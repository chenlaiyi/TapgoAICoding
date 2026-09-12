#!/usr/bin/env bash
# Automated offscreen render check for the evolution UI components.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-evolution-ui-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/evolution-ui.png"

RESULT="$("$ROOT/scripts/preview-evolution-ui.sh" "$OUT")"
[[ "$RESULT" == *"EVOLUTION UI VERIFY OK"* ]] || { echo "FAIL preview output: $RESULT" >&2; exit 1; }
[[ -f "$OUT" ]] || { echo "FAIL missing snapshot" >&2; exit 1; }
SIZE="$(stat -f%z "$OUT")"
[[ "$SIZE" -gt 10000 ]] || { echo "FAIL blank snapshot size=$SIZE" >&2; exit 1; }

echo "evolution-ui-snapshot tests: 3 passed, 0 failed"
