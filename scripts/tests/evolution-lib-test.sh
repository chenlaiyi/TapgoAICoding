#!/usr/bin/env bash
# Shell-level regression tests for the pure self-evolution helpers.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=scripts/evolution-lib.sh
source "$ROOT/scripts/evolution-lib.sh"

PASS=0
FAIL=0
assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" == "$expected" ]]; then PASS=$((PASS + 1)); else
    FAIL=$((FAIL + 1)); printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$label" "$expected" "$actual" >&2
  fi
}

assert_eq "$(printf '%s\n' v0.5.9 v0.5.256 v0.5.10 v0.5.08 | evo_max_version)" "v0.5.256" "max-version: numeric order + leading zero"
assert_eq "$(printf '%s\n' v1.0.1 v0.5.999 | evo_max_version)" "v1.0.1" "max-version: major series"
assert_eq "$(printf '%s\n' nonsense v0.5.99 | evo_max_version)" "v0.5.99" "max-version: ignores invalid tags"
set +e
OUT="$(printf 'nonsense\n' | evo_max_version)"
RC=$?
set -e
assert_eq "$RC" "0" "max-version: no valid tag returns rc 0"
assert_eq "$OUT" "" "max-version: no valid tag prints nothing"
assert_eq "$(evo_max_version)" "" "max-version: empty input"
assert_eq "$(evo_next_version v0.5.256 patch)" "0.5.257" "next-version: patch"
assert_eq "$(evo_next_version v0.5.09 minor)" "0.6.0" "next-version: minor + leading zero"
assert_eq "$(evo_next_version 0.5.256 major)" "1.0.0" "next-version: major"

if evo_path_covered "Sources/A.swift" "Sources"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL path-cover: dir prefix" >&2; fi
if evo_path_covered "scripts/evolve.sh" "scripts/evolve.sh"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL path-cover: exact file" >&2; fi
if evo_path_covered "README.md" "Sources"; then FAIL=$((FAIL + 1)); echo "FAIL path-cover: unrelated must be rejected" >&2; else PASS=$((PASS + 1)); fi
if evo_path_covered "SourcesX/A.swift" "Sources"; then FAIL=$((FAIL + 1)); echo "FAIL path-cover: sibling prefix must be rejected" >&2; else PASS=$((PASS + 1)); fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-evolution-lib-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
printf '# Evolution Log\n## v0.5.256 — old\nbody\n' > "$tmp/EVOLUTION.md"
printf '## v0.5.257 — new\nbody-new\n' > "$tmp/entry.md"
evo_insert_evolution_entry "$tmp/EVOLUTION.md" "$tmp/entry.md"
assert_eq "$(head -1 "$tmp/EVOLUTION.md")" "# Evolution Log" "insert-entry: keeps title"
assert_eq "$(sed -n '3p' "$tmp/EVOLUTION.md")" "## v0.5.257 — new" "insert-entry: newest first"
assert_eq "$(grep -c '^## v0.5.257' "$tmp/EVOLUTION.md")" "1" "insert-entry: exactly once"

evo_lock_acquire "$tmp/lock"
assert_eq "$(cat "$tmp/lock/pid")" "$$" "lock: owner pid"
if ( evo_lock_acquire "$tmp/lock" ); then
  FAIL=$((FAIL + 1)); echo "FAIL lock: second acquire should fail" >&2
else
  PASS=$((PASS + 1))
fi
evo_lock_release "$tmp/lock"
if [[ ! -d "$tmp/lock" ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL lock: release removes dir" >&2; fi

echo "evolution-lib tests: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
