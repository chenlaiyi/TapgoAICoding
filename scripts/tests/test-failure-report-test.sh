#!/usr/bin/env bash
# Regression tests for scripts/test-failure-report.py.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/test-failure-report.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-test-failure-report.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
LOG="$TMP/fail.log"
HISTORY="$TMP/history.jsonl"
cat > "$LOG" <<'LOG'
[run] RemoteSSH: live [START]
  ✗ remote list failed: sshFailed("ssh: connect to host 203.0.113.10 port 22: Operation timed out")  (/tmp/RemoteDirTests.swift:159)
[end] RemoteSSH: live  [FAIL]  passed=10 failed=1
[run] Parser: real regression [START]
  ✗ expected 42, got 41  (/tmp/ParserTests.swift:22)
[end] Parser: real regression  [FAIL]  passed=20 failed=1
— 30 passed, 2 failed —
LOG

PARSED="$(python3 "$TOOL" parse --log "$LOG")"
python3 - "$PARSED" <<'PY'
import json, sys
p = json.loads(sys.argv[1])
assert p["passed"] == 30 and p["failed"] == 2, p
assert len(p["failedSections"]) == 2, p
assert p["environmentFailures"] == 1, p
assert p["realFailures"] == 1, p
PY

RERUNS='[{"section":"Parser: real regression","passed":true}]'
python3 "$TOOL" record --log "$LOG" --history "$HISTORY" --version 0.5.9 --status fail --reruns "$RERUNS" >/dev/null
FLAKY="$(python3 "$TOOL" flaky --history "$HISTORY")"
python3 - "$FLAKY" <<'PY'
import json, sys
f = json.loads(sys.argv[1])
assert f["runs"] == 1, f
assert f["lastStatus"] == "fail", f
assert f["flakyCount"] == 1 and f["flakySections"] == ["Parser: real regression"], f
assert f["environmentFailures"] == 1 and f["realFailures"] == 1, f
PY

echo "test-failure-report tests: 8 passed, 0 failed"
