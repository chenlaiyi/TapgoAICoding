#!/usr/bin/env bash
# Regression tests for scripts/evolution-feedback.py scoring.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/evolution-feedback.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-feedback-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/evolution/feedback"

cat > "$TMP/evolution/feedback/registry.json" <<'JSON'
{"version":1,"entries":[
  {"id":"FB-A","title":"pass","reported":"v1","weight":50,"check":"true"},
  {"id":"FB-B","title":"fail","reported":"v1","weight":50,"check":"false"}
]}
JSON
set +e
python3 "$TOOL" verify --root "$TMP" >/dev/null 2>&1
RC=$?
set -e
[[ "$RC" -eq 1 ]] || { echo "FAIL failing registry rc=$RC" >&2; exit 1; }

cat > "$TMP/evolution/feedback/registry.json" <<'JSON'
{"version":1,"entries":[
  {"id":"FB-A","title":"pass","reported":"v1","weight":50,"check":"true"},
  {"id":"FB-B","title":"pass2","reported":"v1","weight":50,"check":"true"}
]}
JSON
OUT="$(python3 "$TOOL" verify --root "$TMP" --json)"
[[ "$OUT" == *'"score": 100.0'* ]] || { echo "FAIL passing score: $OUT" >&2; exit 1; }
[[ "$OUT" == *'"entries": 2'* ]] || { echo "FAIL entries: $OUT" >&2; exit 1; }

echo "evolution-feedback tests: 3 passed, 0 failed"
