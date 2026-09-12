#!/usr/bin/env python3
"""Structured source of truth for Tapgo self-evolution version records.

One JSON file per released version lives in evolution/versions/vX.Y.Z.json.
EVOLUTION.md sections and AppBuilder release notes are rendered from records;
this tool also validates record -> log -> current-version consistency.

Stdlib only, no third-party dependencies.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import plistlib
import re
import sys
import tempfile
from pathlib import Path

VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")
REQUIRED_FIELDS = ("version", "tag", "date", "message", "details", "why", "next", "testStatus")


def repo_root(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit).resolve()
    return Path(__file__).resolve().parent.parent


def versions_dir(root: Path) -> Path:
    return root / "evolution" / "versions"


def record_path(root: Path, version: str) -> Path:
    return versions_dir(root) / f"v{version}.json"


def atomic_write(path: Path, text: str, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp_name, mode)
        os.replace(tmp_name, path)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def load_record(path: Path) -> dict:
    with path.open(encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise ValueError(f"{path}: top-level JSON must be an object")
    return data


def load_all(root: Path) -> list[tuple[Path, dict]]:
    out = []
    for path in sorted(versions_dir(root).glob("v*.json")):
        out.append((path, load_record(path)))
    return out


def validate_record(path: Path, record: dict) -> list[str]:
    errors = []
    for field in REQUIRED_FIELDS:
        if field not in record:
            errors.append(f"{path}: missing field '{field}'")
    version = str(record.get("version", ""))
    if not VERSION_RE.match(version):
        errors.append(f"{path}: invalid version '{version}'")
    if record.get("tag") != f"v{version}":
        errors.append(f"{path}: tag must be v{version}")
    if path.name != f"v{version}.json":
        errors.append(f"{path}: filename must be v{version}.json")
    date = str(record.get("date", ""))
    try:
        dt.date.fromisoformat(date)
    except ValueError:
        errors.append(f"{path}: date must be YYYY-MM-DD")
    if record.get("scope") not in ("mac", "ios"):
        errors.append(f"{path}: scope must be mac|ios")
    for field in ("message", "details", "why", "next", "testStatus"):
        if not str(record.get(field, "")).strip():
            errors.append(f"{path}: field '{field}' must not be empty")
    changes = record.get("changes")
    if not isinstance(changes, list) or not changes or not all(isinstance(x, str) and x.strip() for x in changes):
        errors.append(f"{path}: changes must be a non-empty array of strings")
    return errors


def cmd_add(args: argparse.Namespace) -> int:
    root = repo_root(args.root)
    if not VERSION_RE.match(args.version):
        print(f"ERROR: invalid version '{args.version}'", file=sys.stderr)
        return 2
    path = record_path(root, args.version)
    if path.exists() and not args.force:
        print(f"ERROR: record already exists: {path}", file=sys.stderr)
        return 3
    changes = args.change or [args.message]
    record = {
        "version": args.version,
        "tag": f"v{args.version}",
        "date": args.date or dt.date.today().isoformat(),
        "scope": args.scope,
        "message": args.message,
        "changes": changes,
        "details": args.details,
        "why": args.why,
        "next": args.next,
        "testStatus": args.test_status,
        "commitSha": None,
    }
    errors = validate_record(path, record)
    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 2
    atomic_write(path, json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    print(path.relative_to(root))
    return 0


def cmd_set_field(args: argparse.Namespace) -> int:
    root = repo_root(args.root)
    path = record_path(root, args.version)
    if not path.exists():
        print(f"ERROR: record not found: {path}", file=sys.stderr)
        return 3
    record = load_record(path)
    record[args.field] = args.value
    errors = validate_record(path, record)
    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 2
    atomic_write(path, json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    return 0


def header_for(record: dict) -> str:
    scope = " (iOS)" if record.get("scope") == "ios" else ""
    return f"## v{record['version']}{scope} — {record['message']}"


def render_entry(record: dict) -> str:
    lines = [
        header_for(record),
        f"**Date**: {record['date']}",
        f"**Commit**: _(see `git log -1 v{record['version']}`)_",
        f"**Tag**: v{record['version']}",
        f"**Test status**: {record['testStatus']}",
        "**Changed**:",
    ]
    lines.extend(f"- {item}" for item in record["changes"])
    if str(record.get("details", "")).strip():
        lines.append("")
        lines.append(str(record["details"]).strip())
    lines.extend([
        f"**Why**: {record['why']}",
        f"**Next**: {record['next']}",
    ])
    return "\n".join(lines) + "\n"


def render_notes(record: dict) -> str:
    lines = [
        f"# v{record['version']}",
        "",
        record["message"],
        "",
        "## 变更",
        "",
    ]
    lines.extend(f"- {item}" for item in record["changes"])
    if str(record.get("details", "")).strip():
        lines.extend(["", str(record["details"]).strip()])
    lines.extend(["", "## Next", "", record["next"], ""])
    return "\n".join(lines)


def cmd_render(args: argparse.Namespace) -> int:
    root = repo_root(args.root)
    path = record_path(root, args.version)
    if not path.exists():
        print(f"ERROR: record not found: {path}", file=sys.stderr)
        return 3
    record = load_record(path)
    errors = validate_record(path, record)
    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 2
    text = render_entry(record) if args.kind == "entry" else render_notes(record)
    sys.stdout.write(text)
    return 0


def evo_headers(text: str) -> list[str]:
    return [m.group(1) for m in re.finditer(r"^## v(\d+\.\d+\.\d+)", text, re.M)]


def cmd_validate(args: argparse.Namespace) -> int:
    root = repo_root(args.root)
    errors: list[str] = []
    records = load_all(root)
    seen: dict[str, Path] = {}
    for path, record in records:
        errors.extend(validate_record(path, record))
        version = str(record.get("version", ""))
        if version in seen:
            errors.append(f"duplicate record version {version}: {seen[version]} and {path}")
        seen[version] = path

    evo_path = root / "EVOLUTION.md"
    evo_text = evo_path.read_text(encoding="utf-8") if evo_path.exists() else ""
    headers = evo_headers(evo_text)
    if args.require_rendered:
        for version in seen:
            if version not in headers:
                errors.append(f"EVOLUTION.md missing rendered section for v{version}")

    if args.check_current and records:
        mac_records = [r for _, r in records if r.get("scope", "mac") == "mac"]
        if not mac_records:
            errors.append("no mac record found for --check-current")
        else:
            latest = max(mac_records, key=lambda r: tuple(int(x) for x in r["version"].split(".")))
            plist_path = root / "AppBuilder" / "Info.plist"
            if not plist_path.exists():
                errors.append(f"missing {plist_path}")
            else:
                with plist_path.open("rb") as fh:
                    plist = plistlib.load(fh)
                plist_version = str(plist.get("CFBundleShortVersionString", ""))
                if plist_version != latest["version"]:
                    errors.append(
                        f"Info.plist version {plist_version} != latest record v{latest['version']}"
                    )
            project_path = root / "AppBuilder" / "project.yml"
            if project_path.exists():
                text = project_path.read_text(encoding="utf-8")
                match = re.search(r'MARKETING_VERSION:\s*"([0-9.]+)"', text)
                if not match:
                    errors.append("AppBuilder/project.yml has no quoted MARKETING_VERSION")
                elif match.group(1) != latest["version"]:
                    errors.append(
                        f"project.yml MARKETING_VERSION {match.group(1)} != latest record v{latest['version']}"
                    )

    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1
    print(f"OK: {len(records)} record(s), EVOLUTION.md headers={len(headers)}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    def add_common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--root", default=None, help="repo root (default: auto-detect)")

    p = sub.add_parser("add")
    add_common(p)
    p.add_argument("--version", required=True)
    p.add_argument("--scope", choices=("mac", "ios"), default="mac")
    p.add_argument("--message", required=True)
    p.add_argument("--details", default="_no_summary_")
    p.add_argument("--why", default="Self-evolution iteration — see commit message + diff.")
    p.add_argument("--next", required=True)
    p.add_argument("--test-status", default="pending")
    p.add_argument("--change", action="append", default=None)
    p.add_argument("--date", default=None)
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=cmd_add)

    p = sub.add_parser("set-test-status")
    add_common(p)
    p.add_argument("--version", required=True)
    p.add_argument("--value", required=True)
    p.set_defaults(func=lambda a: cmd_set_field(argparse.Namespace(
        root=a.root, version=a.version, field="testStatus", value=a.value)))

    p = sub.add_parser("render-entry")
    add_common(p)
    p.add_argument("--version", required=True)
    p.set_defaults(func=cmd_render, kind="entry")

    p = sub.add_parser("render-notes")
    add_common(p)
    p.add_argument("--version", required=True)
    p.set_defaults(func=cmd_render, kind="notes")

    p = sub.add_parser("validate")
    add_common(p)
    p.add_argument("--require-rendered", action="store_true")
    p.add_argument("--check-current", action="store_true")
    p.set_defaults(func=cmd_validate)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
