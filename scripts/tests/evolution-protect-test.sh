#!/usr/bin/env bash
# Regression tests for scripts/evolution-protect.py.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/evolution-protect.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-evolution-protect.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO/evolution" "$REPO/scripts/tests"
printf '{"version":1,"paths":["scripts/evolve.sh","scripts/tests/**","AGENTS.md"]}\n' > "$REPO/evolution/protected-paths.json"
printf '#!/usr/bin/env bash\necho v1\n' > "$REPO/scripts/evolve.sh"
printf 'test v1\n' > "$REPO/scripts/tests/run-all.sh"
printf 'agents v1\n' > "$REPO/AGENTS.md"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name Test
git -C "$REPO" add -A
git -C "$REPO" commit -qm baseline
git -C "$REPO" tag -a v0.5.1 -m v0.5.1

python3 "$TOOL" --root "$REPO" check --base v0.5.1 >/dev/null
printf 'safe change\n' > "$REPO/README.md"
python3 "$TOOL" --root "$REPO" check --base v0.5.1 >/dev/null

printf '#!/usr/bin/env bash\necho v2\n' > "$REPO/scripts/evolve.sh"
set +e
python3 "$TOOL" --root "$REPO" check --base v0.5.1 >/dev/null 2>&1
RC=$?
set -e
[[ "$RC" -eq 1 ]] || { echo "FAIL unapproved protected change rc=$RC" >&2; exit 1; }

TOKEN="$(python3 "$TOOL" --root "$REPO" token --base v0.5.1)"
[[ -n "$TOKEN" ]] || { echo "FAIL empty token" >&2; exit 1; }
python3 "$TOOL" --root "$REPO" check --base v0.5.1 --approve "$TOKEN" >/dev/null
printf 'test v2\n' > "$REPO/scripts/tests/run-all.sh"
set +e
python3 "$TOOL" --root "$REPO" check --base v0.5.1 --approve "$TOKEN" >/dev/null 2>&1
RC=$?
set -e
[[ "$RC" -eq 1 ]] || { echo "FAIL stale token after further edit rc=$RC" >&2; exit 1; }

echo "evolution-protect tests: 5 passed, 0 failed"
