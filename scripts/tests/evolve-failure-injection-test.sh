#!/usr/bin/env bash
# Failure-injection matrix for evolve.sh.
#
# Each scenario builds a disposable git repo containing the real evolve.sh +
# structured-record tooling, but fake test/build/release entrypoints. This
# exercises the actual version patching, staging, commit/tag, rollback and
# state-machine code without running Swift builds.
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BASE="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-evolve-failure.XXXXXX")"
trap 'if [[ "$FAIL" -eq 0 ]]; then rm -rf "$BASE"; else echo "kept failure repo: $BASE" >&2; fi' EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1" >&2; }
assert_eq() { [[ "$1" == "$2" ]] && ok || bad "$3 (expected=$2 actual=$1)"; }
assert_file() { [[ -e "$1" ]] && ok || bad "$2 (missing $1)"; }
assert_no_file() { [[ ! -e "$1" ]] && ok || bad "$2 (unexpected $1)"; }
assert_grep() { grep -q -- "$2" "$1" 2>/dev/null && ok || bad "$3 ($1 missing '$2')"; }
assert_not_grep() { ! grep -q -- "$2" "$1" 2>/dev/null && ok || bad "$3 ($1 unexpectedly has '$2')"; }
assert_json() {
  local file="$1" expr="$2" label="$3"
  python3 - "$file" "$expr" <<'PY' && ok || bad "$label"
import json, sys
data = json.load(open(sys.argv[1]))
eval(sys.argv[2], {"d": data, "len": len})
PY
}

make_repo() {
  local dir="$1"
  mkdir -p "$dir/scripts/tests" "$dir/AppBuilder" "$dir/evolution/versions"
  cp "$SOURCE_ROOT/scripts/evolve.sh" "$dir/scripts/evolve.sh"
  cp "$SOURCE_ROOT/scripts/evolution-lib.sh" "$dir/scripts/evolution-lib.sh"
  cp "$SOURCE_ROOT/scripts/evolution-records.py" "$dir/scripts/evolution-records.py"
  cp "$SOURCE_ROOT/scripts/tapgo-repo-slug.sh" "$dir/scripts/tapgo-repo-slug.sh"
  cp "$SOURCE_ROOT/scripts/evolution-backlog.py" "$dir/scripts/evolution-backlog.py"
  chmod +x "$dir/scripts/evolution-backlog.py"
  cat > "$dir/evolution/BACKLOG.md" <<'MD'
# Backlog
## P0
- [ ] **EVO-999 test backlog item**: next from backlog
MD
  chmod +x "$dir/scripts/evolve.sh" "$dir/scripts/evolution-records.py"
  cat > "$dir/AppBuilder/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>0.5.1</string>
<key>CFBundleVersion</key><string>0.5.1</string>
</dict></plist>
PLIST
  cat > "$dir/AppBuilder/ComputerUseHelper-Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>0.5.1</string>
<key>CFBundleVersion</key><string>0.5.1</string>
</dict></plist>
PLIST
  printf 'MARKETING_VERSION: "0.5.1"\nCURRENT_PROJECT_VERSION: "0.5.1"\n' > "$dir/AppBuilder/project.yml"
  printf '# Evolution Log\n' > "$dir/EVOLUTION.md"
  printf 'Tapgo AICoding.app/\n.build/\nstate/\n' > "$dir/.gitignore"

  cat > "$dir/scripts/tests/run-all.sh" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
echo "— 10 passed, 0 failed —"
exit "${FAKE_TESTS_RC:-0}"
FAKE
  cat > "$dir/scripts/build-app.sh" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${FAKE_BUILD_RC:-0}" != "0" ]]; then
  echo "fake build failure" >&2
  exit 9
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/AppBuilder/Info.plist")"
mkdir -p "$ROOT/Tapgo AICoding.app/Contents"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$ROOT/Tapgo AICoding.app/Contents/Info.plist" >/dev/null 2>&1 || \
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$ROOT/Tapgo AICoding.app/Contents/Info.plist"
FAKE
  cat > "$dir/scripts/create-github-release-artifacts.sh" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
echo "fake release: $*"
exit "${FAKE_RELEASE_RC:-0}"
FAKE
  chmod +x "$dir/scripts/tests/run-all.sh" "$dir/scripts/build-app.sh" "$dir/scripts/create-github-release-artifacts.sh"

  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name "Evolution Test"
  git -C "$dir" add -A
  git -C "$dir" commit -qm "baseline"
  git -C "$dir" tag -a v0.5.1 -m "v0.5.1"
}

