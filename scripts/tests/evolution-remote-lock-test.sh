#!/usr/bin/env bash
# Regression tests for the cross-machine evolution lock.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/evolution-remote-lock.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-remote-lock.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; ORIGIN="$TMP/origin.git"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name Test
echo base > "$REPO/base.txt"
git -C "$REPO" add -A; git -C "$REPO" commit -qm base
git -C "$REPO" init -q --bare "$ORIGIN"
git -C "$REPO" remote add origin "$ORIGIN"
git -C "$REPO" push -q -u origin main

SHA="$(cd "$REPO" && EVOLVE_LOCK_REPO_ROOT="$REPO" "$TOOL" acquire --remote origin)"
[[ -n "$SHA" ]] || { echo "FAIL empty lock sha" >&2; exit 1; }
STATUS="$(cd "$REPO" && EVOLVE_LOCK_REPO_ROOT="$REPO" "$TOOL" status --remote origin)"
[[ "$STATUS" == *"REMOTE LOCK HELD"* && "$STATUS" == *"host="* ]] || { echo "FAIL status: $STATUS" >&2; exit 1; }
set +e
(cd "$REPO" && EVOLVE_LOCK_REPO_ROOT="$REPO" "$TOOL" acquire --remote origin) >/dev/null 2>&1
RC=$?
set -e
[[ "$RC" -eq 1 ]] || { echo "FAIL second acquire rc=$RC" >&2; exit 1; }
(cd "$REPO" && EVOLVE_LOCK_REPO_ROOT="$REPO" "$TOOL" release --remote origin --sha "$SHA") >/dev/null
FREE="$(cd "$REPO" && EVOLVE_LOCK_REPO_ROOT="$REPO" "$TOOL" status --remote origin)"
[[ "$FREE" == *"REMOTE LOCK FREE"* ]] || { echo "FAIL free: $FREE" >&2; exit 1; }

echo "evolution-remote-lock tests: 4 passed, 0 failed"
