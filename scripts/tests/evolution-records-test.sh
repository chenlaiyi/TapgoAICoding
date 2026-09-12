#!/usr/bin/env bash
# Regression tests for scripts/evolution-records.py (structured version source).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/evolution-records.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-evolution-records-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/AppBuilder" "$TMP/evolution/versions"
printf '# Evolution Log\n' > "$TMP/EVOLUTION.md"
cat > "$TMP/AppBuilder/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>0.5.10</string>
</dict></plist>
PLIST
printf 'MARKETING_VERSION: "0.5.10"\nCURRENT_PROJECT_VERSION: "0.5.10"\n' > "$TMP/AppBuilder/project.yml"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1" >&2; }
assert_contains() { [[ "$1" == *"$2"* ]] && ok || bad "$3 (missing: $2)"; }
assert_not_contains() { [[ "$1" != *"$2"* ]] && ok || bad "$3 (unexpected: $2)"; }
assert_rc() { [[ "$1" -eq "$2" ]] && ok || bad "$3 (rc=$1 expected=$2)"; }

python3 "$TOOL" add --root "$TMP" --version 0.5.10 --message "feat: first record" \
  --details "details line" --next "next step" --test-status pending >/dev/null
[[ -f "$TMP/evolution/versions/v0.5.10.json" ]] && ok || bad "add creates record"

ENTRY="$(python3 "$TOOL" render-entry --root "$TMP" --version 0.5.10)"
assert_contains "$ENTRY" "## v0.5.10 — feat: first record" "render-entry header"
assert_contains "$ENTRY" "**Test status**: pending" "render-entry test status"
assert_contains "$ENTRY" "details line" "render-entry details"

set +e
python3 "$TOOL" validate --root "$TMP" --require-rendered >/dev/null 2>&1
RC=$?
set -e
assert_rc "$RC" 1 "validate rejects record missing EVOLUTION section"

printf '\n%s\n' "$ENTRY" >> "$TMP/EVOLUTION.md"
python3 "$TOOL" validate --root "$TMP" --require-rendered --check-current >/dev/null
ok

python3 "$TOOL" set-test-status --root "$TMP" --version 0.5.10 --value "— 10 passed, 0 failed —"
ENTRY2="$(python3 "$TOOL" render-entry --root "$TMP" --version 0.5.10)"
assert_contains "$ENTRY2" "**Test status**: — 10 passed, 0 failed —" "set-test-status updates render"

NOTES="$(python3 "$TOOL" render-notes --root "$TMP" --version 0.5.10)"
assert_contains "$NOTES" "# v0.5.10" "render-notes title"
assert_contains "$NOTES" "feat: first record" "render-notes message"

set +e
python3 "$TOOL" add --root "$TMP" --version 0.5.10 --message duplicate --next n >/dev/null 2>&1
RC=$?
set -e
assert_rc "$RC" 3 "duplicate add rejected"

set +e
python3 "$TOOL" add --root "$TMP" --version 0.5 --message bad --next n >/dev/null 2>&1
RC=$?
set -e
assert_rc "$RC" 2 "invalid version rejected"

sed -i '' 's/0.5.10/0.5.9/g' "$TMP/AppBuilder/Info.plist" "$TMP/AppBuilder/project.yml"
set +e
python3 "$TOOL" validate --root "$TMP" --check-current >/dev/null 2>&1
RC=$?
set -e
assert_rc "$RC" 1 "check-current rejects stale plist/project"

# iOS scope renders into evolution/ios/EVOLUTION.md, not the Mac log.
ITMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-evolution-ios-test.XXXXXX")"
trap 'rm -rf "$ITMP"' EXIT
mkdir -p "$ITMP/AppBuilder" "$ITMP/evolution/versions" "$ITMP/evolution/ios"
printf '# iOS Evolution Log\n' > "$ITMP/evolution/ios/EVOLUTION.md"
printf '# Evolution Log\n' > "$ITMP/EVOLUTION.md"
python3 "$TOOL" add --root "$ITMP" --version 1.0.2 --scope ios --message "ios record" --next n >/dev/null
set +e
python3 "$TOOL" validate --root "$ITMP" --require-rendered >/dev/null 2>&1
RC=$?
set -e
assert_rc "$RC" 1 "iOS record requires iOS rendered section"
python3 "$TOOL" render-entry --root "$ITMP" --version 1.0.2 >> "$ITMP/evolution/ios/EVOLUTION.md"
python3 "$TOOL" validate --root "$ITMP" --require-rendered >/dev/null
ok

echo "evolution-records tests: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
