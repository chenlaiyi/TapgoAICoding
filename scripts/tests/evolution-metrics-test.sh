#!/usr/bin/env bash
# Regression tests for scripts/evolution-metrics.py.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-evolution-metrics-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/evolution/versions"
cat > "$TMP/evolution/BACKLOG.md" <<'MD'
# Backlog
- [x] done item
- [ ] open item one
- [ ] open item two
MD
cat > "$TMP/evolution/versions/v0.5.1.json" <<'JSON'
{"version":"0.5.1","tag":"v0.5.1","date":"2026-09-01","scope":"mac","message":"m1","changes":["c"],"details":"d","why":"w","next":"n","testStatus":"— 100 passed, 0 failed —","commitSha":null}
JSON
cat > "$TMP/evolution/versions/v0.5.2.json" <<'JSON'
{"version":"0.5.2","tag":"v0.5.2","date":"2026-09-02","scope":"mac","message":"m2","changes":["c"],"details":"d","why":"w","next":"n","testStatus":"pending","commitSha":null}
JSON
cat > "$TMP/history.jsonl" <<'JSONL'
{"status":"published","version":"0.5.1","mode":"publish","builtAt":"2026-09-01T00:00:00Z","testStatus":"— 100 passed, 0 failed —"}
{"status":"committed","version":"0.5.2","mode":"publish","builtAt":"2026-09-02T00:00:00Z","testStatus":"— 200 passed, 0 failed —"}
{"status":"release_failed","version":"0.5.2","mode":"publish","builtAt":"2026-09-02T01:00:00Z","testStatus":"— 200 passed, 0 failed —"}
{"status":"published","version":"0.5.3","mode":"publish","builtAt":"2026-09-03T01:00:00Z","testStatus":"— 300 passed, 0 failed —"}
JSONL

OUT="$(python3 "$ROOT/scripts/evolution-metrics.py" --root "$TMP" --history "$TMP/history.jsonl" --json)"
python3 - "$OUT" <<'PY'
import json, sys
m = json.loads(sys.argv[1])
assert m["recordCount"] == 2, m
assert m["iterations"] == 3, m
assert m["published"] == 2, m
assert m["failed"] == 1, m
assert abs(m["successRate"] - 2/3) < 1e-9, m
assert m["testPassedTotal"] == 600, m
assert m["openBacklog"] == 2 and m["doneBacklog"] == 1, m
assert m["medianCycleSeconds"] == 176400.0, m  # 49h between published v0.5.1 and v0.5.3
print("evolution-metrics assertions: 8 passed, 0 failed")
PY
