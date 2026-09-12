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


def percentile(values: list[float], fraction: float) -> float | None:
    """线性插值分位数；空集返回 None。"""
    if not values:
        return None
    xs = sorted(values)
    if len(xs) == 1:
        return xs[0]
    position = (len(xs) - 1) * fraction
    low = int(position)
    high = min(low + 1, len(xs) - 1)
    return xs[low] + (xs[high] - xs[low]) * (position - low)


def ordered_transitions(history: list[dict]) -> list[tuple[dt.datetime, str, str]]:
    """按时间排序的 (时间, 版本, 状态) 迁移序列。"""
    rows = []
    for entry in history:
        version = str(entry.get("version", ""))
        stamp = parse_timestamp(str(entry.get("builtAt", "")))
        if version and stamp is not None:
            rows.append((stamp, version, str(entry.get("status", ""))))
    rows.sort(key=lambda row: row[0])
    return rows


def recovery_samples(rows: list[tuple[dt.datetime, str, str]]) -> tuple[list[float], int]:
    """MTTR 采样：每个失败状态 → 其后第一个终端成功（同版本续跑或下一版发布）。

    返回 (恢复秒数列表, 未恢复失败次数)。未恢复的失败不计入采样但单独计数。
    """
    samples: list[float] = []
    unrecovered = 0
    for index, (stamp, _version, status) in enumerate(rows):
        if status not in FAILED:
            continue
        for later_stamp, _later_version, later_status in rows[index + 1:]:
            if later_status in TERMINAL:
                samples.append((later_stamp - stamp).total_seconds())
                break
        else:
            unrecovered += 1
    return samples, unrecovered


def numeric(entry: dict, key: str) -> float | None:
    value = entry.get(key)
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value))
    except (TypeError, ValueError):
        return None


def collect_test_runs(path: Path) -> list[dict]:
    return load_history(path)


