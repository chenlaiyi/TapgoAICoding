#!/usr/bin/env bash
# Regression tests for scripts/evolution-model-eval.py (deterministic, no model).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/evolution-model-eval.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-model-eval-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
HISTORY="$TMP/model_eval.jsonl"

"$TOOL" verify-references --root "$ROOT" >/dev/null

cat > "$TMP/perfect-runner.sh" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
cp -R "$PWD/evolution/model-eval/reference/$EVO_EVAL_TASK_ID/." "$EVO_EVAL_WORKDIR/"
printf '{"total_tokens": 123, "cost_usd": 0.01}\n'
RUNNER
chmod +x "$TMP/perfect-runner.sh"

PERFECT="$(EVOLVE_MODEL_RUNNER="$TMP/perfect-runner.sh" "$TOOL" run --root "$ROOT" --out "$HISTORY" --version 0.5.1)"
python3 - "$PERFECT" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
assert r["score"] == 100, r
assert r["failed"] == [], r
assert r["totalTokens"] == 369, r
assert r["totalDurationSeconds"] > 0, r
PY

cat > "$TMP/lazy-runner.sh" <<'RUNNER'
#!/usr/bin/env bash
exit 0
RUNNER
chmod +x "$TMP/lazy-runner.sh"
LAZY="$(EVOLVE_MODEL_RUNNER="$TMP/lazy-runner.sh" "$TOOL" run --root "$ROOT" --out "$HISTORY" --version 0.5.2)"
python3 - "$LAZY" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
assert r["score"] == 0, r
assert len(r["failed"]) == 3, r
PY

REPORT="$("$TOOL" report --history "$HISTORY")"
[[ "$REPORT" == *"best=100"* ]] || { echo "FAIL report: $REPORT" >&2; exit 1; }

echo "evolution-model-eval tests: 6 passed, 0 failed"
