#!/usr/bin/env bash
# Regression tests for monthly state-history archiving.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/evolution-archive.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-archive-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
STATE="$TMP/state"; mkdir -p "$STATE"
cat > "$STATE/evolution_state_history.jsonl" <<'JSONL'
{"version":"0.5.1","builtAt":"2026-07-05T00:00:00Z"}
{"version":"0.5.2","builtAt":"2026-08-20T00:00:00Z"}
{"version":"0.5.3","builtAt":"2026-09-10T00:00:00Z"}
{"version":"no-time","note":"keep me"}
JSONL

python3 "$TOOL" archive --state-dir "$STATE" --keep-days 15 --now 2026-09-12T00:00:00Z >/dev/null
LIVE="$STATE/evolution_state_history.jsonl"
[[ "$(wc -l < "$LIVE" | tr -d ' ')" == "2" ]] || { echo "FAIL live count" >&2; exit 1; }
[[ -f "$STATE/archive/evolution_state_history-2026-07.jsonl" ]] || { echo "FAIL july archive" >&2; exit 1; }
[[ -f "$STATE/archive/evolution_state_history-2026-08.jsonl" ]] || { echo "FAIL august archive" >&2; exit 1; }
grep -q 'no-time' "$LIVE" || { echo "FAIL untimestamped record kept" >&2; exit 1; }

# Idempotent: second run moves nothing and does not duplicate archives.
python3 "$TOOL" archive --state-dir "$STATE" --keep-days 15 --now 2026-09-12T00:00:00Z >/dev/null
[[ "$(wc -l < "$STATE/archive/evolution_state_history-2026-07.jsonl" | tr -d ' ')" == "1" ]] || { echo "FAIL archive idempotence" >&2; exit 1; }
STATUS="$(python3 "$TOOL" status --state-dir "$STATE")"
[[ "$STATUS" == *"LIVE evolution_state_history.jsonl"* && "$STATUS" == *"ARCHIVE evolution_state_history-2026-07.jsonl"* ]] || { echo "FAIL status: $STATUS" >&2; exit 1; }

echo "evolution-archive tests: 6 passed, 0 failed"
