#!/usr/bin/env bash
# evolution-remote-lock.sh — cross-machine mutex for self-evolution.
#
# A fixed remote ref refs/heads/evolution-lock is created with an empty
# force-with-lease expectation, which git treats as "must not exist". This is
# atomic on the remote. The ref points at a metadata commit whose message
# records host/user/pid/started epoch.
#
# EVO-037 TTL：
#   * 锁的 started 超过 EVOLVE_LOCK_TTL_SECONDS（默认 4h）即视为陈旧，acquire
#     会自动抢占并在 stderr 说明，避免机器崩溃后要人工介入。
#   * 元数据读不出 started（例如手推的 ref）时绝不自动抢占，只报 HELD。
#   * reclaim 是显式抢占入口：无论年龄一律用 force-with-lease 覆盖，
#     供 evolve.sh --break-remote-lock 使用；lease 保证不与并发者互相覆盖。
#
# Usage: acquire|reclaim|release|status --remote <name> [--sha <sha>] [--ttl <seconds>]
set -euo pipefail

ROOT="${EVOLVE_LOCK_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"

usage() {
  echo "usage: evolution-remote-lock.sh acquire|reclaim|release|status --remote <name> [--sha <sha>] [--ttl <seconds>]" >&2
  exit 2
}
CMD="${1:-}"; shift || true
REMOTE=""; SHA=""; TTL="${EVOLVE_LOCK_TTL_SECONDS:-14400}"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --remote) REMOTE="${2:-}"; shift ;;
    --sha) SHA="${2:-}"; shift ;;
    --ttl) TTL="${2:-}"; shift ;;
    *) usage ;;
  esac
  shift
done
[[ -n "$CMD" && -n "$REMOTE" ]] || usage
[[ "$TTL" =~ ^[0-9]+$ ]] || { echo "ERROR: --ttl must be an integer" >&2; exit 2; }
REF="refs/heads/evolution-lock"
# 测试注入点：用固定 epoch 伪造锁的创建时间。
STARTED_OVERRIDE="${EVOLVE_LOCK_STARTED_OVERRIDE:-}"

remote_sha() {
  git ls-remote "$REMOTE" "$REF" 2>/dev/null | awk '{print $1}' | head -1
}

holder_info() {
  local sha="$1"
  [[ -n "$sha" ]] || return 0
  git fetch -q "$REMOTE" "$REF" 2>/dev/null || true
  git log -1 --format=%B "$sha" 2>/dev/null || true
}

holder_started() {
  printf '%s\n' "$1" | sed -n 's/.*started=\([0-9][0-9]*\).*/\1/p' | head -1
}

make_lock_commit() {
  local empty_tree started metadata
  empty_tree="$(git mktree </dev/null)"
  if [[ -n "$STARTED_OVERRIDE" ]]; then
    started="$STARTED_OVERRIDE"
  else
    started="$(date +%s)"
  fi
  metadata="tapgo-evolve-lock host=$(hostname) user=$(whoami) pid=$$ started=$started startedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\n' "$metadata" | git commit-tree "$empty_tree"
}

# push_lock_lease <expected-old-sha-or-empty> — 只在远端仍等于期望值时写入。
push_lock_lease() {
  local expected="$1" commit="$2"
  git push -q --force-with-lease="$REF:$expected" "$REMOTE" "$commit:$REF" 2>/dev/null
}

report_held() {
  local sha="$1" info="$2" started now age remaining stale
  echo "REMOTE LOCK HELD sha=$sha" >&2
  [[ -n "$info" ]] && printf '%s\n' "$info" >&2
  started="$(holder_started "$info")"
  if [[ -z "$started" ]]; then
    echo "ttlSeconds=$TTL started=unknown stale=unknown (auto-reclaim disabled)" >&2
    return 0
  fi
  now="$(date +%s)"
  age="$(( now - started ))"
  remaining="$(( TTL - age ))"
  stale="no"
  (( age > TTL )) && stale="yes"
  echo "ttlSeconds=$TTL ageSeconds=$age remainingSeconds=$remaining stale=$stale" >&2
}

case "$CMD" in
  acquire)
    existing="$(remote_sha)"
    if [[ -n "$existing" ]]; then
      info="$(holder_info "$existing")"
      started="$(holder_started "$info")"
      if [[ -n "$started" ]] && (( $(date +%s) - started > TTL )); then
        commit="$(make_lock_commit)"
        if push_lock_lease "$existing" "$commit"; then
          echo "REMOTE LOCK STALE RECLAIMED old=$existing sha=$commit ttl=${TTL}s" >&2
          echo "$commit"
          exit 0
        fi
        echo "REMOTE LOCK CONTENDED during stale reclaim sha=$(remote_sha)" >&2
        exit 1
      fi
      report_held "$existing" "$info"
      exit 1
    fi
    commit="$(make_lock_commit)"
    if ! push_lock_lease "" "$commit"; then
      existing="$(remote_sha)"
      echo "REMOTE LOCK CONTENDED sha=${existing:-unknown}" >&2
      [[ -n "$existing" ]] && holder_info "$existing" >&2
      exit 1
    fi
    echo "$commit"
    ;;
  reclaim)
    existing="$(remote_sha)"
    commit="$(make_lock_commit)"
    if ! push_lock_lease "$existing" "$commit"; then
      echo "REMOTE LOCK CONTENDED during reclaim sha=$(remote_sha)" >&2
      exit 1
    fi
    echo "REMOTE LOCK RECLAIMED old=${existing:-none} sha=$commit" >&2
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
    started="$(holder_started "$info")"
    if [[ -n "$started" ]]; then
      now="$(date +%s)"
      age="$((now - started))"
      remaining="$((TTL - age))"
      stale="no"
      (( age > TTL )) && stale="yes"
      echo "ttlSeconds=$TTL ageSeconds=$age remainingSeconds=$remaining stale=$stale"
    else
      echo "ttlSeconds=$TTL started=unknown stale=unknown"
    fi
    ;;
  *) usage ;;
esac
