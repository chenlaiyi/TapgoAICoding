#!/usr/bin/env bash
# Regression tests for scripts/evolution-backlog.py.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/evolution-backlog.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-evolution-backlog-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/evolution"
cat > "$TMP/evolution/BACKLOG.md" <<'MD'
# Backlog
## P0 — high
- [x] **EVO-001 done item**: old
- [ ] **EVO-005 top item**：top detail
## P1 — medium
- [ ] **EVO-006 second item**: second detail
MD

TOP="$(python3 "$TOOL" top --root "$TMP")"
[[ "$TOP" == "EVO-005 top item: top detail" ]] || { echo "FAIL top: $TOP" >&2; exit 1; }
COUNT="$(python3 "$TOOL" list --root "$TMP" --json | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')"
[[ "$COUNT" == "2" ]] || { echo "FAIL open count: $COUNT" >&2; exit 1; }
ALL="$(python3 "$TOOL" list --root "$TMP" --all --json | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')"
[[ "$ALL" == "3" ]] || { echo "FAIL all count: $ALL" >&2; exit 1; }
python3 "$TOOL" validate --root "$TMP" >/dev/null

# Duplicate id must be rejected.
cat >> "$TMP/evolution/BACKLOG.md" <<'MD'
- [ ] **EVO-005 duplicate**: dup
MD
set +e
python3 "$TOOL" validate --root "$TMP" >/dev/null 2>&1
RC=$?
set -e
[[ "$RC" -eq 1 ]] || { echo "FAIL duplicate validate rc=$RC" >&2; exit 1; }

echo "evolution-backlog tests: 5 passed, 0 failed"
