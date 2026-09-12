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

# ---------- EVO-037: TTL 元数据 / 陈旧自动回收 / 显式 reclaim ----------
lock_status() { (cd "$REPO" && EVOLVE_LOCK_REPO_ROOT="$REPO" "$TOOL" status --remote origin); }
lock_acquire() { (cd "$REPO" && EVOLVE_LOCK_REPO_ROOT="$REPO" "$TOOL" acquire --remote origin "$@" 2>&1); }
lock_held_sha() { lock_status | sed -n 's/^REMOTE LOCK HELD sha=\(.*\)$/\1/p' | head -1; }

# 新鲜锁：status 暴露 TTL 信息，acquire 仍拒绝
FRESH_SHA="$(lock_acquire | tail -1)"
FRESH_STATUS="$(lock_status)"
[[ "$FRESH_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "FAIL fresh lock sha: $FRESH_SHA" >&2; exit 1; }
[[ "$FRESH_STATUS" == *"ttlSeconds=14400"* ]] || { echo "FAIL status ttl: $FRESH_STATUS" >&2; exit 1; }
[[ "$FRESH_STATUS" == *"stale=no"* ]] || { echo "FAIL status stale flag: $FRESH_STATUS" >&2; exit 1; }
[[ "$FRESH_STATUS" == *"remainingSeconds="* ]] || { echo "FAIL status remaining" >&2; exit 1; }
set +e; lock_acquire >/dev/null; RC=$?; set -e
[[ "$RC" -eq 1 ]] || { echo "FAIL fresh acquire rc=$RC" >&2; exit 1; }
(cd "$REPO" && EVOLVE_LOCK_REPO_ROOT="$REPO" "$TOOL" release --remote origin --sha "$FRESH_SHA") >/dev/null

# 元数据缺 started（手推 ref）：绝不自动抢占
EMPTY_TREE="$(git -C "$REPO" mktree </dev/null)"
MANUAL="$(printf 'manual lock without metadata\n' | git -C "$REPO" commit-tree "$EMPTY_TREE")"
git -C "$REPO" push -q --force-with-lease="refs/heads/evolution-lock:" origin "$MANUAL:refs/heads/evolution-lock"
set +e; MANUAL_OUT="$(lock_acquire)"; RC=$?; set -e
[[ "$RC" -eq 1 ]] || { echo "FAIL manual lock acquire rc=$RC" >&2; exit 1; }
[[ "$MANUAL_OUT" == *"stale=unknown"* && "$MANUAL_OUT" == *"auto-reclaim disabled"* ]] \
  || { echo "FAIL manual lock guard: $MANUAL_OUT" >&2; exit 1; }
git -C "$REPO" push -q --force-with-lease="refs/heads/evolution-lock:$MANUAL" origin ":refs/heads/evolution-lock"

# 陈旧锁（started 早于 TTL）：正常 acquire 自动回收
STALE_EPOCH="$(( $(date +%s) - 20000 ))"
STALE_SHA="$(EVOLVE_LOCK_STARTED_OVERRIDE="$STALE_EPOCH" lock_acquire | tail -1)"
[[ -n "$STALE_SHA" ]] || { echo "FAIL stale lock creation" >&2; exit 1; }
STALE_STATUS="$(lock_status)"
[[ "$STALE_STATUS" == *"stale=yes"* ]] || { echo "FAIL stale status: $STALE_STATUS" >&2; exit 1; }
set +e; RECLAIM_OUT="$(lock_acquire)"; RC=$?; set -e
[[ "$RC" -eq 0 ]] || { echo "FAIL stale auto-reclaim rc=$RC out=$RECLAIM_OUT" >&2; exit 1; }
[[ "$RECLAIM_OUT" == *"REMOTE LOCK STALE RECLAIMED"* ]] || { echo "FAIL stale reclaim message: $RECLAIM_OUT" >&2; exit 1; }
NEW_SHA="$(lock_held_sha)"
[[ "$NEW_SHA" != "$STALE_SHA" && -n "$NEW_SHA" ]] || { echo "FAIL stale reclaim sha" >&2; exit 1; }
[[ "$(lock_status)" == *"stale=no"* ]] || { echo "FAIL post-reclaim status" >&2; exit 1; }

# 显式 reclaim：不依赖 TTL，立即覆盖
set +e; EXPLICIT_OUT="$(cd "$REPO" && EVOLVE_LOCK_REPO_ROOT="$REPO" "$TOOL" reclaim --remote origin 2>&1)"; RC=$?; set -e
[[ "$RC" -eq 0 ]] || { echo "FAIL explicit reclaim rc=$RC" >&2; exit 1; }
[[ "$EXPLICIT_OUT" == *"REMOTE LOCK RECLAIMED"* ]] || { echo "FAIL explicit reclaim message" >&2; exit 1; }
FORCED_SHA="$(lock_held_sha)"
[[ "$FORCED_SHA" != "$NEW_SHA" && -n "$FORCED_SHA" ]] || { echo "FAIL explicit reclaim sha" >&2; exit 1; }
(cd "$REPO" && EVOLVE_LOCK_REPO_ROOT="$REPO" "$TOOL" release --remote origin --sha "$FORCED_SHA") >/dev/null
[[ "$(lock_status)" == "REMOTE LOCK FREE" ]] || { echo "FAIL free after reclaim" >&2; exit 1; }

# --ttl 必须是整数
set +e; (cd "$REPO" && EVOLVE_LOCK_REPO_ROOT="$REPO" "$TOOL" status --remote origin --ttl abc) >/dev/null 2>&1; RC=$?; set -e
[[ "$RC" -eq 2 ]] || { echo "FAIL invalid ttl rc=$RC" >&2; exit 1; }

echo "evolution-remote-lock tests: 15 passed, 0 failed"
