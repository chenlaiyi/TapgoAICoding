#!/usr/bin/env python3
"""Parse evolution/BACKLOG.md and surface the highest-priority open item."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

HEADER_RE = re.compile(r"^##\s+(P\d)\b")
ITEM_RE = re.compile(r"^-\s+\[( |x|X)\]\s+\*\*(EVO-\d+)\s+(.*?)\*\*(?::|：)?\s*(.*)$")


def repo_root(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit).resolve()
    return Path(__file__).resolve().parent.parent


def parse(text: str) -> list[dict]:
    items = []
    priority = "P?"
    for line in text.splitlines():
        header = HEADER_RE.match(line.strip())
        if header:
            priority = header.group(1)
            continue
        match = ITEM_RE.match(line.strip())
        if not match:
            continue
        done = match.group(1).lower() == "x"
        items.append({
            "id": match.group(2),
            "priority": priority,
            "title": match.group(3).strip(),
            "detail": match.group(4).strip(),
            "done": done,
        })
    return items


def load(root: Path) -> list[dict]:
    path = root / "evolution" / "BACKLOG.md"
    if not path.exists():
        return []
    return parse(path.read_text(encoding="utf-8"))


def cmd_list(args: argparse.Namespace) -> int:
    items = load(repo_root(args.root))
    if not args.all:
        items = [i for i in items if not i["done"]]
    if args.json:
        print(json.dumps(items, ensure_ascii=False, indent=2))
    else:
        for item in items:
            mark = "x" if item["done"] else " "
            print(f"[{mark}] {item['priority']} {item['id']} {item['title']}: {item['detail']}")
    return 0


def cmd_top(args: argparse.Namespace) -> int:
    items = [i for i in load(repo_root(args.root)) if not i["done"]]
    if not items:
        return 1
    item = items[0]
    if args.json:
        print(json.dumps(item, ensure_ascii=False, indent=2))
    else:
        detail = f": {item['detail']}" if item["detail"] else ""
        print(f"{item['id']} {item['title']}{detail}")
    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    root = repo_root(args.root)
    items = load(root)
    errors = []
    seen = set()
    for item in items:
        if item["id"] in seen:
            errors.append(f"duplicate backlog id: {item['id']}")
        seen.add(item["id"])
        if not item["title"]:
            errors.append(f"{item['id']}: empty title")
        if item["priority"] == "P?":
            errors.append(f"{item['id']}: missing Pn section")
    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1
    open_count = sum(1 for i in items if not i["done"])
    print(f"OK: {len(items)} items, {open_count} open, {len(items) - open_count} done")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    def common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--root", default=None)

    p = sub.add_parser("list")
    common(p)
    p.add_argument("--json", action="store_true")
    p.add_argument("--all", action="store_true")
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("top")
    common(p)
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_top)

    p = sub.add_parser("validate")
    common(p)
    p.set_defaults(func=cmd_validate)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
