#!/usr/bin/env bash
# Regression tests for scripts/evolution-maintenance.sh (mocked drill/archive/notify).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/evolution-maintenance.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-maintenance-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASSED=0; FAILED=0
ok()   { PASSED=$((PASSED + 1)); }
bad()  { FAILED=$((FAILED + 1)); echo "FAIL: $1" >&2; }
expect_eq() { # expect_eq <desc> <expected> <actual>
  if [[ "$2" == "$3" ]]; then ok; else bad "$1 (expected [$2] got [$3])"; fi
}
expect_grep() { # expect_grep <desc> <pattern> <file>
  if grep -q -- "$2" "$3" 2>/dev/null; then ok; else bad "$1 (no match: $2)"; fi
}
expect_no_grep() {
  if grep -q -- "$2" "$3" 2>/dev/null; then bad "$1 (unexpected match: $2)"; else ok; fi
}
expect_file_absent() {
  if [[ -e "$2" ]]; then bad "$1 (file exists: $2)"; else ok; fi
}
json_path() { # json_path <json> <dotted.path>
  python3 - "$1" "$2" <<'PY'
import json, sys
value = json.loads(sys.argv[1])
for key in sys.argv[2].split("."):
    value = value.get(key) if isinstance(value, dict) else None
print(json.dumps(value, ensure_ascii=False))
PY
}
last_record() {
  python3 - "$1" <<'PY'
import sys
lines = [l for l in open(sys.argv[1], encoding="utf-8").read().splitlines() if l.strip()]
print(lines[-1] if lines else "")
PY
}

mkdir -p "$TMP/state"
export DRILL_CALLS="$TMP/drill.calls" ARCHIVE_CALLS="$TMP/archive.calls" NOTIFY_CALLS="$TMP/notify.calls"
DRILL_EXIT=0 ARCHIVE_EXIT=0

cat > "$TMP/drill.sh" <<'MOCK'
#!/usr/bin/env bash
echo "drill $*" >> "$DRILL_CALLS"
if [[ "${DRILL_EXIT:-0}" -ne 0 ]]; then
  echo "ROLLBACK DRILL FAILED: remote tag v0.5.9 not found" >&2
  exit 1
fi
echo "ROLLBACK DRILL OK tag=v0.5.9 archive=local-dist fullBuild=0"
MOCK
chmod +x "$TMP/drill.sh"

cat > "$TMP/archive.py" <<'MOCK'
import os, sys
with open(os.environ["ARCHIVE_CALLS"], "a", encoding="utf-8") as fh:
    fh.write(" ".join(sys.argv[1:]) + "\n")
if int(os.environ.get("ARCHIVE_EXIT", "0")) != 0:
    print("ARCHIVE ERROR: permission denied", file=sys.stderr)
    sys.exit(1)
print("ARCHIVE OK: moved 3 record(s), keep_days=90")
MOCK

cat > "$TMP/notify.sh" <<'MOCK'
#!/usr/bin/env bash
echo "$1|$2" >> "$NOTIFY_CALLS"
MOCK
chmod +x "$TMP/notify.sh"

run_tool() { # run_tool <history> <output-prefix> [extra args...]
  local history="$1" prefix="$2"; shift 2
  set +e
  EVOLVE_MAINTENANCE_REPO_ROOT="$ROOT" \
  EVOLVE_MAINTENANCE_DRILL="$TMP/drill.sh" \
  EVOLVE_MAINTENANCE_ARCHIVE="$TMP/archive.py" \
  EVOLVE_MAINTENANCE_NOTIFY="$TMP/notify.sh" \
  EVOLVE_STATE_DIR="$TMP/state" \
  EVOLVE_MAINTENANCE_HISTORY="$history" \
  EVOLVE_MAINTENANCE_LOG="$TMP/state/maintenance.log" \
  DRILL_EXIT="$DRILL_EXIT" ARCHIVE_EXIT="$ARCHIVE_EXIT" \
    "$TOOL" "$@" > "$prefix.out" 2> "$prefix.err"
  TOOL_RC=$?
  set -e
}

# 1. 成功：静默、无通知、两份任务都跑、历史 status=ok。
HIST1="$TMP/state/maintenance_history.jsonl"
rm -f "$DRILL_CALLS" "$ARCHIVE_CALLS" "$NOTIFY_CALLS"
run_tool "$HIST1" "$TMP/success"
expect_eq "success: exit code" "0" "$TOOL_RC"
expect_eq "success: silent stdout" "" "$(cat "$TMP/success.out")"
REC="$(last_record "$HIST1")"
expect_eq "success: history status" '"ok"' "$(json_path "$REC" status)"
expect_eq "success: drill passed" "true" "$(json_path "$REC" drill.passed)"
expect_eq "success: drill tag" '"v0.5.9"' "$(json_path "$REC" drill.tag)"
expect_eq "success: archive moved" "3" "$(json_path "$REC" archive.moved)"
expect_eq "success: archive keepDays" "90" "$(json_path "$REC" archive.keepDays)"
expect_grep "success: drill invoked" "^drill " "$DRILL_CALLS"
expect_grep "success: archive invoked with keep-days" "\-\-keep-days 90" "$ARCHIVE_CALLS"
expect_file_absent "success: no notification" "$NOTIFY_CALLS"
expect_grep "success: log line" "status=ok" "$TMP/state/maintenance.log"

