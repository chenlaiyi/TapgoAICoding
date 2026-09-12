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
SECTION_RE = re.compile(r'"([^"]+)"')

CATEGORY_RULES = [
    ("quota", ["额度", "用量", "剩余", "quota", "余额"], ["quota", "remaining", "used", "balance"]),
    ("performance", ["cpu", "卡顿", "性能", "每个字符", "保存"], ["debounce", "scheduleSave", "cpu"]),
    ("release", ["签名", "helper", "更新", "版本落后", "release"], ["AppUpdate", "Helper", "release", "version"]),
    ("version-sync", ["同步", "日志", "makehistory"], ["Evolution log sync", "makeHistory", "version"]),
    ("ui", ["输入", "快捷键", "按钮", "界面", "样式", "布局", "显示", "问号"], ["desktop-design", "Conversation", "Sidebar", "presentation"]),
    ("regression", ["崩溃", "报错", "失败", "错误", "crash", "error", "回归"], []),
]


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


def load_test_sections(path: Path) -> list[str]:
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8")
    start = text.find("let allSections")
    if start < 0:
        return []
    assign = text.find("= [", start)
    if assign < 0:
        return []
    end = text.find("]", assign)
    return SECTION_RE.findall(text[assign:end if end > 0 else len(text)])


def suggest_for(title: str, sections: list[str]) -> dict:
    lowered = title.lower()
    kind = "regression"
    tokens: list[str] = []
    for candidate_kind, keywords, section_tokens in CATEGORY_RULES:
        if any(keyword.lower() in lowered for keyword in keywords):
            kind = candidate_kind
            tokens = section_tokens
            break
    candidates = []
    for section in sections:
        if any(token.lower() in section.lower() for token in tokens):
            candidates.append(section)
        if len(candidates) >= 3:
            break
    if candidates:
        suggested = f"xcrun -sdk macosx26.5 swift run TapgoTests --filter '{candidates[0]}' >/dev/null"
    elif kind == "quota":
        suggested = "python3 -c '# TODO: 补最小复现响应样例，断言 used = total - remaining'"
    else:
        suggested = "# TODO: 补最小复现 fixture / 源码守卫后填写 command"
    return {
        "suggestedCheck": suggested,
        "suggestionKind": kind,
        "candidateSections": candidates,
    }


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


def cmd_suggest(args: argparse.Namespace) -> int:
    root = repo_root(args.root)
    path = Path(args.out) if args.out else root / "evolution/feedback/drafts.json"
    testmain = Path(args.testmain) if args.testmain else root / "Sources/TapgoTests/TestMain.swift"
    sections = load_test_sections(testmain)
    data = load_drafts(path)
    updated = 0
    for draft in data.get("drafts", []):
        suggestion = suggest_for(draft["title"], sections)
        for key, value in suggestion.items():
            if draft.get(key) != value:
                draft[key] = value
                updated += 1
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"SUGGEST OK: {len(data.get('drafts', []))} draft(s), {updated} field update(s), sections={len(sections)}")
    return 0


def cmd_render(args: argparse.Namespace) -> int:
    root = repo_root(args.root)
    path = Path(args.out) if args.out else root / "evolution/feedback/drafts.json"
    for draft in load_drafts(path).get("drafts", []):
        print(f"- [ ] **{draft['id']}** {draft['title']}")
        print(f"  - source: `{draft.get('source','')}` reported: {draft.get('reported','')}")
        if draft.get("suggestionKind"):
            print(f"  - kind: `{draft['suggestionKind']}`")
        if draft.get("suggestedCheck"):
            print(f"  - suggested check: `{draft['suggestedCheck']}`")
        if draft.get("candidateSections"):
            print("  - candidate sections: " + ", ".join(draft["candidateSections"]))
        print("  - 人工确认后，将最小复现 check 提升到 `registry.json`")
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
    p = sub.add_parser("suggest")
    p.add_argument("--root", default=None)
    p.add_argument("--out", default=None)
    p.add_argument("--testmain", default=None)
    p.set_defaults(func=cmd_suggest)
    p = sub.add_parser("render"); p.add_argument("--root", default=None); p.add_argument("--out", default=None); p.set_defaults(func=cmd_render)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
