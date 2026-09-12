#!/usr/bin/env python3
"""Parse TapgoTests output and record flaky-vs-real failure evidence."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path

ENV_PATTERNS = (
    "auth.json not present",
    "sshFailed",
    "Operation timed out",
    "connect to host",
    "Connection refused",
    "No route to host",
)

SUMMARY_RE = re.compile(r"—\s*(\d+)\s+passed,\s*(\d+)\s+failed\s*—")
SECTION_RE = re.compile(r"^\[end\]\s+(.+?)\s+\[FAIL\]\s+passed=(\d+)\s+failed=(\d+)", re.M)
CASE_RE = re.compile(r"^\s*✗\s+(.*?)\s+\((.+?):(\d+)\)\s*$", re.M)
PROTOCOL_RE = re.compile(r"^\[([^\]]+)\]\s+END:\s+FAIL\s*$", re.M)


def classify(message: str) -> str:
    lowered = message.lower()
    for pattern in ENV_PATTERNS:
        if pattern.lower() in lowered:
            return "environment"
    return "real"


def parse_log(text: str) -> dict:
    summary = SUMMARY_RE.search(text)
    passed = int(summary.group(1)) if summary else 0
    failed = int(summary.group(2)) if summary else 0

    failed_sections = [
        {"section": m.group(1).strip(), "passed": int(m.group(2)), "failed": int(m.group(3))}
        for m in SECTION_RE.finditer(text)
    ]
    cases = []
    for m in CASE_RE.finditer(text):
        message = m.group(1).strip()
        cases.append({"message": message, "file": m.group(2).strip(), "line": int(m.group(3)), "kind": classify(message)})
    for m in PROTOCOL_RE.finditer(text):
        message = f"{m.group(1)}: protocol END FAIL"
        cases.append({"message": message, "file": "", "line": 0, "kind": classify(message)})

    # De-duplicate protocol/case overlaps while preserving order.
    seen = set()
    unique_cases = []
    for case in cases:
        key = (case["message"], case["file"], case["line"])
        if key in seen:
            continue
        seen.add(key)
        unique_cases.append(case)

    return {
        "passed": passed,
        "failed": failed,
        "failedSections": failed_sections,
        "cases": unique_cases,
        "environmentFailures": sum(1 for c in unique_cases if c["kind"] == "environment"),
        "realFailures": sum(1 for c in unique_cases if c["kind"] == "real"),
    }


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
    records = []
    if not path.exists():
        return records
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return records


def cmd_parse(args: argparse.Namespace) -> int:
    text = Path(args.log).read_text(encoding="utf-8", errors="replace") if args.log != "-" else sys.stdin.read()
    print(json.dumps(parse_log(text), ensure_ascii=False, indent=2))
    return 0


def cmd_record(args: argparse.Namespace) -> int:
    text = Path(args.log).read_text(encoding="utf-8", errors="replace")
    parsed = parse_log(text)
    reruns = json.loads(args.reruns) if args.reruns else []
    record = {
        "schemaVersion": 1,
        "version": args.version,
        "ranAt": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "status": args.status,
        "passed": parsed["passed"],
        "failed": parsed["failed"],
        "failedSections": parsed["failedSections"],
        "cases": parsed["cases"],
        "reruns": reruns,
        "environmentFailures": parsed["environmentFailures"],
        "realFailures": parsed["realFailures"],
    }
    append_history(Path(args.history), record)
    print(json.dumps({"status": record["status"], "failed": record["failed"],
                      "environmentFailures": record["environmentFailures"],
                      "realFailures": record["realFailures"]}, ensure_ascii=False))
    return 0


def cmd_flaky(args: argparse.Namespace) -> int:
    records = load_history(Path(args.history))
    flaky_sections = set()
    for record in records:
        failed_sections = {item["section"] for item in record.get("failedSections", [])}
        for rerun in record.get("reruns", []):
            section = str(rerun.get("section", ""))
            if section in failed_sections and rerun.get("passed"):
                flaky_sections.add(section)
    last = records[-1] if records else {}
    summary = {
        "runs": len(records),
        "lastStatus": last.get("status"),
        "lastFailed": last.get("failed", 0),
        "flakySections": sorted(flaky_sections),
        "flakyCount": len(flaky_sections),
        "environmentFailures": last.get("environmentFailures", 0),
        "realFailures": last.get("realFailures", 0),
    }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("parse")
    p.add_argument("--log", required=True)
    p.set_defaults(func=cmd_parse)

    p = sub.add_parser("record")
    p.add_argument("--log", required=True)
    p.add_argument("--history", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--status", choices=("pass", "fail"), required=True)
    p.add_argument("--reruns", default="")
    p.set_defaults(func=cmd_record)

    p = sub.add_parser("flaky")
    p.add_argument("--history", required=True)
    p.set_defaults(func=cmd_flaky)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
