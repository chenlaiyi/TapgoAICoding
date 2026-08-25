#!/usr/bin/env bash
# evolve.sh — One-command self-evolution cycle.
#
# Usage:
#   ./scripts/evolve.sh <version-bump> "<commit message>" "<evolution summary>"
#
# Examples:
#   ./scripts/evolve.sh patch "fix: sidebar crash on empty workspace" \
#     "Crash when SidebarView renders with 0 projects; root cause ..."
#   ./scripts/evolve.sh minor "feat: dark mode for ChatView" \
#     "Add system-appearance-aware colors throughout chat rendering"
#   ./scripts/evolve.sh major "BREAKING: rework approval flow" \
#     "Replace modal with inline ApprovalRow (see ADR-007)"
#
# Bump types:
#   patch — 0.3.0 → 0.3.1  (default; bug fixes, small polish)
#   minor — 0.3.0 → 0.4.0  (new features, backwards-compatible)
#   major — 0.3.0 → 1.0.0  (breaking changes)
#
# What this script does (in order, all atomic):
#   1. Sanity-check the working tree (no uncommitted source changes
#      OTHER than the ones this script itself creates).
#   2. Compute the next version from the current tag (or Info.plist).
#   3. Patch Info.plist's CFBundleShortVersionString + CFBundleVersion.
#   4. swift build -c release --product TapgoAICoding  (must succeed)
#   5. swift run TapgoTests                         (must stay green)
#   6. Append a section to EVOLUTION.md.
#   7. git add + commit + tag + push (origin main + tags).
#   8. Rebuild the .app bundle so a restart picks up the new binary.
#   9. Write ~/Library/Application Support/Tapgo AICoding/state/evolution_state.json
#      so a restarted session knows where we are and what's next.
#  10. Print a summary block + the rollback command.
#
# On ANY failure after step 4, the script:
#   - resets Info.plist to HEAD
#   - does NOT commit, tag, or push
#   - exits non-zero so a caller (or you) knows it didn't take
#
# Rollback at any time:
#   git checkout v0.3.5 && ./scripts/build-app.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ---------- Args ----------
BUMP="${1:-patch}"
MSG="${2:-"chore: evolve"}"
SUMMARY="${3:-_no_summary_}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${2:-}" == "-h" || "${2:-}" == "--help" ]]; then
  sed -n '2,45p' "$0"
  exit 0
fi

case "$BUMP" in
  patch|minor|major) ;;
  *) echo "ERROR: bump must be patch|minor|major (got: $BUMP)" >&2; exit 2 ;;
esac

# ---------- 0. Sanity ----------
if ! git diff --quiet HEAD -- ':!EVOLUTION.md' ':!AppBuilder/Info.plist'; then
  echo "ERROR: working tree has uncommitted source changes."
  echo "Commit or stash them first. Only EVOLUTION.md and Info.plist may be dirty"
  echo "at the start of evolve.sh (and this script manages those itself)."
  echo
  git status --short
  exit 3
fi

# ---------- 1. Compute next version ----------
PLIST="${ROOT}/AppBuilder/Info.plist"
CUR_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST" 2>/dev/null || echo "0.0.0")"
IFS='.' read -r MAJ MIN PAT <<< "$CUR_VERSION"
MAJ="${MAJ:-0}"; MIN="${MIN:-0}"; PAT="${PAT:-0}"

case "$BUMP" in
  major) MAJ=$((MAJ+1)); MIN=0; PAT=0 ;;
  minor) MIN=$((MIN+1)); PAT=0 ;;
  patch) PAT=$((PAT+1)) ;;
esac
NEW_VERSION="${MAJ}.${MIN}.${PAT}"
echo "==> Version: ${CUR_VERSION} → ${NEW_VERSION}  (${BUMP})"

# ---------- 2. Patch Info.plist ----------
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${NEW_VERSION}" "$PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_VERSION}" "$PLIST" >/dev/null

# ---------- 3. Build ----------
echo "==> Building release"
if ! swift build -c release --product TapgoAICoding; then
  echo "BUILD FAILED — reverting Info.plist" >&2
  git checkout -- "$PLIST"
  exit 4
fi