run_evolve() {
  local repo="$1" state="$2" log="$3"; shift 3
  (
    cd "$repo"
    export TAPGO_REPO_SLUG="test/repo"
    export EVOLVE_SKIP_SDK_CHECK=1
    export EVOLVE_TESTS_SCRIPT="$repo/scripts/tests/run-all.sh"
    export EVOLVE_BUILD_SCRIPT="$repo/scripts/build-app.sh"
    export EVOLVE_RELEASE_SCRIPT="$repo/scripts/create-github-release-artifacts.sh"
    export EVOLVE_RECORDS_TOOL="$repo/scripts/evolution-records.py"
    export EVOLVE_STATE_DIR="$state"
    bash "$repo/scripts/evolve.sh" "$@"
  ) >"$log" 2>&1
}

# ---------- S1: dirty path not covered by --paths ----------
R1="$BASE/s1"; make_repo "$R1"; echo unrelated > "$R1/UNRELATED.txt"
set +e; run_evolve "$R1" "$BASE/s1-state" "$BASE/s1.log" --paths scripts patch "s1" "s1" --next n; RC=$?; set -e
assert_eq "$RC" 9 "s1 exit 9 on uncovered dirty path"
assert_eq "$(git -C "$R1" rev-list --count HEAD)" 1 "s1 no commit"
assert_no_file "$R1/evolution/versions/v0.5.2.json" "s1 no record"

# ---------- S2: tests fail -> full rollback ----------
R2="$BASE/s2"; make_repo "$R2"
set +e; FAKE_TESTS_RC=1 run_evolve "$R2" "$BASE/s2-state" "$BASE/s2.log" --paths scripts patch "s2" "s2" --next n; RC=$?; set -e
assert_eq "$RC" 5 "s2 exit 5 on test failure"
assert_eq "$(git -C "$R2" rev-list --count HEAD)" 1 "s2 no commit"
assert_eq "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$R2/AppBuilder/Info.plist")" 0.5.1 "s2 plist rolled back"
assert_eq "$(grep -c '^## v0.5.2' "$R2/EVOLUTION.md" || true)" 0 "s2 EVOLUTION rolled back"
assert_no_file "$R2/evolution/versions/v0.5.2.json" "s2 record removed"
assert_eq "$(git -C "$R2" branch --list 'codex/evolution-v0.5.2' | wc -l | tr -d ' ')" 0 "s2 iteration branch removed"

# ---------- S3: build fails -> full rollback ----------
R3="$BASE/s3"; make_repo "$R3"
set +e; FAKE_BUILD_RC=1 run_evolve "$R3" "$BASE/s3-state" "$BASE/s3.log" --paths scripts patch "s3" "s3" --next n; RC=$?; set -e
assert_eq "$RC" 4 "s3 exit 4 on build failure"
assert_eq "$(git -C "$R3" rev-list --count HEAD)" 1 "s3 no commit"
assert_eq "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$R3/AppBuilder/Info.plist")" 0.5.1 "s3 plist rolled back"
assert_no_file "$R3/evolution/versions/v0.5.2.json" "s3 record removed"
assert_eq "$(git -C "$R3" branch --list 'codex/evolution-v0.5.2' | wc -l | tr -d ' ')" 0 "s3 iteration branch removed"

# ---------- S4: success local -> commit/tag/record/state ----------
R4="$BASE/s4"; make_repo "$R4"
run_evolve "$R4" "$BASE/s4-state" "$BASE/s4.log" --paths scripts \
  --why "s4 rationale" --change "change one" --change "change two" \
  patch "s4 message" "s4 details"
