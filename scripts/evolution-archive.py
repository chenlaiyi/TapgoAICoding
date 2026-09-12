#!/usr/bin/env python3
"""Archive old self-evolution history records by month.

Keeps recent records in the live `*_history.jsonl` files and moves older
records to `<state>/archive/<name>-YYYY-MM.jsonl`. Nothing is deleted;
archiving is idempotent and rebuilds each month file as a deduplicated set.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
from pathlib import Path

TIMESTAMP_KEYS = ("ranAt", "builtAt", "date")


def parse_timestamp(record: dict) -> dt.datetime | None:
    for key in TIMESTAMP_KEYS:
        raw = record.get(key)
        if not raw:
            continue
        try:
            return dt.datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
        except ValueError:
            continue
    return None


def write_lines(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as fh:
        for line in lines:
            fh.write(line + "\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def cmd_archive(args: argparse.Namespace) -> int:
    state_dir = Path(args.state_dir).expanduser()
    archive_dir = Path(args.archive_dir).expanduser() if args.archive_dir else state_dir / "archive"
    now = dt.datetime.fromisoformat(args.now.replace("Z", "+00:00")) if args.now else dt.datetime.now(dt.timezone.utc)
    cutoff = now - dt.timedelta(days=args.keep_days)
    moved_total = 0
    for live in sorted(state_dir.glob("*_history.jsonl")):
        lines = [line for line in live.read_text(encoding="utf-8", errors="replace").splitlines() if line.strip()]
        keep, old_by_month = [], {}
        for line in lines:
            try:
                record = json.loads(line)
                timestamp = parse_timestamp(record)
            except json.JSONDecodeError:
                timestamp = None
                record = {}
            if timestamp is not None and timestamp < cutoff:
                old_by_month.setdefault(timestamp.strftime("%Y-%m"), []).append(line)
            else:
                keep.append(line)
        if not old_by_month:
            continue
        for month, old_lines in old_by_month.items():
            archive_path = archive_dir / f"{live.stem}-{month}.jsonl"
            existing = []
            if archive_path.exists():
                existing = [line for line in archive_path.read_text(encoding="utf-8", errors="replace").splitlines() if line.strip()]
            merged = list(dict.fromkeys(existing + old_lines))
            moved_total += len(old_lines)
            if not args.dry_run:
                write_lines(archive_path, merged)
            print(f"archive {live.name}: {len(old_lines)} -> {archive_path.name}")
        if not args.dry_run:
            write_lines(live, keep)
    if args.dry_run:
        print(f"ARCHIVE DRY-RUN: would move {moved_total} record(s), keep_days={args.keep_days}")
    else:
        print(f"ARCHIVE OK: moved {moved_total} record(s), keep_days={args.keep_days}")
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    state_dir = Path(args.state_dir).expanduser()
    archive_dir = Path(args.archive_dir).expanduser() if args.archive_dir else state_dir / "archive"
    for live in sorted(state_dir.glob("*_history.jsonl")):
        count = len([line for line in live.read_text(encoding="utf-8", errors="replace").splitlines() if line.strip()])
        print(f"LIVE {live.name} records={count} bytes={live.stat().st_size}")
    if archive_dir.exists():
        for archived in sorted(archive_dir.glob("*.jsonl")):
            count = len([line for line in archived.read_text(encoding="utf-8", errors="replace").splitlines() if line.strip()])
            print(f"ARCHIVE {archived.name} records={count} bytes={archived.stat().st_size}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("archive")
    p.add_argument("--state-dir", required=True)
    p.add_argument("--archive-dir", default=None)
    p.add_argument("--keep-days", type=int, default=90)
    p.add_argument("--now", default=None)
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(func=cmd_archive)
    p = sub.add_parser("status")
    p.add_argument("--state-dir", required=True)
    p.add_argument("--archive-dir", default=None)
    p.set_defaults(func=cmd_status)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
