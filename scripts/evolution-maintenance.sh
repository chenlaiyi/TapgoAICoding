#!/usr/bin/env bash
# evolution-maintenance.sh — 自进化月度维护：回滚演练 + 指标归档，异常才通知。
#
# 定时（launchd，见 scripts/install-evolution-maintenance.sh）或手动执行。
# 成功静默：退出码 0，只追加一条 maintenance_history.jsonl 记录；
# 失败：写历史 + stderr 一行原因 + 触发通知，退出码 1。
#
# 可覆盖入口（测试/自定义）：
#   EVOLVE_MAINTENANCE_REPO_ROOT  仓库根目录
#   EVOLVE_STATE_DIR              运行态目录（history 与日志）
#   EVOLVE_MAINTENANCE_DRILL      回滚演练脚本（默认 scripts/rollback-drill.sh）
#   EVOLVE_MAINTENANCE_ARCHIVE    归档脚本（默认 scripts/evolution-archive.py）
#   EVOLVE_MAINTENANCE_HISTORY    历史文件（默认 <state>/maintenance_history.jsonl）
#   EVOLVE_MAINTENANCE_LOG        运行日志（默认 <state>/maintenance.log）
#   EVOLVE_MAINTENANCE_NOTIFY     通知命令：单一路径，接收 <title> <message>；
#                                 未设置时用 macOS 通知中心（osascript）
set -euo pipefail

ROOT="${EVOLVE_MAINTENANCE_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
DRILL_BIN="${EVOLVE_MAINTENANCE_DRILL:-$ROOT/scripts/rollback-drill.sh}"
ARCHIVE_BIN="${EVOLVE_MAINTENANCE_ARCHIVE:-$ROOT/scripts/evolution-archive.py}"
NOTIFY_CMD="${EVOLVE_MAINTENANCE_NOTIFY:-}"
STATE_DIR="${EVOLVE_STATE_DIR:-$HOME/Library/Application Support/Tapgo AICoding/state}"
HISTORY="${EVOLVE_MAINTENANCE_HISTORY:-$STATE_DIR/maintenance_history.jsonl}"
LOG_FILE="${EVOLVE_MAINTENANCE_LOG:-$STATE_DIR/maintenance.log}"

TAG=""; KEEP_DAYS=90; FULL_BUILD=0; RUN_DRILL=1; RUN_ARCHIVE=1; DO_NOTIFY=1; VERBOSE=0
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --tag) TAG="${2:-}"; shift ;;
    --keep-days) KEEP_DAYS="${2:-90}"; shift ;;
    --history) HISTORY="${2:-}"; shift ;;
    --state-dir) STATE_DIR="${2:-}"; shift ;;
    --full-build) FULL_BUILD=1 ;;
    --no-drill) RUN_DRILL=0 ;;
    --no-archive) RUN_ARCHIVE=0 ;;
    --no-notify) DO_NOTIFY=0 ;;
    --verbose) VERBOSE=1 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "ERROR: unexpected arg: $1" >&2; exit 2 ;;
  esac
  shift
done

[[ "$KEEP_DAYS" =~ ^[0-9]+$ ]] || { echo "ERROR: --keep-days must be an integer" >&2; exit 2; }
[[ "$RUN_DRILL" -eq 1 || "$RUN_ARCHIVE" -eq 1 ]] || { echo "ERROR: nothing to do (--no-drill --no-archive)" >&2; exit 2; }
if [[ "$RUN_DRILL" -eq 1 && ! -x "$DRILL_BIN" ]]; then
  echo "ERROR: drill script not executable: $DRILL_BIN" >&2; exit 2
fi
if [[ "$RUN_ARCHIVE" -eq 1 && ! -f "$ARCHIVE_BIN" ]]; then
  echo "ERROR: archive script not found: $ARCHIVE_BIN" >&2; exit 2
fi

mkdir -p "$(dirname "$HISTORY")" "$(dirname "$LOG_FILE")"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-maintenance.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

last_line() {
  local file="$1" line
  line="$(grep -v '^[[:space:]]*$' "$file" 2>/dev/null | tail -1 || true)"
  printf '%s' "${line:0:300}"
}

append_log() {
  local stamp
  stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s %s\n' "$stamp" "$1" >> "$LOG_FILE"
  chmod 0600 "$LOG_FILE" 2>/dev/null || true
}

notify() {
  local title="$1" message="$2" esc_title esc_message
  if [[ -n "$NOTIFY_CMD" ]]; then
    "$NOTIFY_CMD" "$title" "$message" >/dev/null 2>&1 || true
  elif command -v osascript >/dev/null 2>&1; then
    esc_title="$(printf '%s' "$title" | sed 's/["\\]/\\&/g')"
    esc_message="$(printf '%s' "$message" | sed 's/["\\]/\\&/g')"
    osascript -e "display notification \"$esc_message\" with title \"$esc_title\"" >/dev/null 2>&1 || true
  fi
}

