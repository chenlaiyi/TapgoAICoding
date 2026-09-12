#!/usr/bin/env bash
# Regression tests for scripts/evolution-schema.py (registry / ensure / validate).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/evolution-schema.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-schema-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASSED=0; FAILED=0
ok()  { PASSED=$((PASSED + 1)); }
bad() { FAILED=$((FAILED + 1)); echo "FAIL: $1" >&2; }
expect_eq() { [[ "$2" == "$3" ]] && ok || bad "$1 (expected [$2] got [$3])"; }
expect_grep() { grep -q -- "$2" "$3" 2>/dev/null && ok || bad "$1 (no match '$2')"; }
expect_no_grep() { ! grep -q -- "$2" "$3" 2>/dev/null && ok || bad "$1 (unexpected '$2')"; }

run_tool() { # run_tool <log> <args...>
  local log="$1"; shift
  set +e
  EVOLVE_STATE_DIR="$STATE" "$TOOL" "$@" > "$log" 2>&1
  RC=$?
  set -e
}

# ---------- 1. 历史记录（无 schemaVersion）迁移 ----------
STATE="$TMP/state"; mkdir -p "$STATE"
cat > "$STATE/test_run_history.jsonl" <<'JSONL'
{"version":"0.5.1","ranAt":"2026-09-01T00:00:00Z","status":"pass"}
{"version":"0.5.2","ranAt":"2026-09-02T00:00:00Z","status":"fail"}
JSONL
printf '{"tag":"v0.5.1","passed":true,"ranAt":"2026-09-01T00:00:00Z"}\n' > "$STATE/rollback_drill_history.jsonl"
printf '%s\n' '{"version":"0.5.286","status":"published","healthCheck":"passed","worktreeVerified":"yes"}' > "$STATE/evolution_state_history.jsonl"
chmod 0600 "$STATE/test_run_history.jsonl"

run_tool "$TMP/validate-before.log" validate
expect_eq "legacy: validate fails before migration" "13" "$RC"
expect_grep "legacy: missing reported" "缺 schemaVersion" "$TMP/validate-before.log"

run_tool "$TMP/ensure.log" ensure
expect_eq "legacy: ensure exit 0" "0" "$RC"
expect_grep "legacy: stamped file listed" "stamped test_run_history.jsonl" "$TMP/ensure.log"
expect_grep "legacy: stamp count reported" "stamped 4 record" "$TMP/ensure.log"
expect_eq "legacy: schemaVersion added" "1" "$(python3 -c "
import json,sys
print(json.loads(open('$STATE/test_run_history.jsonl').readline())['schemaVersion'])")"
expect_eq "legacy: other fields preserved" "0.5.1" "$(python3 -c "
import json
d=json.loads(open('$STATE/test_run_history.jsonl').readline())
print(d['version'])")"
expect_eq "legacy: existing status preserved" "pass" "$(python3 -c "
import json
print(json.loads(open('$STATE/test_run_history.jsonl').readline())['status'])")"
expect_eq "legacy: file mode preserved" "600" "$(stat -f '%Lp' "$STATE/test_run_history.jsonl")"

run_tool "$TMP/validate-after.log" validate
expect_eq "legacy: validate passes after migration" "0" "$RC"
expect_grep "legacy: summary ok" "SCHEMA OK" "$TMP/validate-after.log"

# 幂等：第二次 ensure 不再改写
run_tool "$TMP/ensure-again.log" ensure
expect_eq "idempotent: exit 0" "0" "$RC"
expect_grep "idempotent: zero records stamped" "SCHEMA ENSURE: stamped 0 record(s) in 0 file(s)" "$TMP/ensure-again.log"

# ---------- 2. 未来版本：必须显式失败，不能静默降级 ----------
printf '{"schemaVersion":99,"version":"9.9.9","ranAt":"2026-09-01T00:00:00Z","status":"pass"}\n' \
  > "$STATE/test_run_history.jsonl"
run_tool "$TMP/future-validate.log" validate
expect_eq "future: validate exit 13" "13" "$RC"
expect_grep "future: future version reported" "schemaVersion > 1" "$TMP/future-validate.log"
run_tool "$TMP/future-ensure.log" ensure
expect_eq "future: ensure exit 13" "13" "$RC"
expect_eq "future: record untouched" "99" "$(python3 -c "
import json
print(json.loads(open('$STATE/test_run_history.jsonl').readline())['schemaVersion'])")"

# ---------- 3. 非整数 schemaVersion ----------
printf '{"schemaVersion":"1","version":"0.5.3","ranAt":"2026-09-03T00:00:00Z","status":"pass"}\n' \
  > "$STATE/test_run_history.jsonl"
run_tool "$TMP/type.log" validate
expect_eq "type: exit 13" "13" "$RC"
expect_grep "type: reported" "schemaVersion-not-int" "$TMP/type.log"

# ---------- 4. 损坏行：报告但不改写原文 ----------
printf '{"schemaVersion":1,"version":"0.5.4","ranAt":"2026-09-04T00:00:00Z","status":"pass"}\nnot-json\n' \
  > "$STATE/test_run_history.jsonl"
run_tool "$TMP/broken.log" validate
expect_eq "broken: exit 13" "13" "$RC"
expect_grep "broken: invalid line reported" "无法解析" "$TMP/broken.log"
run_tool "$TMP/broken-ensure.log" ensure
expect_eq "broken: ensure still reports problem" "13" "$RC"
expect_grep "broken: raw line preserved" "^not-json$" "$STATE/test_run_history.jsonl"

# ---------- 5. 最新状态缺必备字段（原有 benchmark 门禁）----------
mkdir -p "$TMP/state2"
printf '%s\n' '{"schemaVersion":2,"status":"published","version":"0.5.9"}' \
  > "$TMP/state2/evolution_state_history.jsonl"
STATE="$TMP/state2"
run_tool "$TMP/latest.log" validate
expect_eq "latest: exit 13" "13" "$RC"
expect_grep "latest: missing keys reported" "最新记录缺字段 healthCheck" "$TMP/latest.log"
STATE="$TMP/state"

# ---------- 6. 空/不存在目录是 no-op ----------
STATE="$TMP/does-not-exist"
run_tool "$TMP/absent.log" validate
expect_eq "absent: validate exit 0" "0" "$RC"
run_tool "$TMP/absent-ensure.log" ensure
expect_eq "absent: ensure exit 0" "0" "$RC"
if [[ -d "$TMP/does-not-exist" ]]; then bad "absent: state dir created"; else ok; fi

# ---------- 7. 未登记文件不动；status --json 可解析 ----------
STATE="$TMP/state"
# 还原第 4 步故意写坏的文件，避免影响后续用例
printf '%s\n' '{"schemaVersion":1,"version":"0.5.5","ranAt":"2026-09-05T00:00:00Z","status":"pass"}' \
  > "$STATE/test_run_history.jsonl"
printf '{"whatever":true}\n' > "$STATE/unknown_thing.jsonl"
run_tool "$TMP/status.log" status --json
expect_eq "status: exit 0" "0" "$RC"
python3 - "$TMP/status.log" <<'PY' && ok || bad "status: json payload"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
names = {a["artifact"] for a in data["artifacts"]}
assert "test_run_history.jsonl" in names, names
assert "unknown_thing.jsonl" not in names, names
PY
run_tool "$TMP/unknown.log" ensure
expect_eq "unknown: ensure exit 0" "0" "$RC"
expect_grep "unknown: file untouched" '"whatever":true' "$STATE/unknown_thing.jsonl"

echo "evolution-schema tests: $PASSED passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
