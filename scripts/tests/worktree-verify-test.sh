#!/usr/bin/env bash
# Regression tests for scripts/worktree-verify.sh clean-checkout isolation.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/worktree-verify.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-worktree-verify-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO"
printf '// package\n' > "$REPO/Package.swift"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name Test
git -C "$REPO" add Package.swift
git -C "$REPO" commit -qm baseline
git -C "$REPO" tag -a v0.5.1 -m v0.5.1

# Untracked file must be invisible to a clean worktree build.
printf 'untracked\n' > "$REPO/needed.txt"
set +e
EVOLVE_WORKTREE_REPO_ROOT="$REPO" EVOLVE_WORKTREE_BUILD_CMD='test -f needed.txt' "$TOOL" v0.5.1 >/dev/null 2>&1
RC=$?
set -e
[[ "$RC" -ne 0 ]] || { echo "FAIL untracked file leaked into worktree build" >&2; exit 1; }

# Once committed, the file is present and the clean worktree build passes.
git -C "$REPO" add needed.txt
git -C "$REPO" commit -qm add-needed
git -C "$REPO" tag -a v0.5.2 -m v0.5.2
(EVOLVE_WORKTREE_REPO_ROOT="$REPO" EVOLVE_WORKTREE_BUILD_CMD='test -f needed.txt' "$TOOL" v0.5.2) | grep -q 'WORKTREE VERIFY OK'
[[ "$(git -C "$REPO" worktree list | wc -l | tr -d ' ')" == "1" ]] || { echo "FAIL worktree not cleaned" >&2; exit 1; }

echo "worktree-verify tests: 3 passed, 0 failed"
