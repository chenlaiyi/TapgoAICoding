#!/usr/bin/env bash
# evolution-maintenance-selftest.sh — 在**真实 launchd 上下文**里验证维护任务的失败告警链路。
#
# 为什么要它：维护任务平时成功静默，最难验证也最危险的组合是
#   「launchd 启动（极简 PATH、无 TTY） + 维护失败 → 告警真的发出去了吗」。
# 之前分别验证过 launchd+成功、直接调用+失败+假 osascript，唯独这条组合没跑过。
#
# 做法：用独立 Label（com.tapgo.aicoding.evolution-maintenance-selftest）安装一个
# RunAtLoad=true 的临时 LaunchAgent，ProgramArguments 与生产任务一致，但通过
# EnvironmentVariables 注入「必然失败的演练桩 + 通知捕获脚本」，并把 state/日志
# 指向临时目录——生产 state 完全不受影响。跑完 bootout 并删除临时 plist。
#
# 用法：
#   ./scripts/evolution-maintenance-selftest.sh                 # 通知指向捕获脚本（不发真实通知）
#   ./scripts/evolution-maintenance-selftest.sh --use-system-notify   # 走真实 osascript（会弹通知）
#   ./scripts/evolution-maintenance-selftest.sh --print         # 只打印临时 plist，不注册
#   ./scripts/evolution-maintenance-selftest.sh --keep          # 保留临时目录供排查
set -euo pipefail
ROOT="${EVOLVE_SELFTEST_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LABEL="com.tapgo.aicoding.evolution-maintenance-selftest"
MAINTENANCE_SCRIPT="$ROOT/scripts/evolution-maintenance.sh"
NOTIFY_MODE="capture"   # capture | system
PRINT_ONLY=0
KEEP=0
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --use-system-notify) NOTIFY_MODE="system" ;;
    --print) PRINT_ONLY=1 ;;
    --keep) KEEP=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "ERROR: unexpected arg: $1" >&2; exit 2 ;;
  esac
  shift
done
[[ -x "$MAINTENANCE_SCRIPT" ]] || { echo "ERROR: $MAINTENANCE_SCRIPT 不可执行" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-maintenance-selftest.XXXXXX")"
cleanup() {
  local rc=$?
  if [[ "$PRINT_ONLY" -eq 0 ]]; then
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" 2>/dev/null || true
  fi
  if [[ "$KEEP" -eq 1 ]]; then
    echo "KEPT: $TMP" >&2
  else
    rm -rf "$TMP"
  fi
  return $rc
}
trap cleanup EXIT

# 必失败的演练桩：模拟"远端 tag 找不到"，让维护任务走失败+通知分支。
cat > "$TMP/fail-drill.sh" <<'FAKE'
#!/usr/bin/env bash
echo "ROLLBACK DRILL FAILED: selftest injected failure" >&2
exit 1
FAKE
chmod +x "$TMP/fail-drill.sh"

# 通知捕获脚本：记录 argv，便于断言"告警真的被调用且内容正确"。
cat > "$TMP/capture-notify.sh" <<FAKE
#!/usr/bin/env bash
printf '%s\\n' "\$1" > "$TMP/notify-title.txt"
printf '%s\\n' "\$2" > "$TMP/notify-message.txt"
FAKE
chmod +x "$TMP/capture-notify.sh"

mkdir -p "$TMP/state"
STATE_DIR="$TMP/state"
PLIST="$TMP/$LABEL.plist"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$MAINTENANCE_SCRIPT</string>
    <string>--verbose</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>TERM</key><string>dumb</string>
    <key>LANG</key><string>C.UTF-8</string>
    <key>EVOLVE_STATE_DIR</key><string>$STATE_DIR</string>
    <key>EVOLVE_MAINTENANCE_LOG</key><string>$STATE_DIR/maintenance.log</string>
    <key>EVOLVE_MAINTENANCE_HISTORY</key><string>$STATE_DIR/maintenance_history.jsonl</string>
    <key>EVOLVE_MAINTENANCE_DRILL</key><string>$TMP/fail-drill.sh</string>
PLISTEOF
if [[ "$NOTIFY_MODE" == "capture" ]]; then
  cat >> "$PLIST" <<PLISTEOF
    <key>EVOLVE_MAINTENANCE_NOTIFY</key><string>$TMP/capture-notify.sh</string>
PLISTEOF
fi
cat >> "$PLIST" <<PLISTEOF
  </dict>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$TMP/launchd.out.log</string>
  <key>StandardErrorPath</key><string>$TMP/launchd.err.log</string>
</dict>
</plist>
PLISTEOF

if [[ "$PRINT_ONLY" -eq 1 ]]; then
  cat "$PLIST"
  exit 0
fi
plutil -lint "$PLIST" >/dev/null

mkdir -p "$HOME/Library/LaunchAgents"
cp "$PLIST" "$HOME/Library/LaunchAgents/$LABEL.plist"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$LABEL.plist"

# 等任务真正跑完（最多 30s）。注意：维护脚本先写历史、后发通知，
# 只等历史文件会抢跑——必须等 launchd 不再显示 running。
for _ in $(seq 1 60); do
  if [[ -s "$STATE_DIR/maintenance_history.jsonl" ]] \
     && ! launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -q "state = running"; then
    break
  fi
  sleep 0.5
done
sleep 0.5   # 留出 launchd 更新 last exit code 的时间

FAILED=0
RECORD="$(tail -1 "$STATE_DIR/maintenance_history.jsonl" 2>/dev/null || true)"
[[ -n "$RECORD" ]] || { echo "SELFTEST FAILED: 维护任务没有写历史（launchd 可能没跑起来）" >&2; FAILED=1; }
if [[ -z "$FAILED" || "$FAILED" -eq 0 ]]; then
  python3 - "$RECORD" <<'PY' || FAILED=1
import json, sys
record = json.loads(sys.argv[1])
assert record["status"] == "failed", record
assert record["drill"]["status"] == "failed", record
assert "selftest injected failure" in (record["drill"]["reason"] or ""), record
PY
fi
if [[ "$NOTIFY_MODE" == "capture" ]]; then
  [[ -s "$TMP/notify-title.txt" ]] || { echo "SELFTEST FAILED: 通知脚本未被调用" >&2; FAILED=1; }
  [[ -s "$TMP/notify-message.txt" ]] || { echo "SELFTEST FAILED: 通知内容为空" >&2; FAILED=1; }
  if [[ -s "$TMP/notify-message.txt" ]]; then
    grep -q "selftest injected failure" "$TMP/notify-message.txt" || {
      echo "SELFTEST FAILED: 通知内容缺少原因：$(cat "$TMP/notify-message.txt")" >&2; FAILED=1; }
  fi
fi
EXIT_CODE="$(launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | sed -n 's/.*last exit code = \([-0-9]*\).*/\1/p' | head -1)"
[[ "$EXIT_CODE" == "1" ]] || { echo "WARN: launchd last exit code=${EXIT_CODE:-unknown}（期望 1）" >&2; }

if [[ "$FAILED" -ne 0 ]]; then
  echo "MAINTENANCE SELFTEST FAILED (state=$STATE_DIR)" >&2
  KEEP=1
  exit 1
fi
echo "MAINTENANCE SELFTEST OK label=$LABEL notify=$NOTIFY_MODE launchdExit=${EXIT_CODE:-unknown} reason=$(cat "$TMP/notify-message.txt" 2>/dev/null || echo '(system osascript)')"