START_EPOCH="$(date +%s)"
DRILL_STATUS="skipped"; DRILL_REASON=""; DRILL_TAG="$TAG"
ARCHIVE_STATUS="skipped"; ARCHIVE_REASON=""; ARCHIVE_MOVED=""
FAILED=0

if [[ "$RUN_DRILL" -eq 1 ]]; then
  drill_args=()
  if [[ -n "$TAG" ]]; then drill_args+=(--tag "$TAG"); fi
  if [[ "$FULL_BUILD" -eq 1 ]]; then drill_args+=(--full-build); fi
  if "$DRILL_BIN" ${drill_args[@]+"${drill_args[@]}"} > "$TMP/drill.log" 2>&1; then
    DRILL_STATUS="passed"
  else
    DRILL_STATUS="failed"; FAILED=1; DRILL_REASON="$(last_line "$TMP/drill.log")"
  fi
  if [[ -z "$DRILL_TAG" ]]; then
    DRILL_TAG="$(sed -n 's/.*tag=\([^ ]*\).*/\1/p' "$TMP/drill.log" | tail -1)"
  fi
  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "drill: $DRILL_STATUS${DRILL_REASON:+ — $DRILL_REASON}${DRILL_TAG:+ [$DRILL_TAG]}"
  fi
fi

if [[ "$RUN_ARCHIVE" -eq 1 ]]; then
  if python3 "$ARCHIVE_BIN" archive --state-dir "$STATE_DIR" --keep-days "$KEEP_DAYS" > "$TMP/archive.log" 2>&1; then
    ARCHIVE_STATUS="passed"
    ARCHIVE_MOVED="$(sed -n 's/^ARCHIVE OK: moved \([0-9]*\) record.*/\1/p' "$TMP/archive.log" | tail -1)"
  else
    ARCHIVE_STATUS="failed"; FAILED=1; ARCHIVE_REASON="$(last_line "$TMP/archive.log")"
  fi
  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "archive: $ARCHIVE_STATUS${ARCHIVE_MOVED:+ — moved $ARCHIVE_MOVED}${ARCHIVE_REASON:+ — $ARCHIVE_REASON}"
  fi
fi

DURATION="$(( $(date +%s) - START_EPOCH ))"
RECORD_STATUS="ok"; [[ "$FAILED" -eq 0 ]] || RECORD_STATUS="failed"

python3 - "$HISTORY" "$RECORD_STATUS" "$DRILL_STATUS" "$DRILL_TAG" "$DRILL_REASON" \
  "$ARCHIVE_STATUS" "$ARCHIVE_MOVED" "$ARCHIVE_REASON" "$KEEP_DAYS" "$DURATION" \
  "$RUN_DRILL" "$RUN_ARCHIVE" <<'PY'
from __future__ import annotations

import datetime, json, os, sys

(path, status, drill_status, drill_tag, drill_reason,
 archive_status, archive_moved, archive_reason, keep_days, duration,
 run_drill, run_archive) = sys.argv[1:13]

def passed(value: str) -> bool | None:
    return True if value == "passed" else False if value == "failed" else None

record = {
    "schemaVersion": 1,
    "ranAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "status": status,
    "durationSeconds": int(duration),
    "drill": {
        "ran": run_drill == "1",
        "status": drill_status,
        "passed": passed(drill_status),
        "tag": drill_tag or None,
        "reason": drill_reason or None,
    },
    "archive": {
        "ran": run_archive == "1",
        "status": archive_status,
        "passed": passed(archive_status),
        "moved": int(archive_moved) if archive_moved.isdigit() else None,
        "keepDays": int(keep_days),
        "reason": archive_reason or None,
    },
}
os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
with open(path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(record, ensure_ascii=False) + "\n")
os.chmod(path, 0o600)
PY

if [[ "$FAILED" -eq 1 ]]; then
  REASON=""
  if [[ "$DRILL_STATUS" == "failed" ]]; then REASON+="回滚演练失败(${DRILL_REASON:-未知原因}) "; fi
  if [[ "$ARCHIVE_STATUS" == "failed" ]]; then REASON+="指标归档失败(${ARCHIVE_REASON:-未知原因})"; fi
  REASON="${REASON% }"
  echo "EVOLUTION MAINTENANCE FAILED: $REASON" >&2
  append_log "status=failed ${REASON}"
  if [[ "$DO_NOTIFY" -eq 1 ]]; then notify "Tapgo 自进化维护失败" "$REASON"; fi
  exit 1
fi

append_log "status=ok drill=$DRILL_STATUS archive=$ARCHIVE_STATUS moved=${ARCHIVE_MOVED:-n/a}"
if [[ "$VERBOSE" -eq 1 ]]; then
  echo "EVOLUTION MAINTENANCE OK: drill=$DRILL_STATUS archive=$ARCHIVE_STATUS moved=${ARCHIVE_MOVED:-n/a} in ${DURATION}s"
fi
exit 0
