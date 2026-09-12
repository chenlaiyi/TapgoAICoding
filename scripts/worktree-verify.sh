#!/usr/bin/env bash
# worktree-verify.sh <ref>
#
# Create a detached git worktree at <ref> and build there. This proves the
# tagged commit is self-contained: files that exist only in the dirty main
# checkout cannot make the build pass.
#
# Override the build command for tests:
#   EVOLVE_WORKTREE_BUILD_CMD='test -f needed.txt' ./scripts/worktree-verify.sh v0.5.1
set -euo pipefail

ROOT="${EVOLVE_WORKTREE_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=scripts/evolution-deps.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/evolution-deps.sh"
REF="${1:-}"
[[ -n "$REF" ]] || { echo "ERROR: usage: worktree-verify.sh <ref>" >&2; exit 2; }
git -C "$ROOT" rev-parse --verify "$REF^{commit}" >/dev/null

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-worktree-verify.XXXXXX")"
WT="$TMP/verify"
cleanup() {
  git -C "$ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

git -C "$ROOT" worktree add --detach "$WT" "$REF" >/dev/null
if [[ -n "$(git -C "$WT" status --porcelain)" ]]; then
  echo "ERROR: fresh worktree is not clean at $REF" >&2
  exit 3
fi

BUILD_CMD="${EVOLVE_WORKTREE_BUILD_CMD:-}"
echo "==> worktree verify: $REF at $WT"
if [[ -n "$BUILD_CMD" ]]; then
  ( cd "$WT" && bash -c "$BUILD_CMD" )
else
  ( cd "$WT" && xcrun -sdk "${TAPGO_SDK:-$(evo_detect_sdk)}" swift build -c release --product TapgoAICoding )
fi

if [[ -n "$(git -C "$WT" status --porcelain)" ]]; then
  echo "ERROR: build produced non-ignored changes inside the clean worktree" >&2
  git -C "$WT" status --short >&2
  exit 4
fi

echo "WORKTREE VERIFY OK ref=$REF"
