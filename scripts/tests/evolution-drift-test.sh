#!/usr/bin/env bash
# EVO-055: scripts/evolution-drift.py（本机 App 版本漂移真源）回归。
#
# 覆盖：一致/落后两种基本判定、releasesBehind 计数与「记录不覆盖时给 null」、
# firstSeenAt 跨轮继承、seenRuns 按 run-id 去重（一轮内多次写 state 只算一次）、
# 未检测到进程时的降级文案、check 子命令的退出码。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/evolution-drift.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-drift-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASSED=0; FAILED=0
ok()  { PASSED=$((PASSED + 1)); }
bad() { FAILED=$((FAILED + 1)); echo "FAIL: $1" >&2; }
expect_eq() { # expect_eq <label> <actual> <expected>
  if [[ "$2" == "$3" ]]; then ok; else bad "$1（期望 $3，实际 $2）"; fi
}
expect_contains() { # expect_contains <label> <haystack> <needle>
  case "$2" in *"$3"*) ok ;; *) bad "$1（缺 $3，实际：$2）" ;; esac
}
json_field() { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1]))' "$1"; }

FAKE_ROOT="$TMP/root"
mkdir -p "$FAKE_ROOT/evolution/versions"
for v in 0.5.300 0.5.301 0.5.302; do
  printf '{"version":"%s"}\n' "$v" > "$FAKE_ROOT/evolution/versions/v$v.json"
done

# 1) 运行版本 == 已安装版本 → 无漂移
OUT="$(python3 "$TOOL" compute --running 0.5.302 --installed 0.5.302 --root "$FAKE_ROOT" --now 2026-09-13T00:00:00Z)"
expect_eq "一致时 stale" "$(printf '%s' "$OUT" | json_field stale)" "False"
expect_eq "一致时 releasesBehind" "$(printf '%s' "$OUT" | json_field releasesBehind)" "0"
expect_eq "一致时 seenRuns" "$(printf '%s' "$OUT" | json_field seenRuns)" "0"
expect_eq "一致时 remediation" "$(printf '%s' "$OUT" | json_field remediation)" "None"

# 2) 落后 2 个版本（0.5.300 → 0.5.302）
STATE="$FAKE_ROOT/state.json"
printf '{"localApp":{}}\n' > "$STATE"
OUT="$(python3 "$TOOL" compute --running 0.5.300 --installed 0.5.302 --root "$FAKE_ROOT" --state "$STATE" --run-id run-1 --now 2026-09-13T00:00:00Z)"
expect_eq "落后时 stale" "$(printf '%s' "$OUT" | json_field stale)" "True"
expect_eq "落后版本数" "$(printf '%s' "$OUT" | json_field releasesBehind)" "2"
expect_eq "首次观测 seenRuns" "$(printf '%s' "$OUT" | json_field seenRuns)" "1"
expect_eq "首次观测时间" "$(printf '%s' "$OUT" | json_field firstSeenAt)" "2026-09-13T00:00:00Z"
expect_contains "remediation 命令" "$(printf '%s' "$OUT" | json_field remediation)" "restart-and-resume.sh"
expect_contains "人类可读行含落后版本数" "$(printf '%s' "$OUT" | json_field line)" "落后 2 个版本"

# 3) 下一轮（running 未变）→ 继承 firstSeenAt，seenRuns 递增
printf '{"localApp":{"drift":%s}}\n' "$OUT" > "$STATE"
OUT2="$(python3 "$TOOL" compute --running 0.5.300 --installed 0.5.302 --root "$FAKE_ROOT" --state "$STATE" --run-id run-2 --now 2026-09-14T00:00:00Z)"
expect_eq "跨轮继承 firstSeenAt" "$(printf '%s' "$OUT2" | json_field firstSeenAt)" "2026-09-13T00:00:00Z"
expect_eq "跨轮 seenRuns 递增" "$(printf '%s' "$OUT2" | json_field seenRuns)" "2"
expect_eq "跨轮 lastSeenAt 更新" "$(printf '%s' "$OUT2" | json_field lastSeenAt)" "2026-09-14T00:00:00Z"