assert_eq "$(git -C "$R4" rev-list --count HEAD)" 2 "s4 committed"
assert_eq "$(git -C "$R4" tag --list v0.5.2)" v0.5.2 "s4 tagged"
assert_eq "$(git -C "$R4" rev-parse HEAD)" "$(git -C "$R4" rev-parse codex/evolution-v0.5.2)" "s4 main fast-forwards iteration branch"
assert_eq "$(python3 -c 'import json;print(json.load(open("'"$BASE"'/s4-state/evolution_state.json"))["iterationBranch"])')" codex/evolution-v0.5.2 "s4 state records iteration branch"
assert_json "$R4/evolution/versions/v0.5.2.json" 'd["why"]' "s4 why stored"
assert_json "$R4/evolution/versions/v0.5.2.json" 'len(d["changes"])' "s4 changes stored"
assert_json "$R4/evolution/versions/v0.5.2.json" '"EVO-999" in d["next"]' "s4 next resolved from backlog"
assert_json "$BASE/s4-state/evolution_state.json" '"EVO-999" in d["nextActions"][0]' "s4 state next resolved from backlog"
assert_json "$BASE/s4-state/evolution_state.json" 'd["status"]' "s4 state status"
assert_grep "$R4/EVOLUTION.md" "## v0.5.2 — s4 message" "s4 rendered log"
assert_eq "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$R4/Tapgo AICoding.app/Contents/Info.plist")" 0.5.2 "s4 built app version"

# ---------- S5: unmerged existing tag -> refuse reuse ----------
R5="$BASE/s5"; make_repo "$R5"
TREE="$(git -C "$R5" rev-parse 'HEAD^{tree}')"
ORPHAN="$(printf orphan | git -C "$R5" commit-tree "$TREE")"
git -C "$R5" tag -a v0.5.2 "$ORPHAN" -m "orphan v0.5.2"
set +e; run_evolve "$R5" "$BASE/s5-state" "$BASE/s5.log" --paths scripts patch "s5" "s5" --next n; RC=$?; set -e
assert_eq "$RC" 3 "s5 refuses existing tag"
assert_eq "$(git -C "$R5" rev-list --count HEAD)" 1 "s5 no commit"

# ---------- S6: publish, release fails after push -> state release_failed ----------
R6="$BASE/s6"; make_repo "$R6"
git -C "$R6" init -q --bare "$BASE/s6-origin.git"
git -C "$R6" remote add origin "$BASE/s6-origin.git"
git -C "$R6" push -q -u origin main --tags
set +e; FAKE_RELEASE_RC=1 run_evolve "$R6" "$BASE/s6-state" "$BASE/s6.log" --publish --paths scripts patch "s6" "s6" --next n; RC=$?; set -e
assert_eq "$RC" 7 "s6 exit 7 on release failure"
assert_eq "$(git -C "$R6" tag --list v0.5.2)" v0.5.2 "s6 local tag retained"
assert_eq "$(git -C "$BASE/s6-origin.git" tag --list v0.5.2)" v0.5.2 "s6 remote tag pushed"
assert_json "$BASE/s6-state/evolution_state.json" 'd["status"]' "s6 release_failed state"
assert_eq "$(git -C "$BASE/s6-origin.git" branch --list codex/evolution-v0.5.2 | wc -l | tr -d ' ')" 1 "s6 iteration branch pushed"

# ---------- S7: publish success -> published ----------
R7="$BASE/s7"; make_repo "$R7"
git -C "$R7" init -q --bare "$BASE/s7-origin.git"
git -C "$R7" remote add origin "$BASE/s7-origin.git"
git -C "$R7" push -q -u origin main --tags
run_evolve "$R7" "$BASE/s7-state" "$BASE/s7.log" --publish --paths scripts patch "s7" "s7" --next n
assert_json "$BASE/s7-state/evolution_state.json" 'd["status"]' "s7 published state"
assert_eq "$(git -C "$BASE/s7-origin.git" tag --list v0.5.2)" v0.5.2 "s7 remote tag"
assert_eq "$(git -C "$R7" rev-list --count origin/main)" 2 "s7 origin main advanced"
assert_eq "$(git -C "$BASE/s7-origin.git" branch --list codex/evolution-v0.5.2 | wc -l | tr -d ' ')" 1 "s7 iteration branch pushed"

# ---------- S8: pre-dirty auto-managed EVOLUTION.md is covered ----------
R8="$BASE/s8"; make_repo "$R8"
printf '# Evolution Log\n\n<!-- hand edit -->\n' > "$R8/EVOLUTION.md"
run_evolve "$R8" "$BASE/s8-state" "$BASE/s8.log" --paths scripts patch "s8" "s8" --next n
assert_eq "$(git -C "$R8" rev-list --count HEAD)" 2 "s8 committed with pre-dirty managed file"
assert_grep "$R8/EVOLUTION.md" "hand edit" "s8 preserves pre-existing managed edit"

echo "evolve failure-injection tests: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
