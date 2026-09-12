#!/usr/bin/env bash
# evolve.sh — One-command self-evolution cycle.
#
# Usage:
#   ./scripts/evolve.sh [--local|--publish] [--dry-run] <version-bump> "<commit message>" "<evolution summary>"
#
# Examples:
#   ./scripts/evolve.sh patch "fix: sidebar crash" "root cause ..."
#   ./scripts/evolve.sh --publish minor "feat: dark mode" "colors throughout chat"
#   ./scripts/evolve.sh --dry-run patch "wip" "just show me the plan"
#
# Modes (v0.5.255):
#   --local    (默认) 任何人可用。版本对齐上游后,只 commit + tag 到**本地**,
#              build .app。不 push、不发 Release、不动 appcast。
#              适合「我只想给自己定制」的副本。
#   --publish  仅维护者。保留完整闭环:push origin main + tag、
#              GitHub Release、刷新 appcast(客户端据此自动更新)。
#              需要对该仓库有写权限 + Sparkle 私钥在 keychain。
#   --dry-run  只打印将要发生的事(版本号/模式/步骤),不修改任何文件。
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
#   4. swift build -c release --product TapgoAICoding  (must succeed; uses
#      SDK 26.5 via xcrun — see scripts/build-app.sh for the rationale)
#   5. swift run TapgoTests                         (must stay green)
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

# ---------- SDK selection ----------
# Match scripts/build-app.sh: pin to SDK 26.5 because macOS 27 SDK
# dropped the SwiftUI macros plugin from CommandLineTools. Override
# with TAPGO_SDK=macosx27.0 to opt back in.
TAPGO_SDK="${TAPGO_SDK:-macosx26.5}"
if ! xcrun -sdk "$TAPGO_SDK" --show-sdk-path >/dev/null 2>&1; then
  echo "ERROR: TAPGO_SDK=$TAPGO_SDK is not installed on this machine." >&2
  echo "  Installed SDKs:" >&2
  ls -1 /Library/Developer/CommandLineTools/SDKs/ 2>/dev/null | sed "s/^/    /" >&2
  exit 7
fi
SWIFT=(xcrun -sdk "$TAPGO_SDK" swift)
echo "==> Using SDK: $TAPGO_SDK (override via TAPGO_SDK=...)"

# ---------- Args ----------
# v0.5.255: 位置参数之前允许 --local / --publish / --dry-run。
# 默认 --local(安全默认):别的用户 clone 下来演进不会误推上游。
MODE="local"
DRY_RUN=""
BUMP=""; MSG=""; SUMMARY=""
for arg in "$@"; do
  case "$arg" in
    --local)   MODE="local" ;;
    --publish) MODE="publish" ;;
    --dry-run) DRY_RUN="1" ;;
    -h|--help) sed -n '2,52p' "$0"; exit 0 ;;
    *)
      if   [[ -z "$BUMP"    ]]; then BUMP="$arg"
      elif [[ -z "$MSG"     ]]; then MSG="$arg"
      elif [[ -z "$SUMMARY" ]]; then SUMMARY="$arg"
      fi
      ;;
  esac
done
BUMP="${BUMP:-patch}"
MSG="${MSG:-chore: evolve}"
SUMMARY="${SUMMARY:-_no_summary_}"

case "$BUMP" in
  patch|minor|major) ;;
  *) echo "ERROR: bump must be patch|minor|major (got: $BUMP)" >&2; exit 2 ;;
esac

# ---------- 仓库归属(共享解析) ----------
# shellcheck source=scripts/tapgo-repo-slug.sh
source "$ROOT/scripts/tapgo-repo-slug.sh"
REPO_SLUG="$(tapgo_repo_slug || true)"
UPSTREAM_REMOTE="$(tapgo_upstream_remote)"

# ---------- 0. Sanity ----------
# Soft sanity check: warn if there are uncommitted changes, but don't
# block. A typical iteration edits README.md + sources together; the
# pipeline commits them atomically. The user can always `git reset
# HEAD~1` if they don't like what got committed.
if ! git diff --quiet HEAD; then
  echo "==> NOTE: working tree has uncommitted changes — will be included in this commit."
  git status --short | sed 's/^/    /'
fi

# ---------- 1. Compute next version ----------
PLIST="${ROOT}/AppBuilder/Info.plist"
HELPER_PLIST="${ROOT}/AppBuilder/ComputerUseHelper-Info.plist"
# Source the version from the LATEST git tag (if any), falling back to
# Info.plist. This way manually-tagged baselines (e.g. v0.3.1 introduced
# before evolve.sh existed) don't get re-used by the script.
# v0.5.255: 先感知上游 tag 再算版本,避免多人并行演进撞号。
# fetch 失败(离线/fork 无 upstream)不阻断,降级为本地 tag。
if git fetch --tags "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
  echo "==> Fetched tags from ${UPSTREAM_REMOTE}"
else
  echo "==> NOTE: fetch ${UPSTREAM_REMOTE} 失败,版本基准退回本地 tag" >&2
