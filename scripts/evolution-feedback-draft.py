#!/usr/bin/env python3
"""Extract minimal-reproduction candidates from feedback snapshots.

Reads Markdown snapshots written by SessionStore.snapshotActiveThreadForFeedback,
scores user-input lines by bug-report keywords, and appends de-duplicated draft
entries to evolution/feedback/drafts.json. It never modifies the covered
registry; promotion to a real check is an explicit human step.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import sys
from pathlib import Path

KEYWORDS = ("问题", "不能", "无法", "失败", "报错", "崩溃", "不对", "错误",
            "应该是", "希望", "请修复", "bug", "crash", "error", "wrong", "should")
INPUT_RE = re.compile(r"###\s+turn\s+\d+\s*\n```\n(.*?)\n```", re.S)


def repo_root(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit).resolve()
    return Path(__file__).resolve().parent.parent


def load_drafts(path: Path) -> dict:
    if not path.exists():
        return {"version": 1, "drafts": []}
    return json.loads(path.read_text(encoding="utf-8"))


def extract_candidates(text: str) -> list[str]:
    candidates = []
    for block in INPUT_RE.findall(text):
        for line in block.splitlines():
            line = line.strip(" -\t")
            if not line or len(line) < 6:
                continue
            lowered = line.lower()
            if any(keyword.lower() in lowered for keyword in KEYWORDS):
                candidates.append(line[:240])
    return candidates


def draft_id(title: str) -> str:
    digest = hashlib.sha1(title.encode("utf-8")).hexdigest()[:8].upper()
    return f"DRAFT-{digest}"


def cmd_list(args: argparse.Namespace) -> int:
    path = Path(args.out) if args.out else repo_root(args.root) / "evolution/feedback/drafts.json"
    for draft in load_drafts(path).get("drafts", []):
        print(f"{draft['id']}\t{draft['title']}\t({draft.get('source','')})")
    return 0


def cmd_discover(args: argparse.Namespace) -> int:
    root = repo_root(args.root)
    feedback_dir = Path(args.feedback_dir).expanduser() if args.feedback_dir else (
        Path.home() / "Library/Application Support/Tapgo AICoding/feedback"
    )
    out = Path(args.out) if args.out else root / "evolution/feedback/drafts.json"
    data = load_drafts(out)
    known = {d["id"] for d in data.get("drafts", [])}
    added = 0
    if feedback_dir.exists():
        for snapshot in sorted(feedback_dir.glob("*.md")):
            for title in extract_candidates(snapshot.read_text(encoding="utf-8", errors="replace")):
                ident = draft_id(title)
                if ident in known:
                    continue
                known.add(ident)
                mtime = dt.datetime.fromtimestamp(snapshot.stat().st_mtime, dt.timezone.utc)
                data["drafts"].append({
                    "id": ident,
                    "title": title,
                    "source": snapshot.name,
                    "reported": mtime.strftime("%Y-%m-%d"),
                    "status": "draft",
                    "suggestedCheck": "",
                })
                added += 1
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"DRAFTS OK: +{added} new, total={len(data.get('drafts', []))} source={feedback_dir}")
    return 0


def cmd_render(args: argparse.Namespace) -> int:
    root = repo_root(args.root)
    path = Path(args.out) if args.out else root / "evolution/feedback/drafts.json"
    for draft in load_drafts(path).get("drafts", []):
        print(f"- [ ] **{draft['id']}** {draft['title']}")
        print(f"  - source: `{draft.get('source','')}` reported: {draft.get('reported','')}")
        print("  - 建议补充最小复现 check 后，将其提升到 `registry.json`")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("list"); p.add_argument("--root", default=None); p.add_argument("--out", default=None); p.set_defaults(func=cmd_list)
    p = sub.add_parser("discover")
    p.add_argument("--root", default=None)
    p.add_argument("--feedback-dir", default=None)
    p.add_argument("--out", default=None)
    p.set_defaults(func=cmd_discover)
    p = sub.add_parser("render"); p.add_argument("--root", default=None); p.add_argument("--out", default=None); p.set_defaults(func=cmd_render)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
