#!/usr/bin/env python3
"""Protected-path gate for self-evolution.

Certain files define the gate itself (evolve.sh, tests, AGENTS.md). Changing
them requires an explicit approval token derived from the exact new contents.
The token is printed for the operator; evolve.sh refuses to start unless the
same token is passed via --approve-protected.

This is a procedural guardrail, not a cryptographic boundary: its purpose is
to make self-modification of the gate visible, explicit and auditable.
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import subprocess
import sys
from pathlib import Path


def repo_root(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit).resolve()
    return Path(__file__).resolve().parent.parent


def load_paths(root: Path) -> list[str]:
    manifest = root / "evolution" / "protected-paths.json"
    data = json.loads(manifest.read_text(encoding="utf-8"))
    return list(data.get("paths", []))


def git(root: Path, *args: str) -> str:
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)
    return result.stdout


def is_protected(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in patterns)


def changed_paths(root: Path, base: str, patterns: list[str]) -> list[str]:
    changed: set[str] = set()
    for line in git(root, "diff", "--name-only", base, "--").splitlines():
        path = line.strip()
        if path and is_protected(path, patterns):
            changed.add(path)
    for line in git(root, "ls-files", "--others", "--exclude-standard").splitlines():
        path = line.strip()
        if path and is_protected(path, patterns):
            changed.add(path)
    return sorted(changed)


def approval_token(root: Path, paths: list[str]) -> str:
    digest = hashlib.sha256()
    for path in paths:
        digest.update(path.encode("utf-8"))
        digest.update(b"\0")
        file_path = root / path
        if file_path.exists() and file_path.is_file():
            digest.update(file_path.read_bytes())
        else:
            digest.update(b"<deleted>")
        digest.update(b"\0")
    return digest.hexdigest()[:16]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=None)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("status")
    p.add_argument("--base", required=True)
    p.set_defaults(command_name="status")

    p = sub.add_parser("token")
    p.add_argument("--base", required=True)
    p.set_defaults(command_name="token")

    p = sub.add_parser("check")
    p.add_argument("--base", required=True)
    p.add_argument("--approve", default="")
    p.set_defaults(command_name="check")

    args = parser.parse_args()
    root = repo_root(args.root)
    patterns = load_paths(root)
    changed = changed_paths(root, args.base, patterns)
    token = approval_token(root, changed) if changed else ""

    if args.command_name == "status":
        print(json.dumps({"base": args.base, "changed": changed, "token": token}, ensure_ascii=False, indent=2))
        return 0
    if args.command_name == "token":
        print(token)
        return 0

    if not changed:
        print("PROTECT OK: no protected-path changes")
        return 0
    if token and args.approve == token:
        print(f"PROTECT OK: approved {len(changed)} protected path(s) token={token}")
        return 0
    print("PROTECT BLOCKED: protected paths changed without valid approval.", file=sys.stderr)
    for path in changed:
        print(f"  - {path}", file=sys.stderr)
    print(f"expected approval token: {token}", file=sys.stderr)
    print("review the diff, then rerun with: --approve-protected " + token, file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
