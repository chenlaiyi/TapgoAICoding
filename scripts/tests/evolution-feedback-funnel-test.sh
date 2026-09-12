#!/usr/bin/env bash
# Regression tests for scripts/evolution-feedback-funnel.py.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/evolution-feedback-funnel.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-feedback-funnel.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASSED=0; FAILED=0
ok()  { PASSED=$((PASSED + 1)); }
bad() { FAILED=$((FAILED + 1)); echo "FAIL: $1" >&2; }
expect_eq() { [[ "$2" == "$3" ]] && ok || bad "$1 (expected [$2] got [$3])"; }
expect_grep() { grep -q -- "$2" "$3" 2>/dev/null && ok || bad "$1 (no match '$2')"; }

run_tool() { # run_tool <log> <root> [args...]
  local log="$1" root="$2"; shift 2
  set +e; "$TOOL" report --root "$root" "$@" > "$log" 2>&1; RC=$?; set -e
}
jget() { # jget <json-file> <python-expr on d>
  python3 - "$1" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(eval(sys.argv[2].strip("'"), {"d": d}))
PY
}

# ---------- fixture：3 草稿（1 提升 / 1 未提升 / 1 陈旧）+ 3 注册（1 发布 / 1 回填 / 1 未发布）----------
FIX="$TMP/fixture"
mkdir -p "$FIX/evolution/feedback" "$FIX/evolution/versions"
cat > "$FIX/evolution/feedback/drafts.json" <<'JSON'
{"version": 1, "drafts": [
  {"id": "DR-001", "status": "draft", "discoveredAt": "2026-08-01T00:00:00Z", "text": "promoted"},
  {"id": "DR-002", "status": "draft", "discoveredAt": "2026-08-10T00:00:00Z", "text": "open"},
  {"id": "DR-003", "status": "draft", "discoveredAt": "2026-06-01T00:00:00Z", "text": "stale open"}
]}
JSON
cat > "$FIX/evolution/feedback/registry.json" <<'JSON'
{"version": 2, "entries": [
  {"id": "FB-901", "title": "shipped after registration", "reported": "v0.5.9",
   "sourceDraft": "DR-001", "registeredAt": "2026-08-11", "fixedIn": "v0.5.10", "weight": 10, "check": "true"},
  {"id": "FB-902", "title": "shipped before registration", "reported": "v0.5.19",
   "registeredAt": "2026-08-15", "fixedIn": "v0.5.20", "weight": 10, "check": "true"},
  {"id": "FB-903", "title": "still unshipped", "reported": "2026-06-20",
   "registeredAt": "2026-07-01", "weight": 10, "check": "true"}
]}
JSON
printf '%s\n' '{"version":"0.5.10","tag":"v0.5.10","date":"2026-08-21"}' > "$FIX/evolution/versions/v0.5.10.json"
printf '%s\n' '{"version":"0.5.20","tag":"v0.5.20","date":"2026-08-01"}' > "$FIX/evolution/versions/v0.5.20.json"