# ---------- 4. Test ----------
echo "==> Running tests"
TEST_LOG="$(mktemp -t tapgo-evolve-tests.XXXXXX)"
if ! swift run TapgoTests 2>&1 | tee "$TEST_LOG"; then
  echo "TESTS FAILED — reverting Info.plist" >&2
  git checkout -- "$PLIST"
  rm -f "$TEST_LOG"
  exit 5
fi
TEST_LINE="$(grep -E '(passed|green|OK)' "$TEST_LOG" | tail -1 || echo "see test log")"
rm -f "$TEST_LOG"
echo "==> Tests: ${TEST_LINE}"

# ---------- 5. Append EVOLUTION.md ----------
TODAY="$(date +%Y-%m-%d)"
COMMIT_SHA="(to be filled)"
ENTRY=$(cat <<ENTRY_EOF

## v${NEW_VERSION} — ${MSG}
**Date**: ${TODAY}
**Commit**: \`${COMMIT_SHA}\`  _(set by evolve.sh post-commit)_
**Tag**: v${NEW_VERSION}
**Test status**: ${TEST_LINE}
**Changed**:
- ${MSG}
${SUMMARY}
**Why**: Self-evolution iteration — see commit message + diff.
**Next**: see \`~/Library/Application Support/Tapgo AICoding/state/evolution_state.json\`.
ENTRY_EOF
)
printf '\n%s\n' "$ENTRY" >> EVOLUTION.md

# ---------- 6. Commit + tag ----------
git add EVOLUTION.md "$PLIST"
git commit -m "${MSG} (v${NEW_VERSION})" >/dev/null
SHA="$(git rev-parse --short HEAD)"
# NOTE: The commit SHA is sourced from `git log -1 v${NEW_VERSION}`.
#       Don't try to backfill it into EVOLUTION.md — chicken/egg.

git tag -a "v${NEW_VERSION}" -m "${MSG} (v${NEW_VERSION})"

echo "==> Commit + tag created locally: ${SHA} → v${NEW_VERSION}"

# ---------- 7. Push ----------
echo "==> Pushing to origin (main + tag v${NEW_VERSION})"
if ! git push origin main --tags; then
  echo "PUSH FAILED — local commit ${SHA} and tag v${NEW_VERSION} retained." >&2
  echo "Re-run with network to retry, or:  git push origin main --tags" >&2
  exit 6
fi

# ---------- 8. Rebuild .app ----------
echo "==> Rebuilding .app bundle"
./scripts/build-app.sh >/dev/null

# ---------- 9. Write evolution_state.json ----------
STATE_DIR="${HOME}/Library/Application Support/Tapgo AICoding/state"
mkdir -p "$STATE_DIR"
STATE_FILE="${STATE_DIR}/evolution_state.json"
cat > "$STATE_FILE" <<STATE_EOF
{
  "version": "${NEW_VERSION}",
  "commitSha": "${SHA}",
  "tag": "v${NEW_VERSION}",
  "builtAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "evolutionNote": "${MSG}",
  "threadToResume": null,
  "nextActions": [
    "Read EVOLUTION.md to see the changelog up through v${NEW_VERSION}.",
    "Read this file's evolutionNote + the latest commit for the 'why'.",
    "Inspect the diff vs the previous tag: git diff v$((MAJ)).$((MIN)).$((PAT-1))..v${NEW_VERSION}",
    "Continue self-evolution: pick the next highest-value change, run ./scripts/evolve.sh ..."
  ],
  "stopConditions": [
    "Tests must be green (swift run TapgoTests) before any commit.",
    "Each iteration MUST be tagged + pushed before the next begins.",
    "Never edit ~/.codex/ — only the isolated Application Support tree.",
    "Never bump major without explicit user approval."
  ]
}
STATE_EOF
chmod 600 "$STATE_FILE"

# ---------- 10. Summary ----------
echo
echo "==================================================="
echo "  EVOLUTION COMPLETE: v${NEW_VERSION}  (${SHA})"
echo "==================================================="
echo "  Tag pushed:     v${NEW_VERSION}"
echo "  State file:     ${STATE_FILE}"
echo "  App bundle:     ${ROOT}/Tapgo AICoding.app"
echo "  Rollback:       git checkout v$((MAJ)).$((MIN)).$((PAT-1)) && ./scripts/build-app.sh"
echo "  Restart+resume: ./scripts/restart-and-resume.sh"
echo "==================================================="