def last_maintenance_reason(record: dict) -> str | None:
    """维护失败原因：优先取失败的子任务原因，其次取最后一条非空原因。"""
    if str(record.get("status", "")) != "failed":
        return None
    for key in ("drill", "archive"):
        section = record.get(key)
        if isinstance(section, dict) and section.get("reason"):
            return str(section["reason"])
    return "unknown"


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
    p95_cycle_seconds = percentile(deltas, 0.95)
    max_cycle_seconds = max(deltas) if deltas else None

    transitions = ordered_transitions(history)
    mttr_values, unrecovered_failures = recovery_samples(transitions)
    mttr_median_seconds = statistics.median(mttr_values) if mttr_values else None
    mttr_p95_seconds = percentile(mttr_values, 0.95)
    last_failure_version = next(
        (version for stamp, version, status in reversed(transitions) if status in FAILED), None)
    last_recovery_seconds = None
    last_failure_index = next(
        (index for index, row in enumerate(reversed(transitions)) if row[2] in FAILED), None)
    if last_failure_index is not None:
        tail = list(reversed(transitions))[:last_failure_index + 1]
        failure_stamp = tail[-1][0]
        for stamp, _version, status in reversed(tail):
            if status in TERMINAL:
                last_recovery_seconds = (stamp - failure_stamp).total_seconds()
                break

    run_durations: list[float] = []
    run_tokens: list[float] = []
    run_costs: list[float] = []
    for entry in final.values():
        duration = numeric(entry, "durationSeconds")
        if duration is not None:
            run_durations.append(duration)
        tokens = numeric(entry, "tokens")
        if tokens is not None:
            run_tokens.append(tokens)
        cost = numeric(entry, "costUSD")
        if cost is not None:
            run_costs.append(cost)
    last_state = max(final.values(), key=lambda e: parse_timestamp(str(e.get("builtAt", ""))) or dt.datetime.min.replace(tzinfo=dt.timezone.utc), default={})

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
    maintenance_path = test_history_path.parent / "maintenance_history.jsonl" if test_history_path else None
    maintenance_runs = load_history(maintenance_path) if maintenance_path else []
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
        "p95CycleSeconds": p95_cycle_seconds,
        "maxCycleSeconds": max_cycle_seconds,
        "mttrMedianSeconds": mttr_median_seconds,
        "mttrP95Seconds": mttr_p95_seconds,
        "mttrSamples": len(mttr_values),
        "unrecoveredFailures": unrecovered_failures,
        "lastFailureVersion": last_failure_version,
        "lastRecoverySeconds": last_recovery_seconds,
        "runDurationSamples": len(run_durations),
        "runDurationMedianSeconds": statistics.median(run_durations) if run_durations else None,
        "runDurationP95Seconds": percentile(run_durations, 0.95),
        "runDurationTotalSeconds": sum(run_durations) if run_durations else None,
        "runTokensTotal": int(sum(run_tokens)) if run_tokens else None,
        "runTokensMedian": statistics.median(run_tokens) if run_tokens else None,
        "runCostUSDTotal": round(sum(run_costs), 4) if run_costs else None,
        "lastRunTokens": int(run_tokens[-1]) if run_tokens else None,
        "lastRunCostUSD": round(run_costs[-1], 4) if run_costs else None,
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
        "maintenanceRuns": len(maintenance_runs),
        "lastMaintenanceStatus": maintenance_runs[-1].get("status") if maintenance_runs else None,
        "lastMaintenanceAt": maintenance_runs[-1].get("ranAt") if maintenance_runs else None,
        "lastMaintenanceReason": last_maintenance_reason(maintenance_runs[-1]) if maintenance_runs else None,
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
    p95 = metrics["p95CycleSeconds"]
    worst = metrics["maxCycleSeconds"]
    if p95 is not None:
        worst_text = "—" if worst is None else f"{worst / 3600:.1f}h"
        print(f"cycle p95 / max:   {p95 / 3600:.1f}h / {worst_text}")
    if metrics["mttrSamples"] or metrics["unrecoveredFailures"]:
        mttr_median = metrics["mttrMedianSeconds"]
        mttr_p95 = metrics["mttrP95Seconds"]
        mttr_text = "n/a" if mttr_median is None else f"median {mttr_median / 3600:.2f}h"
        p95_text = "n/a" if mttr_p95 is None else f"p95 {mttr_p95 / 3600:.2f}h"
        print(f"mttr:              {mttr_text} / {p95_text} over {metrics['mttrSamples']} "
              f"(unrecovered {metrics['unrecoveredFailures']})")
    if metrics["runDurationSamples"]:
        median_run = metrics["runDurationMedianSeconds"] or 0
        p95_run = metrics["runDurationP95Seconds"] or 0
        print(f"run duration:      median {median_run / 60:.1f}m / p95 {p95_run / 60:.1f}m "
              f"over {metrics['runDurationSamples']} run(s)")
    if metrics["runTokensTotal"] is not None or metrics["runCostUSDTotal"] is not None:
        tokens = metrics["runTokensTotal"]
        cost = metrics["runCostUSDTotal"]
        tokens_text = "n/a" if tokens is None else f"{tokens}"
        cost_text = "n/a" if cost is None else f"${cost:.2f}"
        print(f"run cost:          tokens={tokens_text} cost={cost_text} "
              f"(last tokens={metrics['lastRunTokens']} cost={metrics['lastRunCostUSD']})")
    print(f"tests (last-state): {metrics['testPassedTotal']} across {metrics['testVersions']} versions")
    print(f"backlog:           {metrics['openBacklog']} open / {metrics['doneBacklog']} done")
    print(f"test runs:         {metrics['testRuns']} (last {metrics['lastTestStatus'] or 'n/a'})")
    print(f"flaky sections:    {metrics['flakyCount']}")
    print(f"model eval:        runs={metrics['modelEvalRuns']} latest={metrics['modelEvalLatestScore']} best={metrics['modelEvalBestScore']}")
    print(f"rollback drill:    runs={metrics['rollbackDrillRuns']} last={metrics['lastRollbackDrillTag']} passed={metrics['lastRollbackDrillPassed']}")
    print(f"maintenance:       runs={metrics['maintenanceRuns']} last={metrics['lastMaintenanceStatus']} at={metrics['lastMaintenanceAt']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
