#!/usr/bin/env python3
"""Model-level evaluation harness for self-evolution.

This tool never invokes a model itself. It prepares fixed fixtures and calls
the command in EVOLVE_MODEL_RUNNER (or --runner) once per task. Operators must
explicitly provide a runner, so Codex never silently delegates work to another
agent. `verify-references` is fully deterministic and proves each task's
fixture + checks are well-formed.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def repo_root(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit).resolve()
    return Path(__file__).resolve().parent.parent


def load_tasks(root: Path) -> list[dict]:
    data = json.loads((root / "evolution" / "model-eval" / "tasks.json").read_text(encoding="utf-8"))
    return list(data["tasks"])


def stage_task(root: Path, task: dict) -> Path:
    workdir = Path(tempfile.mkdtemp(prefix=f"tapgo-eval-{task['id']}-"))
    shutil.copytree(root / "evolution" / "model-eval" / "fixtures" / task["fixture"], workdir, dirs_exist_ok=True)
    return workdir


def run_checks(task: dict, workdir: Path) -> list[dict]:
    results = []
    for check in task.get("checks", []):
        proc = subprocess.run(["bash", "-c", check["command"]], cwd=workdir, capture_output=True, text=True)
        results.append({
            "command": check["command"],
            "passed": proc.returncode == 0,
            "detail": (proc.stderr or proc.stdout).strip()[:200],
        })
    return results


def cmd_list(args: argparse.Namespace) -> int:
    tasks = load_tasks(repo_root(args.root))
    for task in tasks:
        print(f"{task['id']}\t{task['weight']}\t{task['prompt'][:80]}")
    return 0


def cmd_verify_references(args: argparse.Namespace) -> int:
    root = repo_root(args.root)
    failures = []
    for task in load_tasks(root):
        workdir = stage_task(root, task)
        try:
            reference = root / "evolution" / "model-eval" / "reference" / task["fixture"]
            if reference.exists():
                shutil.copytree(reference, workdir, dirs_exist_ok=True)
            checks = run_checks(task, workdir)
            if not all(c["passed"] for c in checks):
                failures.append(task["id"])
        finally:
            shutil.rmtree(workdir, ignore_errors=True)
    if failures:
        print(f"MODEL EVAL REFERENCES FAILED: {failures}", file=sys.stderr)
        return 1
    print(f"MODEL EVAL REFERENCES OK: {len(load_tasks(root))} task(s)")
    return 0


def cmd_run(args: argparse.Namespace) -> int:
    root = repo_root(args.root)
    tasks = load_tasks(root)
    if args.tasks:
        wanted = set(args.tasks.split(","))
        tasks = [t for t in tasks if t["id"] in wanted]
    runner = args.runner or os.environ.get("EVOLVE_MODEL_RUNNER", "")
    if not runner:
        print("ERROR: no runner. Set EVOLVE_MODEL_RUNNER or pass --runner.", file=sys.stderr)
        print("       This tool never invokes a model by itself.", file=sys.stderr)
        return 2

    results = []
    total_weight = sum(int(t["weight"]) for t in tasks)
    earned = 0
    spent_tokens = 0
    spent_cost = 0.0
    aborted_reason = None
    wall_started = time.monotonic()

    for task in tasks:
        if args.max_duration_seconds > 0 and time.monotonic() - wall_started > args.max_duration_seconds:
            aborted_reason = "max_duration"
            break
        if args.max_tokens > 0 and spent_tokens > args.max_tokens:
            aborted_reason = "max_tokens"
            break
        if args.max_cost_usd > 0 and spent_cost > args.max_cost_usd:
            aborted_reason = "max_cost"
            break

        workdir = stage_task(root, task)
        env = os.environ.copy()
        env.update({
            "EVO_EVAL_TASK_ID": task["id"],
            "EVO_EVAL_WORKDIR": str(workdir),
            "EVO_EVAL_PROMPT": task["prompt"],
        })
        started = time.monotonic()
        timed_out = False
        try:
            proc = subprocess.run(
                ["bash", "-c", runner], env=env, capture_output=True, text=True,
                timeout=args.timeout_seconds if args.timeout_seconds > 0 else None,
            )
            runner_exit = proc.returncode
            stdout = proc.stdout or ""
        except subprocess.TimeoutExpired as exc:
            timed_out = True
            runner_exit = -1
            stdout = exc.stdout.decode() if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        duration = time.monotonic() - started
        checks = run_checks(task, workdir)
        passed = (not timed_out) and runner_exit == 0 and all(c["passed"] for c in checks)
        if passed:
            earned += int(task["weight"])
        tokens = None
        cost = None
        for line in reversed(stdout.splitlines()):
            try:
                payload = json.loads(line)
                tokens = payload.get("total_tokens", tokens)
                cost = payload.get("cost_usd", cost)
                break
            except json.JSONDecodeError:
                continue
        spent_tokens += tokens or 0
        spent_cost += cost or 0
        results.append({
            "taskId": task["id"],
            "passed": passed,
            "weight": int(task["weight"]),
            "durationSeconds": round(duration, 3),
            "runnerExit": runner_exit,
            "timedOut": timed_out,
            "tokens": tokens,
            "costUSD": cost,
            "checks": checks,
        })
        shutil.rmtree(workdir, ignore_errors=True)

    score = (earned / total_weight * 100) if total_weight else 0
    record = {
        "version": args.version or "",
        "ranAt": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "score": round(score, 2),
        "maxScore": 100,
        "totalDurationSeconds": round(sum(r["durationSeconds"] for r in results), 3),
        "totalTokens": sum(r["tokens"] or 0 for r in results) or None,
        "totalCostUSD": sum(r["costUSD"] or 0 for r in results) or None,
        "limits": {
            "timeoutSeconds": args.timeout_seconds,
            "maxTokens": args.max_tokens,
            "maxCostUSD": args.max_cost_usd,
            "maxDurationSeconds": args.max_duration_seconds,
        },
        "aborted": aborted_reason,
        "completedTasks": len(results),
        "totalTasks": len(tasks),
        "tasks": results,
    }
    if args.out:
        path = Path(args.out)
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, ensure_ascii=False) + "\n")
            fh.flush()
            os.fsync(fh.fileno())
    print(json.dumps({
        "score": record["score"],
        "failed": [r["taskId"] for r in results if not r["passed"]],
        "aborted": record["aborted"],
        "completedTasks": record["completedTasks"],
        "totalTasks": record["totalTasks"],
        "totalDurationSeconds": record["totalDurationSeconds"],
        "totalTokens": record["totalTokens"],
        "totalCostUSD": record["totalCostUSD"],
    }, ensure_ascii=False))
    if aborted_reason:
        return 3
    if args.fail_under is not None and score < args.fail_under:
        return 1
    return 0


def cmd_report(args: argparse.Namespace) -> int:
    path = Path(args.history)
    if not path.exists():
        print("no model-eval history")
        return 0
    lines = [line for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not lines:
        print("no model-eval history")
        return 0
    latest = json.loads(lines[-1])
    best = max((json.loads(line).get("score", 0) for line in lines), default=0)
    print(f"score={latest.get('score')} best={best} duration={latest.get('totalDurationSeconds')}s "
          f"tokens={latest.get('totalTokens')} cost={latest.get('totalCostUSD')}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("list"); p.add_argument("--root", default=None); p.set_defaults(func=cmd_list)
    p = sub.add_parser("verify-references"); p.add_argument("--root", default=None); p.set_defaults(func=cmd_verify_references)
    p = sub.add_parser("run")
    p.add_argument("--root", default=None)
    p.add_argument("--runner", default=None)
    p.add_argument("--tasks", default=None)
    p.add_argument("--out", default=None)
    p.add_argument("--version", default="")
    p.add_argument("--fail-under", type=float, default=None)
    p.add_argument("--timeout-seconds", type=float, default=300)
    p.add_argument("--max-tokens", type=int, default=200000)
    p.add_argument("--max-cost-usd", type=float, default=5.0)
    p.add_argument("--max-duration-seconds", type=float, default=1800)
    p.set_defaults(func=cmd_run)
    p = sub.add_parser("report"); p.add_argument("--history", required=True); p.set_defaults(func=cmd_report)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
