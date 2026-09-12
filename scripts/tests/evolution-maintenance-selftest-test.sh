#!/usr/bin/env bash
# Regression for scripts/evolution-maintenance-selftest.sh（EVO-051）。
#
# 两条：①--print 渲染的临时 LaunchAgent 形状正确（Label/参数/注入变量/独立 state）
#       ②真的在 launchd 里跑一次失败维护，断言通知被调用（隔离 Label，跑完自清）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/evolution-maintenance-selftest.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-maintenance-selftest-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASSED=0; FAILED=0
ok()  { PASSED=$((PASSED + 1)); }
bad() { FAILED=$((FAILED + 1)); echo "FAIL: $1" >&2; }
expect_eq() { [[ "$2" == "$3" ]] && ok || bad "$1 (expected [$2] got [$3])"; }
expect_grep() { grep -q -- "$2" "$3" 2>/dev/null && ok || bad "$1 (no match '$2')"; }

# ---------- 1. --print 形状 ----------
"$TOOL" --print > "$TMP/selftest.plist" 2> "$TMP/print.err"
expect_eq "print: exit 0" "0" "$?"
if plutil -lint "$TMP/selftest.plist" >/dev/null 2>&1; then ok; else bad "print: plist 非法"; fi
expect_grep "print: 独立 Label" "com.tapgo.aicoding.evolution-maintenance-selftest" "$TMP/selftest.plist"
expect_grep "print: 与生产一致的脚本参数" "--verbose" "$TMP/selftest.plist"
expect_grep "print: 注入失败演练桩" "EVOLVE_MAINTENANCE_DRILL" "$TMP/selftest.plist"
expect_grep "print: 注入通知捕获" "EVOLVE_MAINTENANCE_NOTIFY" "$TMP/selftest.plist"
expect_grep "print: 独立 state 目录" "EVOLVE_STATE_DIR" "$TMP/selftest.plist"
expect_grep "print: RunAtLoad" "RunAtLoad" "$TMP/selftest.plist"
expect_grep "print: 极简 PATH（模拟 launchd）" "/usr/bin:/bin" "$TMP/selftest.plist"

# ---------- 2. 真实 launchd 跑一次失败维护 ----------
if ! command -v launchctl >/dev/null 2>&1; then
  echo "NOTE: 无 launchctl，跳过真实 launchd 自检"
else
  set +e
  "$TOOL" > "$TMP/run.log" 2>&1
  RC=$?
  set -e
  expect_eq "run: exit 0" "0" "$RC"
  expect_grep "run: OK 行" "MAINTENANCE SELFTEST OK" "$TMP/run.log"
  expect_grep "run: 走的是 capture 通知" "notify=capture" "$TMP/run.log"
  expect_grep "run: launchd 退出码为 1（失败维护）" "launchdExit=1" "$TMP/run.log"
  expect_grep "run: 通知内容带原因" "selftest injected failure" "$TMP/run.log"
  # 生产任务不受影响：临时 Label 已清理，生产 plist 仍在
  if launchctl print "gui/$(id -u)/com.tapgo.aicoding.evolution-maintenance-selftest" >/dev/null 2>&1; then
    bad "run: 临时 Label 未清理"
  else
    ok
  fi
  if [[ -f "$HOME/Library/LaunchAgents/com.tapgo.aicoding.evolution-maintenance.plist" ]]; then ok; else bad "run: 生产 plist 丢失"; fi
fi

echo "evolution-maintenance-selftest tests: $PASSED passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
