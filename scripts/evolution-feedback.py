#!/usr/bin/env python3
"""Run the user-feedback regression registry.

Each registry entry pins a real reported issue to a minimal reproducible check
(source guard or an existing test section). `verify` fails when any covered
feedback regresses.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def repo_root(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit).resolve()
    return Path(__file__).resolve().parent.parent


def load_entries(root: Path) -> list[dict]:
    data = json.loads((root / "evolution" / "feedback" / "registry.json").read_text(encoding="utf-8"))
    return [e for e in data.get("entries", []) if e.get("status", "covered") == "covered"]


def cmd_list(args: argparse.Namespace) -> int:
    for entry in load_entries(repo_root(args.root)):
        print(f"{entry['id']}\t{entry['weight']}\t{entry['title']}\t({entry['reported']})")
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    root = repo_root(args.root)
    entries = load_entries(root)
    total = sum(int(e["weight"]) for e in entries) or 1
    earned = 0
    failed = []
    for entry in entries:
        proc = subprocess.run(["bash", "-c", entry["check"]], cwd=root, capture_output=True, text=True)
        if proc.returncode == 0:
            earned += int(entry["weight"])
        else:
            failed.append(entry["id"])
    score = round(earned / total * 100, 2)
    if failed:
        print(f"FEEDBACK REGRESSED: score={score} failed={failed}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps({"score": score, "entries": len(entries), "failed": []}, ensure_ascii=False))
    else:
        print(f"FEEDBACK REGRESSIONS OK: score={score} entries={len(entries)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("list")
    p.add_argument("--root", default=None)
    p.set_defaults(func=cmd_list)
    p = sub.add_parser("verify")
    p.add_argument("--root", default=None)
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_verify)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