fi
LATEST_TAG="$(git describe --tags --abbrev=0 "${UPSTREAM_REMOTE}/main" 2>/dev/null \
  || git describe --tags --abbrev=0 2>/dev/null || true)"
if [[ "$LATEST_TAG" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  MAJ="${BASH_REMATCH[1]}"
  MIN="${BASH_REMATCH[2]}"
  PAT="${BASH_REMATCH[3]}"
else
  CUR_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST" 2>/dev/null || echo "0.0.0")"
  IFS='.' read -r MAJ MIN PAT <<< "$CUR_VERSION"
  MAJ="${MAJ:-0}"; MIN="${MIN:-0}"; PAT="${PAT:-0}"
fi

OLD_VERSION="${MAJ}.${MIN}.${PAT}"
case "$BUMP" in
  major) MAJ=$((MAJ+1)); MIN=0; PAT=0 ;;
  minor) MIN=$((MIN+1)); PAT=0 ;;
  patch) PAT=$((PAT+1)) ;;
esac
NEW_VERSION="${MAJ}.${MIN}.${PAT}"
echo "==> Version: ${OLD_VERSION} → ${NEW_VERSION}  (${BUMP})"

if [[ -n "$DRY_RUN" ]]; then
  echo
  echo "=== DRY RUN(不修改任何文件)==="
  echo "  模式:      ${MODE}$( [[ "$MODE" == "local" ]] && echo '  (本地演进,不 push / 不发布)' || echo '  (维护者发布,含 push + Release + appcast)' )"
  echo "  仓库:      ${REPO_SLUG:-未解析到}"
  echo "  上游远端:  ${UPSTREAM_REMOTE}"
  echo "  版本:      ${NEW_VERSION}"
  echo "  commit:    ${MSG} (v${NEW_VERSION})"
  echo "  将执行:    改版本号 → release build → 全量测试 → 追加 EVOLUTION.md → commit → tag"
  if [[ "$MODE" == "publish" ]]; then
    echo "             → push ${UPSTREAM_REMOTE} main + tag → GitHub Release → 刷新 appcast"
  else
    echo "             → 仅本地 commit + tag,再重建并安装 .app"
  fi
  exit 0
fi

