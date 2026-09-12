#!/usr/bin/env bash
# Regression tests for scripts/evolution-benchmark.py scoring + compare.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/evolution-benchmark.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-evolution-benchmark.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/evolution"
HISTORY="$TMP/history.jsonl"

write_spec() {
  cat > "$TMP/evolution/benchmark.json" <<JSON
{"version":1,"checks":[{"id":"pass","weight":60,"command":"${1}"},{"id":"other","weight":40,"command":"${2}"}]}
JSON
}

write_spec true false
RUN1="$(python3 "$TOOL" run --root "$TMP" --history "$HISTORY" --version 0.5.1)"
[[ "$RUN1" == *'"score": 60'* ]] || { echo "FAIL first score: $RUN1" >&2; exit 1; }
python3 "$TOOL" compare --history "$HISTORY" >/dev/null

write_spec true true
python3 "$TOOL" run --root "$TMP" --history "$HISTORY" --version 0.5.2 >/dev/null
python3 "$TOOL" compare --history "$HISTORY" >/dev/null

write_spec true false
python3 "$TOOL" run --root "$TMP" --history "$HISTORY" --version 0.5.3 >/dev/null
set +e
python3 "$TOOL" compare --history "$HISTORY" >/dev/null 2>&1
RC=$?
set -e
[[ "$RC" -eq 1 ]] || { echo "FAIL regression rc=$RC" >&2; exit 1; }

echo "evolution-benchmark tests: 4 passed, 0 failed"