# 4) 同一 run-id 再次写 state → seenRuns 不重复计数
printf '{"localApp":{"drift":%s}}\n' "$OUT2" > "$STATE"
OUT3="$(python3 "$TOOL" compute --running 0.5.300 --installed 0.5.302 --root "$FAKE_ROOT" --state "$STATE" --run-id run-2 --now 2026-09-14T01:00:00Z)"
expect_eq "同轮去重 seenRuns" "$(printf '%s' "$OUT3" | json_field seenRuns)" "2"

# 5) running 早于最早记录 → 不给错数（null）
OUT4="$(python3 "$TOOL" compute --running 0.5.100 --installed 0.5.302 --root "$FAKE_ROOT" --now 2026-09-13T00:00:00Z)"
expect_eq "记录不覆盖时为 null" "$(printf '%s' "$OUT4" | json_field releasesBehind)" "None"

# 6) 未检测到运行中进程 → 降级文案 + stale
OUT5="$(python3 "$TOOL" compute --running none --installed 0.5.302 --root "$FAKE_ROOT" --now 2026-09-13T00:00:00Z)"
expect_eq "无进程时 stale" "$(printf '%s' "$OUT5" | json_field stale)" "True"
expect_eq "无进程时版本数未知" "$(printf '%s' "$OUT5" | json_field releasesBehind)" "None"
expect_contains "无进程时给出收敛命令" "$(printf '%s' "$OUT5" | json_field line)" "restart-and-resume.sh"

# 7) check 子命令：有漂移退出 1，无漂移退出 0
printf '{"localApp":{"installed":"0.5.302","running":"0.5.300","stale":true,"drift":%s}}\n' "$OUT" > "$STATE"
set +e
CHECK_OUT="$(python3 "$TOOL" check --state "$STATE" 2>&1)"; CHECK_RC=$?
set -e
expect_eq "check 漂移退出码" "$CHECK_RC" "1"
expect_contains "check 漂移输出命令" "$CHECK_OUT" "restart-and-resume.sh"

printf '{"localApp":{"installed":"0.5.302","running":"0.5.302","stale":false}}\n' > "$STATE"
set +e
CHECK_OUT2="$(python3 "$TOOL" check --state "$STATE" 2>&1)"; CHECK_RC2=$?
set -e
expect_eq "check 一致退出码" "$CHECK_RC2" "0"
expect_contains "check 一致输出" "$CHECK_OUT2" "版本一致"

# 8) 旧形状 state（EVO-055 之前写的：只有 installed/running/stale，没有 drift 块）
#    必须降级成通用提示，而不是崩掉或静默说「一致」。
printf '{"localApp":{"installed":"0.5.302","running":"0.5.300","stale":true}}\n' > "$STATE"
set +e
CHECK_OLD="$(python3 "$TOOL" check --state "$STATE" 2>&1)"; RC_OLD=$?
set -e
expect_eq "旧形状 check 退出码" "$RC_OLD" "1"
expect_contains "旧形状降级提示含运行版本" "$CHECK_OLD" "0.5.300"
expect_contains "旧形状降级提示含收敛命令" "$CHECK_OLD" "restart-and-resume.sh"

# 9) state 不可读 → 退出 2（区别于「一致」的 0，自动化不能误判成已对齐）
set +e
CHECK_MISSING="$(python3 "$TOOL" check --state "$TMP/does-not-exist.json" 2>&1)"; RC_MISSING=$?
set -e
expect_eq "state 缺失退出码" "$RC_MISSING" "2"
expect_contains "state 缺失给出原因" "$CHECK_MISSING" "不可读"

echo "evolution-drift tests: $PASSED passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