# ---------- 2. Patch Info.plist ----------
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${NEW_VERSION}" "$PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_VERSION}" "$PLIST" >/dev/null
if [[ -f "$HELPER_PLIST" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${NEW_VERSION}" "$HELPER_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_VERSION}" "$HELPER_PLIST" >/dev/null
fi

# Sync AppBuilder/project.yml so a future 'xcodegen' run picks up the new
# MARKETING_VERSION / CURRENT_PROJECT_VERSION instead of a stale hardcode.
PROJECT_YML="${ROOT}/AppBuilder/project.yml"
if [[ -f "$PROJECT_YML" ]] && grep -q "MARKETING_VERSION" "$PROJECT_YML"; then
  # Sync version so a future xcodegen run doesn't ship a stale spec.
  python3 - "$PROJECT_YML" "${NEW_VERSION}" <<'PY'
import re, sys
path, ver = sys.argv[1], sys.argv[2]
text = open(path).read()
text = re.sub(r'(MARKETING_VERSION:\s*")[0-9.]+"', r'\g<1>' + ver + '"', text)
text = re.sub(r'(CURRENT_PROJECT_VERSION:\s*")[0-9.]+"', r'\g<1>' + ver + '"', text)
open(path, 'w').write(text)
PY
fi

# ---------- 3. Build ----------
echo "==> Building release"
if ! "${SWIFT[@]}" build -c release --product TapgoAICoding; then
  echo "BUILD FAILED — reverting Info.plist" >&2
  git checkout -- "$PLIST" "$HELPER_PLIST"
  exit 4
fi

# ---------- 4. Test ----------
# By default we SKIP SSH-integration tests (they require a real remote
# codex host at 203.0.113.10 which is RFC 5737 TEST-NET-3). Pass
# --with-integration to include them.
WITH_INTEGRATION="${WITH_INTEGRATION:-}"
TEST_ENV=()
TEST_ARGS=()
if [[ -z "$WITH_INTEGRATION" ]]; then
  TEST_ENV+=("TAPGO_SKIP_REMOTE_INTEGRATION=1")
  echo "==> Running tests (skipping SSH-integration: TAPGO_SKIP_REMOTE_INTEGRATION=1)"
else
  echo "==> Running tests (WITH integration — needs real SSH host at 203.0.113.10)"
fi
# Info.plist 已经是即将发布的 ${NEW_VERSION}，但 git tag 还没打——
# 让 AppUpdateDistributionTests 用我们预期的版本号而不是回退去匹配
# 上一版 tag，避免假阳性 fail。
TEST_ENV+=("TAPGO_EXPECTED_VERSION=${NEW_VERSION}")
TEST_LOG="$(mktemp -t tapgo-evolve-tests.XXXXXX)"
if ! env "${TEST_ENV[@]}" swift run TapgoTests ${TEST_ARGS[@]+"${TEST_ARGS[@]}"} 2>&1 | tee "$TEST_LOG"; then
  echo "TESTS FAILED — reverting Info.plist" >&2
  git checkout -- "$PLIST" "$HELPER_PLIST"
  rm -f "$TEST_LOG"
  exit 5
fi
# Summary line: prefer the final "— N passed, M failed —" line; fall
# back to the last "passed=" counter if present.
TEST_LINE="$(grep -E '— [0-9]+ passed, [0-9]+ failed —' "$TEST_LOG" | tail -1 || echo "see test log")"
if [[ -z "$TEST_LINE" ]]; then
  TEST_LINE="$(grep -E 'passed=[0-9]+ failed=[0-9]+' "$TEST_LOG" | tail -1 || echo "see test log")"
fi
rm -f "$TEST_LOG"
echo "==> Tests: ${TEST_LINE}"

# ---------- 5. Append EVOLUTION.md ----------
TODAY="$(date +%Y-%m-%d)"
ENTRY=$(cat <<ENTRY_EOF

## v${NEW_VERSION} — ${MSG}
**Date**: ${TODAY}
**Commit**: _(see \`git log -1 v${NEW_VERSION}\`)_
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
# Stage all tracked-file modifications (README, scripts, sources…) PLUS
# the script-managed EVOLUTION.md + Info.plist. -u won't pick up new
# untracked files, so the user has to explicitly git add those if they
# want them in this commit.
git add -u
git add EVOLUTION.md "$PLIST" "$HELPER_PLIST"
git commit -m "${MSG} (v${NEW_VERSION})" >/dev/null
SHA="$(git rev-parse --short HEAD)"
# NOTE: The commit SHA is sourced from `git log -1 v${NEW_VERSION}`.
#       Don't try to backfill it into EVOLUTION.md — chicken/egg.

git tag -a "v${NEW_VERSION}" -m "${MSG} (v${NEW_VERSION})"

echo "==> Commit + tag created locally: ${SHA} → v${NEW_VERSION}"

# ---------- 7. Push + 发布(仅 --publish) ----------
# v0.5.255: 默认 --local 只做本地 commit + tag。别的用户 clone 后演进
# 不应该(也没有权限)推上游、发 Release、改 appcast。
if [[ "$MODE" == "publish" ]]; then
  echo "==> Pushing to ${UPSTREAM_REMOTE} (main + tag v${NEW_VERSION})"
  # Push main + ONLY the new tag (avoid duplicates like a local v0.5.82 pointing
  # to a different commit than origin/v0.5.82 -- --tags rejects those).
  if ! git push "$UPSTREAM_REMOTE" HEAD:main "v${NEW_VERSION}"; then
    echo "PUSH FAILED — local commit ${SHA} and tag v${NEW_VERSION} retained." >&2
    echo "Re-run with network to retry, or:  git push ${UPSTREAM_REMOTE} HEAD:main v${NEW_VERSION}" >&2
    exit 6
  fi

  echo "==> Building signed zip + publishing GitHub Release + refreshing appcast"
  if ! TAPGO_REPO_SLUG="${REPO_SLUG}" ./scripts/create-github-release-artifacts.sh; then
    echo "WARN: create-github-release-artifacts.sh failed; release not published." >&2
    echo "      Re-run later: ./scripts/create-github-release-artifacts.sh" >&2
    echo "      Tag v${NEW_VERSION} is already pushed; clients cannot fetch the zip until release is created." >&2
  fi
else
  echo "==> [local 模式] 跳过 push / GitHub Release / appcast"
  echo "    本地 commit ${SHA} + tag v${NEW_VERSION} 已创建;App 仍会重建。"
  echo "    若要让这个副本跟随自己的更新源,见 README「自进化」章节。"
fi

# ---------- 8. Rebuild .app ----------
echo "==> Rebuilding .app bundle"
if [[ "$MODE" == "local" ]]; then
  # 本地定制:关闭自动安装更新,避免用户的自定义被上游版本静默覆盖。
  TAPGO_LOCAL_BUILD=1 ./scripts/build-app.sh >/dev/null
  echo "    [local] .app 已重建(自动安装更新已关闭)"
else
  ./scripts/build-app.sh >/dev/null
  echo "    [publish] .app 已重建(跟随上游 feed)"
fi

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
if [[ "$MODE" == "publish" ]]; then
  echo "  Tag pushed:     v${NEW_VERSION}"
else
  echo "  Tag (local):    v${NEW_VERSION}   ← 未推送(publish 模式才推)"
fi
echo "  State file:     ${STATE_FILE}"
echo "  App bundle:     ${ROOT}/Tapgo AICoding.app"
echo "  Rollback:       git checkout v$((MAJ)).$((MIN)).$((PAT-1)) && ./scripts/build-app.sh"
echo "  Restart+resume: ./scripts/restart-and-resume.sh"
echo "==================================================="