# 2. 演练失败：非零退出、stderr 给原因、发通知、归档继续跑、历史留痕。
DRILL_EXIT=1
run_tool "$HIST1" "$TMP/drill-fail"
DRILL_EXIT=0
expect_eq "drill failure: exit code" "1" "$TOOL_RC"
expect_grep "drill failure: stderr banner" "EVOLUTION MAINTENANCE FAILED" "$TMP/drill-fail.err"
expect_grep "drill failure: stderr reason" "回滚演练失败" "$TMP/drill-fail.err"
REC="$(last_record "$HIST1")"
expect_eq "drill failure: history status" '"failed"' "$(json_path "$REC" status)"
expect_eq "drill failure: drill status" '"failed"' "$(json_path "$REC" drill.status)"
expect_eq "drill failure: drill reason kept" '"ROLLBACK DRILL FAILED: remote tag v0.5.9 not found"' "$(json_path "$REC" drill.reason)"
expect_eq "drill failure: archive still ran" '"passed"' "$(json_path "$REC" archive.status)"
expect_grep "drill failure: notification title" "Tapgo 自进化维护失败" "$NOTIFY_CALLS"
expect_grep "drill failure: notification body" "回滚演练失败" "$NOTIFY_CALLS"

# 3. 归档失败：非零退出、归档失败进历史、演练结果仍为 passed。
ARCHIVE_EXIT=1
run_tool "$HIST1" "$TMP/archive-fail"
ARCHIVE_EXIT=0
expect_eq "archive failure: exit code" "1" "$TOOL_RC"
expect_grep "archive failure: stderr reason" "指标归档失败" "$TMP/archive-fail.err"
REC="$(last_record "$HIST1")"
expect_eq "archive failure: history status" '"failed"' "$(json_path "$REC" status)"
expect_eq "archive failure: drill passed" '"passed"' "$(json_path "$REC" drill.status)"
expect_eq "archive failure: archive status" '"failed"' "$(json_path "$REC" archive.status)"
expect_eq "archive failure: archive reason" '"ARCHIVE ERROR: permission denied"' "$(json_path "$REC" archive.reason)"

# 4. --no-archive：只跑演练，归档记为 skipped。
HIST2="$TMP/state/no-archive.jsonl"
rm -f "$DRILL_CALLS" "$ARCHIVE_CALLS" "$NOTIFY_CALLS"
run_tool "$HIST2" "$TMP/no-archive" --no-archive
expect_eq "no-archive: exit code" "0" "$TOOL_RC"
REC="$(last_record "$HIST2")"
expect_eq "no-archive: archive ran flag" "false" "$(json_path "$REC" archive.ran)"
expect_eq "no-archive: archive status" '"skipped"' "$(json_path "$REC" archive.status)"
expect_file_absent "no-archive: archive not invoked" "$ARCHIVE_CALLS"
expect_grep "no-archive: drill invoked" "^drill " "$DRILL_CALLS"

# 5. --no-notify：失败但不调用通知命令。
rm -f "$NOTIFY_CALLS"
DRILL_EXIT=1
run_tool "$HIST2" "$TMP/no-notify" --no-notify
DRILL_EXIT=0
expect_eq "no-notify: exit code" "1" "$TOOL_RC"
expect_file_absent "no-notify: notification skipped" "$NOTIFY_CALLS"

# 6. 参数校验：空任务与非法 keep-days 直接拒绝。
run_tool "$HIST2" "$TMP/bad-args" --no-drill --no-archive
expect_eq "bad args: exit code" "2" "$TOOL_RC"
run_tool "$HIST2" "$TMP/bad-days" --keep-days abc
expect_eq "bad keep-days: exit code" "2" "$TOOL_RC"

# 7. 安装器 --print：plist 可解析、无残留占位符、月度计划与 RunAtLoad=false。
PLIST_OUT="$TMP/rendered.plist"
"$ROOT/scripts/install-evolution-maintenance.sh" --print > "$PLIST_OUT"
if plutil -lint "$PLIST_OUT" >/dev/null 2>&1; then ok; else bad "installer: rendered plist invalid"; fi
expect_no_grep "installer: no leftover placeholders" "__[A-Z_]*__" "$PLIST_OUT"
expect_grep "installer: monthly schedule" "StartCalendarInterval" "$PLIST_OUT"
expect_grep "installer: run at load disabled" "RunAtLoad" "$PLIST_OUT"
expect_grep "installer: points at maintenance script" "evolution-maintenance.sh" "$PLIST_OUT"

# 8. 真实安装路径（隔离 LaunchAgents 目录 + 跳过 launchctl）：
#    覆盖 "变量后紧跟非 ASCII 字符被 bash 3.2 并入变量名" 这类只在
#    运行期暴露的回归（v0.5.287 曾因此在 install 路径 unbound variable）。
FAKE_HOME="$TMP/fake-home"
mkdir -p "$FAKE_HOME"
set +e
HOME="$FAKE_HOME" EVOLVE_LAUNCH_AGENTS_DIR="$FAKE_HOME/LaunchAgents" \
  "$ROOT/scripts/install-evolution-maintenance.sh" --skip-launchctl \
  > "$TMP/install.out" 2> "$TMP/install.err"
INSTALL_RC=$?
set -e
expect_eq "install: exit code" "0" "$INSTALL_RC"
expect_eq "install: clean stderr" "" "$(cat "$TMP/install.err")"
INSTALLED_PLIST="$FAKE_HOME/LaunchAgents/com.tapgo.aicoding.evolution-maintenance.plist"
if [[ -f "$INSTALLED_PLIST" ]]; then ok; else bad "install: plist not written"; fi
if plutil -lint "$INSTALLED_PLIST" >/dev/null 2>&1; then ok; else bad "install: written plist invalid"; fi
expect_grep "install: banner printed" "已安装" "$TMP/install.out"
expect_grep "install: monthly schedule in installed plist" "StartCalendarInterval" "$INSTALLED_PLIST"
expect_grep "install: script path resolved" "scripts/evolution-maintenance.sh" "$INSTALLED_PLIST"

echo "evolution-maintenance tests: $PASSED passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
