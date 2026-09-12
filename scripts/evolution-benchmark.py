#!/usr/bin/env python3
"""Deterministic self-evolution benchmark.

The benchmark is a fixed set of weighted repo-invariant checks (max 100).
`run` executes them and appends a score to a JSONL history; `compare` fails
when the latest score regresses below the previous best.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
from pathlib import Path


def repo_root(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit).resolve()
    return Path(__file__).resolve().parent.parent


def load_spec(root: Path) -> dict:
    return json.loads((root / "evolution" / "benchmark.json").read_text(encoding="utf-8"))


def append_history(path: Path, record: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False) + "\n")
        fh.flush()
        os.fsync(fh.fileno())
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


def load_history(path: Path) -> list[dict]:
    if not path.exists():
        return []
    records = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if line:
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return records


def cmd_run(args: argparse.Namespace) -> int:
    root = repo_root(args.root)
    spec = load_spec(root)
    checks = []
    score = 0
    max_score = sum(int(c.get("weight", 0)) for c in spec["checks"])
    for check in spec["checks"]:
        proc = subprocess.run(
            ["bash", "-c", check["command"]],
            cwd=root, capture_output=True, text=True,
        )
        passed = proc.returncode == 0
        weight = int(check.get("weight", 0))
        if passed:
            score += weight
        checks.append({
            "id": check["id"], "passed": passed, "weight": weight,
            "detail": (proc.stderr or proc.stdout).strip()[:200] if not passed else "",
        })
    record = {
        "schemaVersion": 1,
        "version": args.version or "",
        "ranAt": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "score": score,
        "maxScore": max_score,
        "checks": checks,
    }
    if args.history:
        append_history(Path(args.history), record)
    print(json.dumps({"score": score, "maxScore": max_score,
                      "failed": [c["id"] for c in checks if not c["passed"]]}, ensure_ascii=False))
    return 0


def cmd_compare(args: argparse.Namespace) -> int:
    records = load_history(Path(args.history))
    if not records:
        print("BENCHMARK OK: no previous history")
        return 0
    latest = records[-1]
    previous = records[:-1]
    best_previous = max((r.get("score", 0) for r in previous), default=0)
    score = latest.get("score", 0)
    if previous and score < best_previous:
        print(f"BENCHMARK REGRESSED: latest={score} best_previous={best_previous}", file=sys.stderr)
        return 1
    print(f"BENCHMARK OK: score={score} best_previous={best_previous}")
    return 0


def cmd_latest(args: argparse.Namespace) -> int:
    records = load_history(Path(args.history))
    if not records:
        print("null")
        return 0
    record = records[-1]
    if args.json:
        print(json.dumps(record, ensure_ascii=False, indent=2))
    else:
        print(f"{record.get('score', 0)}/{record.get('maxScore', 100)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("run")
    p.add_argument("--root", default=None)
    p.add_argument("--history", default=None)
    p.add_argument("--version", default="")
    p.set_defaults(func=cmd_run)
    p = sub.add_parser("compare")
    p.add_argument("--history", required=True)
    p.set_defaults(func=cmd_compare)
    p = sub.add_parser("latest")
    p.add_argument("--history", required=True)
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_latest)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
