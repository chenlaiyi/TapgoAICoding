#!/usr/bin/env bash
# evolution-remote-lock.sh — cross-machine mutex for self-evolution.
#
# A fixed remote ref refs/heads/evolution-lock is created with an empty
# force-with-lease expectation, which git treats as "must not exist". This is
# atomic on the remote. The ref points at a metadata commit whose message
# records host/user/pid/started epoch.
set -euo pipefail

ROOT="${EVOLVE_LOCK_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

usage() { echo "usage: evolution-remote-lock.sh acquire|release|status --remote <name> [--sha <sha>]" >&2; exit 2; }
CMD="${1:-}"; shift || true
REMOTE=""; SHA=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --remote) REMOTE="${2:-}"; shift ;;
    --sha) SHA="${2:-}"; shift ;;
    *) usage ;;
  esac
  shift
done
[[ -n "$CMD" && -n "$REMOTE" ]] || usage
REF="refs/heads/evolution-lock"

remote_sha() {
  git ls-remote "$REMOTE" "$REF" 2>/dev/null | awk '{print $1}' | head -1
}

holder_info() {
  local sha="$1"
  [[ -n "$sha" ]] || return 0
  git fetch -q "$REMOTE" "$REF" 2>/dev/null || true
  git log -1 --format=%B "$sha" 2>/dev/null || true
}

case "$CMD" in
  acquire)
    existing="$(remote_sha)"
    if [[ -n "$existing" ]]; then
      echo "REMOTE LOCK HELD sha=$existing" >&2
      holder_info "$existing" >&2
      exit 1
    fi
    empty_tree="$(git mktree </dev/null)"
    started="$(date +%s)"
    metadata="tapgo-evolve-lock host=$(hostname) user=$(whoami) pid=$$ started=$started startedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    commit="$(printf '%s\n' "$metadata" | git commit-tree "$empty_tree")"
    if ! git push -q --force-with-lease="$REF:" "$REMOTE" "$commit:$REF" 2>/dev/null; then
      existing="$(remote_sha)"
      echo "REMOTE LOCK CONTENDED sha=${existing:-unknown}" >&2
      [[ -n "$existing" ]] && holder_info "$existing" >&2
      exit 1
    fi
    echo "$commit"
    ;;
  release)
    [[ -n "$SHA" ]] || usage
    git push -q --force-with-lease="$REF:$SHA" "$REMOTE" ":$REF"
    echo "REMOTE LOCK RELEASED sha=$SHA"
    ;;
  status)
    existing="$(remote_sha)"
    if [[ -z "$existing" ]]; then
      echo "REMOTE LOCK FREE"
      exit 0
    fi
    echo "REMOTE LOCK HELD sha=$existing"
    info="$(holder_info "$existing")"
    echo "$info"
    started="$(printf '%s\n' "$info" | sed -n 's/.*started=\([0-9][0-9]*\).*/\1/p' | head -1)"
    if [[ -n "$started" ]]; then
      now="$(date +%s)"
      echo "ageSeconds=$((now - started))"
    fi
    ;;
  *) usage ;;
esac
