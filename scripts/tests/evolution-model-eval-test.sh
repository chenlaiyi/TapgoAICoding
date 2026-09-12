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

# Timeout guard: a slow runner must be cut off and fail the task.
cat > "$TMP/slow-runner.sh" <<'RUNNER'
#!/usr/bin/env bash
sleep 5
RUNNER
chmod +x "$TMP/slow-runner.sh"
set +e
SLOW="$(EVOLVE_MODEL_RUNNER="$TMP/slow-runner.sh" "$TOOL" run --root "$ROOT" --tasks fix-off-by-one --timeout-seconds 1)"
SLOW_RC=$?
set -e
[[ "$SLOW_RC" -eq 0 ]] || { echo "FAIL slow rc=$SLOW_RC" >&2; exit 1; }
python3 - "$SLOW" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
assert r["score"] == 0, r
assert r["failed"] == ["fix-off-by-one"], r
PY

# Budget guard: token overrun aborts remaining tasks with exit 3.
cat > "$TMP/token-runner.sh" <<'RUNNER'
#!/usr/bin/env bash
printf '{"total_tokens": 999}\n'
RUNNER
chmod +x "$TMP/token-runner.sh"
set +e
BUDGET="$(EVOLVE_MODEL_RUNNER="$TMP/token-runner.sh" "$TOOL" run --root "$ROOT" --max-tokens 100)"
BUDGET_RC=$?
set -e
[[ "$BUDGET_RC" -eq 3 ]] || { echo "FAIL budget rc=$BUDGET_RC" >&2; exit 1; }
python3 - "$BUDGET" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
assert r["aborted"] == "max_tokens", r
assert r["completedTasks"] == 1, r
PY

# A/B: candidate worse than baseline must fail the gate.
set +e
AB_BAD="$("$TOOL" ab --root "$ROOT" --tasks fix-off-by-one \
  --runners "perfect=$TMP/perfect-runner.sh" --runners "lazy=$TMP/lazy-runner.sh" \
  --require-candidate-not-worse)"
AB_BAD_RC=$?
set -e
[[ "$AB_BAD_RC" -eq 1 ]] || { echo "FAIL ab regression rc=$AB_BAD_RC" >&2; exit 1; }
python3 - "$AB_BAD" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
assert r["baseline"] == "perfect", r
assert r["comparison"][0]["score"] == 100, r
assert r["comparison"][1]["score"] == 0, r
assert r["comparison"][1]["deltaVsBaseline"] == -100.0, r
PY

# A/B: candidate better than baseline passes.
"$TOOL" ab --root "$ROOT" --tasks fix-off-by-one \
  --runners "lazy=$TMP/lazy-runner.sh" --runners "perfect=$TMP/perfect-runner.sh" \
  --require-candidate-not-worse >/dev/null

# Operator wrapper refuses without explicit confirmation.
set +e
"$ROOT/scripts/run-model-eval.sh" >/dev/null 2>&1
WRAP_RC=$?
set -e
[[ "$WRAP_RC" -eq 2 ]] || { echo "FAIL wrapper rc=$WRAP_RC" >&2; exit 1; }

echo "evolution-model-eval tests: 13 passed, 0 failed"
