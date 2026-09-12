#!/usr/bin/env bash
# Single green-gate used by evolve.sh: shell + Swift regressions.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/tests/evolution-lib-test.sh"
"$ROOT/scripts/tests/evolution-records-test.sh"
"$ROOT/scripts/tests/health-check-test.sh"
"$ROOT/scripts/tests/test-failure-report-test.sh"
"$ROOT/scripts/tests/evolution-protect-test.sh"
"$ROOT/scripts/tests/evolution-benchmark-test.sh"
"$ROOT/scripts/tests/evolution-model-eval-test.sh"
"$ROOT/scripts/tests/evolution-remote-lock-test.sh"
"$ROOT/scripts/tests/rollback-drill-test.sh"
"$ROOT/scripts/tests/evolution-feedback-test.sh"
"$ROOT/scripts/tests/evolution-feedback-draft-test.sh"
"$ROOT/scripts/tests/worktree-verify-test.sh"
"$ROOT/scripts/tests/evolution-ui-snapshot-test.sh"
"$ROOT/scripts/tests/evolution-backlog-test.sh"
"$ROOT/scripts/tests/evolution-metrics-test.sh"
"$ROOT/scripts/tests/evolve-failure-injection-test.sh"

TAPGO_SDK="${TAPGO_SDK:-macosx26.5}"
exec xcrun -sdk "$TAPGO_SDK" swift run TapgoTests "$@"
