#!/usr/bin/env python3
"""Summarize self-evolution health from records + state history."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import statistics
import sys
from pathlib import Path

TERMINAL = {"published", "local_built"}
FAILED = {"push_failed", "release_failed", "health_failed", "worktree_verify_failed", "benchmark_regressed"}


def repo_root(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit).resolve()
    return Path(__file__).resolve().parent.parent


def load_records(root: Path) -> list[dict]:
    records = []
    for path in sorted((root / "evolution" / "versions").glob("v*.json")):
        try:
            records.append(json.loads(path.read_text(encoding="utf-8")))
        except (OSError, json.JSONDecodeError):
            continue
    return records


def load_history(path: Path) -> list[dict]:
    entries = []
    if not path.exists():
        return entries
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return entries


def parse_timestamp(value: str) -> dt.datetime | None:
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def parse_passed(value: str) -> int:
    match = re.search(r"(\d+)\s+passed", value or "")
    return int(match.group(1)) if match else 0


def collect_test_runs(path: Path) -> list[dict]:
    return load_history(path)


def collect_metrics(root: Path, history_path: Path, test_history_path: Path | None = None) -> dict:
    records = load_records(root)
    history = load_history(history_path)

    final: dict[str, dict] = {}
    for entry in history:
        version = str(entry.get("version", ""))
        if version:
            final[version] = entry  # later transitions win

    statuses = [str(e.get("status", "")) for e in final.values()]
    published = statuses.count("published")
    local_built = statuses.count("local_built")
    failed = sum(1 for s in statuses if s in FAILED)
    other = len(statuses) - published - local_built - failed
    terminal_total = published + local_built + failed
    success_rate = (published + local_built) / terminal_total if terminal_total else None

    terminal_times = []
    for version, entry in final.items():
        if str(entry.get("status", "")) in TERMINAL:
            ts = parse_timestamp(str(entry.get("builtAt", "")))
            if ts is not None:
                terminal_times.append((ts, version))
    terminal_times.sort()
    deltas = [
        (terminal_times[i][0] - terminal_times[i - 1][0]).total_seconds()
        for i in range(1, len(terminal_times))
    ]
    median_cycle_seconds = statistics.median(deltas) if deltas else None

    test_total = 0
    test_versions = 0
    for entry in final.values():
        passed = parse_passed(str(entry.get("testStatus", "")))
        if passed:
            test_total += passed
            test_versions += 1

    test_runs = collect_test_runs(test_history_path) if test_history_path else []
    model_eval_path = test_history_path.parent / "model_eval_history.jsonl" if test_history_path else None
    rollback_path = test_history_path.parent / "rollback_drill_history.jsonl" if test_history_path else None
    rollback_runs = load_history(rollback_path) if rollback_path else []
    model_eval_runs = load_history(model_eval_path) if model_eval_path else []
    model_eval_scores = [float(r.get("score", 0)) for r in model_eval_runs]
    flaky_sections = set()
    for record in test_runs:
        failed_sections = {item.get("section") for item in record.get("failedSections", [])}
        for rerun in record.get("reruns", []):
            if rerun.get("section") in failed_sections and rerun.get("passed"):
                flaky_sections.add(rerun.get("section"))
    last_test = test_runs[-1] if test_runs else {}

    backlog_path = root / "evolution" / "BACKLOG.md"
    backlog_text = backlog_path.read_text(encoding="utf-8") if backlog_path.exists() else ""
    open_backlog = len(re.findall(r"^- \[ \] ", backlog_text, re.M))
    done_backlog = len(re.findall(r"^- \[x\] ", backlog_text, re.M))

    latest_record = None
    if records:
        latest = max(records, key=lambda r: tuple(int(x) for x in str(r["version"]).split(".")))
        latest_record = {"version": latest["version"], "date": latest.get("date"), "testStatus": latest.get("testStatus")}

    return {
        "recordCount": len(records),
        "latestRecord": latest_record,
        "historyEntries": len(history),
        "iterations": len(final),
        "published": published,
        "localBuilt": local_built,
        "failed": failed,
        "other": other,
        "successRate": success_rate,
        "medianCycleSeconds": median_cycle_seconds,
        "testPassedTotal": test_total,
        "testVersions": test_versions,
        "openBacklog": open_backlog,
        "doneBacklog": done_backlog,
        "testRuns": len(test_runs),
        "lastTestStatus": last_test.get("status"),
        "flakyCount": len(flaky_sections),
        "flakySections": sorted(flaky_sections),
        "lastEnvironmentFailures": last_test.get("environmentFailures", 0),
        "lastRealFailures": last_test.get("realFailures", 0),
        "modelEvalRuns": len(model_eval_runs),
        "modelEvalLatestScore": model_eval_scores[-1] if model_eval_scores else None,
        "modelEvalBestScore": max(model_eval_scores) if model_eval_scores else None,
        "modelEvalLastTokens": model_eval_runs[-1].get("totalTokens") if model_eval_runs else None,
        "modelEvalLastCostUSD": model_eval_runs[-1].get("totalCostUSD") if model_eval_runs else None,
        "modelEvalLastDuration": model_eval_runs[-1].get("totalDurationSeconds") if model_eval_runs else None,
        "rollbackDrillRuns": len(rollback_runs),
        "lastRollbackDrillTag": rollback_runs[-1].get("tag") if rollback_runs else None,
        "lastRollbackDrillPassed": rollback_runs[-1].get("passed") if rollback_runs else None,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=None)
    parser.add_argument("--history", default=None)
    parser.add_argument("--test-history", default=None)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    root = repo_root(args.root)
    history_path = Path(args.history).expanduser() if args.history else (
        Path.home() / "Library" / "Application Support" / "Tapgo AICoding" / "state" / "evolution_state_history.jsonl"
    )
    test_history_path = Path(args.test_history).expanduser() if args.test_history else (
        history_path.parent / "test_run_history.jsonl"
    )
    metrics = collect_metrics(root, history_path, test_history_path)

    if args.json:
        print(json.dumps(metrics, ensure_ascii=False, indent=2))
        return 0

    rate = metrics["successRate"]
    rate_text = "n/a" if rate is None else f"{rate * 100:.1f}%"
    cycle = metrics["medianCycleSeconds"]
    cycle_text = "n/a" if cycle is None else f"{cycle / 3600:.1f}h"
    latest = metrics["latestRecord"]
    latest_text = "n/a" if not latest else f"v{latest['version']} ({latest['date']})"
    print(f"latest record:     {latest_text}")
    print(f"records:           {metrics['recordCount']}")
    print(f"iterations:        {metrics['iterations']} (history entries {metrics['historyEntries']})")
    print(f"published:         {metrics['published']}")
    print(f"local built:       {metrics['localBuilt']}")
    print(f"failed:            {metrics['failed']}")
    print(f"success rate:      {rate_text}")
    print(f"median cycle:      {cycle_text}")
    print(f"tests (last-state): {metrics['testPassedTotal']} across {metrics['testVersions']} versions")
    print(f"backlog:           {metrics['openBacklog']} open / {metrics['doneBacklog']} done")
    print(f"test runs:         {metrics['testRuns']} (last {metrics['lastTestStatus'] or 'n/a'})")
    print(f"flaky sections:    {metrics['flakyCount']}")
    print(f"model eval:        runs={metrics['modelEvalRuns']} latest={metrics['modelEvalLatestScore']} best={metrics['modelEvalBestScore']}")
    print(f"rollback drill:    runs={metrics['rollbackDrillRuns']} last={metrics['lastRollbackDrillTag']} passed={metrics['lastRollbackDrillPassed']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