run_tool "$TMP/full.json" "$FIX" --json
expect_eq "fixture: exit 0" "0" "$RC"
expect_eq "drafts total" "3" "$(jget "$TMP/full.json" "'d[\"drafts\"][\"total\"]'")"
expect_eq "drafts promoted" "1" "$(jget "$TMP/full.json" "'d[\"drafts\"][\"promoted\"]'")"
expect_eq "drafts open" "2" "$(jget "$TMP/full.json" "'d[\"drafts\"][\"open\"]'")"
expect_eq "drafts stale" "2" "$(jget "$TMP/full.json" "'d[\"drafts\"][\"staleOverDays\"]'")"  # DR-002/DR-003 都早于 today-30d
expect_eq "registered total" "3" "$(jget "$TMP/full.json" "'d[\"registered\"][\"total\"]'")"
expect_eq "registered shipped" "2" "$(jget "$TMP/full.json" "'d[\"registered\"][\"shipped\"]'")"
expect_eq "registered unshipped" "1" "$(jget "$TMP/full.json" "'d[\"registered\"][\"unshipped\"]'")"
expect_eq "registered stale" "1" "$(jget "$TMP/full.json" "'d[\"registered\"][\"staleOverDays\"]'")"
expect_eq "rate draft->registered" "0.3333" "$(jget "$TMP/full.json" "'d[\"conversion\"][\"draftToRegistered\"]'")"
expect_eq "rate registered->shipped" "0.6667" "$(jget "$TMP/full.json" "'d[\"conversion\"][\"registeredToShipped\"]'")"
expect_eq "rate draft->shipped" "0.3333" "$(jget "$TMP/full.json" "'d[\"conversion\"][\"draftToShipped\"]'")"
expect_eq "wait draft->reg median (10d)" "10" "$(jget "$TMP/full.json" "'d[\"waitsDays\"][\"draftToRegisteredMedian\"]'")"
expect_eq "wait draft->reg p95" "10.0" "$(jget "$TMP/full.json" "'d[\"waitsDays\"][\"draftToRegisteredP95\"]'")"
expect_eq "wait reg->shipped median (10d)" "10" "$(jget "$TMP/full.json" "'d[\"waitsDays\"][\"registeredToShippedMedian\"]'")"
expect_eq "backfilled excluded" "1" "$(jget "$TMP/full.json" "'d[\"backfilledShipped\"]'")"
expect_eq "unknown release dates" "0" "$(jget "$TMP/full.json" "'d[\"unknownTimingShipped\"]'")"

# 文本报告与 stale 门禁
run_tool "$TMP/full.txt" "$FIX"
expect_grep "text: conversion line" "conversion:" "$TMP/full.txt"
expect_grep "text: wait line" "wait reg→shipped:" "$TMP/full.txt"
run_tool "$TMP/stale.log" "$FIX" --fail-on-stale
expect_eq "fail-on-stale exit 1" "1" "$RC"
expect_grep "fail-on-stale message" "FEEDBACK FUNNEL STALE" "$TMP/stale.log"
run_tool "$TMP/nostale.log" "$FIX" --stale-days 9999 --fail-on-stale
expect_eq "large stale threshold passes" "0" "$RC"

# 版本号不是日期：fixedIn/reported 里的 vX.Y.Z 不得被当成时间戳
python3 - "$FIX/evolution/feedback/registry.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for entry in data["entries"]:
    entry["registeredAt"] = "v0.5.9"
json.dump(data, open(path, "w", encoding="utf-8"), ensure_ascii=False)
PY
run_tool "$TMP/version-dates.json" "$FIX" --json
expect_eq "version-lookalike dates rejected" "0" "$(jget "$TMP/version-dates.json" "'d[\"waitsDays\"][\"draftToRegisteredSamples\"]'")"
expect_eq "registered->shipped unknown" "2" "$(jget "$TMP/version-dates.json" "'d[\"unknownTimingShipped\"]'")"

# 空目录：全 0、rate 为 null、退出 0
EMPTY="$TMP/empty"; mkdir -p "$EMPTY"
run_tool "$TMP/empty.json" "$EMPTY" --json
expect_eq "empty: exit 0" "0" "$RC"
expect_eq "empty: drafts 0" "0" "$(jget "$TMP/empty.json" "'d[\"drafts\"][\"total\"]'")"
expect_eq "empty: rate null" "None" "$(jget "$TMP/empty.json" "'d[\"conversion\"][\"draftToShipped\"]'")"

# 真实仓库自检：注册表 6 条全部有 fixedIn，且不编造等待时长
run_tool "$TMP/repo.json" "$ROOT" --json
expect_eq "repo: exit 0" "0" "$RC"
expect_eq "repo: registered 6" "6" "$(jget "$TMP/repo.json" "'d[\"registered\"][\"total\"]'")"
expect_eq "repo: shipped 6" "6" "$(jget "$TMP/repo.json" "'d[\"registered\"][\"shipped\"]'")"
expect_eq "repo: no fabricated waits" "0" "$(jget "$TMP/repo.json" "'d[\"waitsDays\"][\"registeredToShippedSamples\"]'")"

echo "evolution-feedback-funnel tests: $PASSED passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
