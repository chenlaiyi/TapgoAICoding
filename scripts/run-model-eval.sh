#!/usr/bin/env bash
# Operator-only wrapper for the model-level evaluation.
#
# Codex never runs this automatically. A human must:
#   1. provide a real runner via EVOLVE_MODEL_RUNNER
#   2. pass --i-understand-this-spends-model-credits
#
# Usage:
#   EVOLVE_MODEL_RUNNER='<command using $EVO_EVAL_WORKDIR/$EVO_EVAL_PROMPT>' \
#     ./scripts/run-model-eval.sh --i-understand-this-spends-model-credits [options]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIRMED=""
PASSTHROUGH=()
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --i-understand-this-spends-model-credits) CONFIRMED=1 ;;
    *) PASSTHROUGH+=("$1") ;;
  esac
  shift
done

if [[ -z "$CONFIRMED" ]]; then
  echo "REFUSED: pass --i-understand-this-spends-model-credits to run model evaluation." >&2
  exit 2
fi
if [[ -z "${EVOLVE_MODEL_RUNNER:-}" ]]; then
  echo "REFUSED: EVOLVE_MODEL_RUNNER is required; this wrapper never picks a model itself." >&2
  exit 2
fi

STATE_DIR="${EVOLVE_STATE_DIR:-$HOME/Library/Application Support/Tapgo AICoding/state}"
HISTORY="${EVOLVE_MODEL_EVAL_HISTORY:-$STATE_DIR/model_eval_history.jsonl}"
mkdir -p "$STATE_DIR"

echo "==> Model eval policy: timeout=300s max_tokens=200000 max_cost=\$5 max_duration=1800s"
echo "==> Runner: $EVOLVE_MODEL_RUNNER"
echo "==> History: $HISTORY"
python3 scripts/evolution-model-eval.py run --out "$HISTORY" "${PASSTHROUGH[@]+"${PASSTHROUGH[@]}"}"
python3 scripts/evolution-model-eval.py report --history "$HISTORY"
