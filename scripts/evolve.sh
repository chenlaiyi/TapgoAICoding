#!/usr/bin/env bash
# evolve.sh — One-command self-evolution cycle (hardened v0.5.257).
#
# Usage:
#   ./scripts/evolve.sh [--local|--publish] [--dry-run] [--next "..."] \
#       <version-bump> "<commit message>" "<evolution summary>"
#
# Modes:
#   --local    (默认) 只 commit + tag 到本地,构建并安装本机 .app。
#   --publish  维护者完整闭环: 清理树预检 → 测试 → App 构建 → commit + tag
#              → push main + tag → GitHub Release + appcast。
#   --dry-run  只打印计划,不修改任何文件。
#
# Safety contract (v0.5.257):
#   1. 工作树/索引必须干净,否则拒绝启动(避免把无关改动卷进自进化 commit)。
#   2. 仓库级 mkdir 锁,防止同机两个 evolve 进程同时改版本。
#   3. 版本号取 upstream/main 可达 tag 的语义化最高值,不再用 git describe
#      的拓扑最近值,避免旧 hotfix 或其它版本序列造成版本回退/撞号。
#   4. 测试与 .app 构建都在 commit 之前完成;失败自动恢复被改文件。
#   5. 成功后 commit 使用 `git add -A`,新文件不会被漏掉。
#   6. evolution_state.json 是分阶段状态机(committed / local_built /
#      published / push_failed / release_failed),不再只写终态。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=scripts/evolution-lib.sh
source "$ROOT/scripts/evolution-lib.sh"

# ---------- SDK selection ----------
TAPGO_SDK="${TAPGO_SDK:-macosx26.5}"
if [[ -z "${EVOLVE_SKIP_SDK_CHECK:-}" ]]; then
  if ! xcrun -sdk "$TAPGO_SDK" --show-sdk-path >/dev/null 2>&1; then
    echo "ERROR: TAPGO_SDK=$TAPGO_SDK is not installed on this machine." >&2
    exit 7
  fi
  echo "==> Using SDK: $TAPGO_SDK (override via TAPGO_SDK=...)"
fi

# Overridable entrypoints keep evolve.sh testable and allow failure injection.
TESTS_SCRIPT="${EVOLVE_TESTS_SCRIPT:-$ROOT/scripts/tests/run-all.sh}"
BUILD_SCRIPT="${EVOLVE_BUILD_SCRIPT:-$ROOT/scripts/build-app.sh}"
RELEASE_SCRIPT="${EVOLVE_RELEASE_SCRIPT:-$ROOT/scripts/create-github-release-artifacts.sh}"
RECORDS_TOOL="${EVOLVE_RECORDS_TOOL:-$ROOT/scripts/evolution-records.py}"

# ---------- Args ----------
MODE="local"
DRY_RUN=""
BUMP=""; MSG=""; SUMMARY=""; NEXT_ACTION=""; WHY_ACTION=""
ALLOWED_PATHS=()
CHANGES=()
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --local)   MODE="local" ;;
    --publish) MODE="publish" ;;
    --dry-run) DRY_RUN="1" ;;
    --next)    NEXT_ACTION="${2:-}"; shift ;;
    --why)     WHY_ACTION="${2:-}"; shift ;;
    --change)
      [[ -n "${2:-}" ]] || { echo "ERROR: --change needs a value" >&2; exit 2; }
      CHANGES+=("$2")
      shift
      ;;
    --paths)
      [[ -n "${2:-}" ]] || { echo "ERROR: --paths needs a value" >&2; exit 2; }
      IFS=',' read -r -a _paths <<< "$2"
      for _p in "${_paths[@]+"${_paths[@]}"}"; do
        [[ -n "$_p" ]] && ALLOWED_PATHS+=("$_p")
      done
      shift
      ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *)
      if   [[ -z "$BUMP"        ]]; then BUMP="$1"
      elif [[ -z "$MSG"         ]]; then MSG="$1"
      elif [[ -z "$SUMMARY"     ]]; then SUMMARY="$1"
      else echo "ERROR: unexpected extra argument: $1" >&2; exit 2
      fi
      ;;
  esac
  shift
done
BUMP="${BUMP:-patch}"
MSG="${MSG:-chore: evolve}"
SUMMARY="${SUMMARY:-_no_summary_}"
WHY_ACTION="${WHY_ACTION:-Self-evolution iteration — see commit message + diff.}"
case "$BUMP" in patch|minor|major) ;; *) echo "ERROR: bump must be patch|minor|major (got: $BUMP)" >&2; exit 2 ;; esac

# ---------- Repo identity ----------
# shellcheck source=scripts/tapgo-repo-slug.sh
source "$ROOT/scripts/tapgo-repo-slug.sh"
REPO_SLUG="$(tapgo_repo_slug || true)"
UPSTREAM_REMOTE="$(tapgo_upstream_remote)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
START_HEAD="$(git rev-parse HEAD)"

PLIST="${ROOT}/AppBuilder/Info.plist"
HELPER_PLIST="${ROOT}/AppBuilder/ComputerUseHelper-Info.plist"
PROJECT_YML="${ROOT}/AppBuilder/project.yml"
EVOLUTION="${ROOT}/EVOLUTION.md"
STATE_DIR="${EVOLVE_STATE_DIR:-$HOME/Library/Application Support/Tapgo AICoding/state}"
STATE_FILE="${STATE_DIR}/evolution_state.json"
NOTES_FILE=""
NEW_VERSION=""
COMMITTED=0
MUTATED=0

GIT_DIR_REAL="$(git rev-parse --git-dir)"
[[ "$GIT_DIR_REAL" = /* ]] || GIT_DIR_REAL="$ROOT/$GIT_DIR_REAL"
LOCK_DIR="${GIT_DIR_REAL}/tapgo-evolve.lock"

cleanup() {
  local rc=$?
  if [[ "$rc" -ne 0 && "$COMMITTED" -eq 0 && "$MUTATED" -eq 1 ]]; then
    echo "==> ROLLBACK: restoring files modified by this failed run" >&2
    git checkout -- "$PLIST" "$PROJECT_YML" "$EVOLUTION" 2>/dev/null || true
    [[ -f "$HELPER_PLIST" ]] && git checkout -- "$HELPER_PLIST" 2>/dev/null || true
    [[ -n "$NOTES_FILE" && -f "$NOTES_FILE" && "$NOTES_FILE" == */release-notes-* ]] && rm -f "$NOTES_FILE"
    if [[ -n "$NEW_VERSION" && -f "$ROOT/evolution/versions/v${NEW_VERSION}.json" ]]; then
      rm -f "$ROOT/evolution/versions/v${NEW_VERSION}.json"
    fi
    # The .app may already have been rebuilt with the failed version; rebuild
    # HEAD so the installed bundle cannot silently mismatch the repo.
    if [[ -d "${ROOT}/Tapgo AICoding.app" ]]; then
      echo "==> ROLLBACK: rebuilding .app from HEAD" >&2
      "${ROOT}/scripts/build-app.sh" >/dev/null 2>&1 || \
        echo "WARN: rollback .app rebuild failed; rerun scripts/build-app.sh manually" >&2
    fi
  fi
  evo_lock_release "$LOCK_DIR"
}
trap cleanup EXIT

# ---------- 0. Preflight: clean tree + no in-flight git operation ----------
for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
  if [[ -f "$GIT_DIR_REAL/$marker" ]]; then
    echo "ERROR: git operation in progress ($marker); finish it before evolving." >&2
    exit 9
  fi
done
if [[ -d "$GIT_DIR_REAL/rebase-merge" || -d "$GIT_DIR_REAL/rebase-apply" ]]; then
  echo "ERROR: git rebase in progress; finish it before evolving." >&2
  exit 9
fi
DIRTY_STATUS="$(git -c core.quotepath=false status --porcelain)"
if [[ -n "$DIRTY_STATUS" ]]; then
  if [[ -n "$DRY_RUN" ]]; then
    echo "==> NOTE: dry-run continues with a dirty tree (no files will be modified)"
  elif [[ "${#ALLOWED_PATHS[@]}" -eq 0 ]]; then
    echo "ERROR: dirty tree + no --paths allowlist. Pass every iteration path, e.g." >&2
    echo "       ./scripts/evolve.sh --paths Sources/TapgoCore/Foo.swift,scripts/evolve.sh ..." >&2
    git status --short | sed 's/^/    /' >&2
    exit 9
  fi
fi
if ! evo_lock_acquire "$LOCK_DIR"; then
  echo "ERROR: another evolve.sh run holds the lock ($LOCK_DIR)." >&2
  exit 9
fi
if [[ -n "$DIRTY_STATUS" ]]; then
  echo "==> Preflight: ${BRANCH}, lock acquired, dirty paths covered by allowlist"
else
  echo "==> Preflight: clean tree, branch=${BRANCH}, lock acquired"
fi

# ---------- 1. Compute next version from semantic max of reachable tags ----------
if git fetch --tags "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
  echo "==> Fetched tags from ${UPSTREAM_REMOTE}"
else
  echo "==> NOTE: fetch ${UPSTREAM_REMOTE} failed; using local merged tags" >&2
fi
MERGED_TAGS="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --merged "${UPSTREAM_REMOTE}/main" 2>/dev/null || true)"
LATEST_TAG="$(printf '%s\n' "$MERGED_TAGS" | evo_max_version)"
if [[ -z "$LATEST_TAG" ]]; then
  MERGED_TAGS="$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --merged HEAD 2>/dev/null || true)"
  LATEST_TAG="$(printf '%s\n' "$MERGED_TAGS" | evo_max_version)"
fi
FALLBACK_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST" 2>/dev/null || echo "0.0.0")"
OLD_VERSION="${LATEST_TAG#v}"
[[ -n "$OLD_VERSION" ]] || OLD_VERSION="$FALLBACK_VERSION"
NEW_VERSION="$(evo_next_version "$OLD_VERSION" "$BUMP")"
echo "==> Version: ${OLD_VERSION} → ${NEW_VERSION}  (${BUMP})"

if git rev-parse -q --verify "refs/tags/v${NEW_VERSION}" >/dev/null; then
  echo "ERROR: tag v${NEW_VERSION} already exists; refusing to reuse it." >&2
  exit 3
fi

UPSTREAM_HEAD="$(git rev-parse "${UPSTREAM_REMOTE}/main" 2>/dev/null || true)"
if [[ "$MODE" == "publish" ]]; then
  if [[ -z "$UPSTREAM_HEAD" || "$START_HEAD" != "$UPSTREAM_HEAD" ]]; then
    echo "ERROR: publish requires local HEAD == ${UPSTREAM_REMOTE}/main." >&2
    echo "       local:  ${START_HEAD}" >&2
    echo "       upstream: ${UPSTREAM_HEAD:-unknown}" >&2
    echo "       Run scripts/sync-upstream.sh --apply first." >&2
    exit 3
  fi
elif [[ -n "$UPSTREAM_HEAD" && "$START_HEAD" != "$UPSTREAM_HEAD" ]]; then
  echo "==> NOTE: local HEAD differs from ${UPSTREAM_REMOTE}/main (local mode continues)" >&2
fi

if [[ -n "$DRY_RUN" ]]; then
  echo
  echo "=== DRY RUN (no files modified) ==="
  echo "  mode:      ${MODE}"
  echo "  repo:      ${REPO_SLUG:-unresolved}"
  echo "  upstream:  ${UPSTREAM_REMOTE}"
  echo "  version:   ${NEW_VERSION}"
  echo "  commit:    ${MSG} (v${NEW_VERSION})"
  echo "  steps:     lock → prepend EVOLUTION.md → tests → build .app → notes"
  echo "             → git add <allowlist> → commit + tag"
  if [[ "$MODE" == "publish" ]]; then
    echo "             → push main + tag → GitHub Release → appcast"
  else
    echo "             → local commit/tag only"
  fi
  exit 0
fi

# ---------- 2. Patch version sources ----------
MUTATED=1
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${NEW_VERSION}" "$PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_VERSION}" "$PLIST" >/dev/null
if [[ -f "$HELPER_PLIST" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${NEW_VERSION}" "$HELPER_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_VERSION}" "$HELPER_PLIST" >/dev/null
fi
if [[ -f "$PROJECT_YML" ]] && grep -q "MARKETING_VERSION" "$PROJECT_YML"; then
  python3 - "$PROJECT_YML" "${NEW_VERSION}" <<'PY'
import re, sys
path, ver = sys.argv[1], sys.argv[2]
text = open(path).read()
text = re.sub(r'(MARKETING_VERSION:\s*")[0-9.]+"', r'\g<1>' + ver + '"', text)
text = re.sub(r'(CURRENT_PROJECT_VERSION:\s*")[0-9.]+"', r'\g<1>' + ver + '"', text)
open(path, 'w').write(text)
PY
fi

# ---------- 3. Create structured record + prepend rendered EVOLUTION.md ----------
RESOLVED_NEXT="${NEXT_ACTION:-see state file evolution_state.json}"
CHANGE_ARGS=()
for change in "${CHANGES[@]+"${CHANGES[@]}"}"; do
  CHANGE_ARGS+=(--change "$change")
done
python3 "$RECORDS_TOOL" add \
  --version "$NEW_VERSION" \
  --scope mac \
  --message "$MSG" \
  --details "$SUMMARY" \
  --why "$WHY_ACTION" \
  --next "$RESOLVED_NEXT" \
  --test-status pending \
  ${CHANGE_ARGS[@]+"${CHANGE_ARGS[@]}"} >/dev/null

ENTRY_FILE="$(mktemp -t tapgo-evolution-entry.XXXXXX)"
python3 "$RECORDS_TOOL" render-entry --version "$NEW_VERSION" > "$ENTRY_FILE"
evo_insert_evolution_entry "$EVOLUTION" "$ENTRY_FILE"
rm -f "$ENTRY_FILE"
python3 "$RECORDS_TOOL" validate --require-rendered --check-current >/dev/null
echo "==> Structured record + EVOLUTION.md rendered for v${NEW_VERSION}"

# ---------- 4. Tests (before any commit) ----------
WITH_INTEGRATION="${WITH_INTEGRATION:-}"
TEST_ENV=("TAPGO_EXPECTED_VERSION=${NEW_VERSION}")
TEST_ARGS=()
if [[ -z "$WITH_INTEGRATION" ]]; then
  TEST_ENV+=("TAPGO_SKIP_REMOTE_INTEGRATION=1")
  echo "==> Running tests (skipping SSH integration)"
else
  echo "==> Running tests (WITH SSH integration)"
fi
echo "==> Running shell + Swift regression via ${TESTS_SCRIPT}"
TEST_LOG="$(mktemp -t tapgo-evolve-tests.XXXXXX)"
if ! env "${TEST_ENV[@]}" "$TESTS_SCRIPT" 2>&1 | tee "$TEST_LOG"; then
  echo "TESTS FAILED — rolling back version edits" >&2
  rm -f "$TEST_LOG"
  exit 5
fi
TEST_LINE="$(grep -E '— [0-9]+ passed, [0-9]+ failed —' "$TEST_LOG" | tail -1 || true)"
if [[ -z "$TEST_LINE" ]]; then
  TEST_LINE="$(grep -E 'passed=[0-9]+ failed=[0-9]+' "$TEST_LOG" | tail -1 || true)"
fi
[[ -n "$TEST_LINE" ]] || TEST_LINE="see test log"
rm -f "$TEST_LOG"
echo "==> Tests: ${TEST_LINE}"

python3 "$RECORDS_TOOL" set-test-status --version "$NEW_VERSION" --value "$TEST_LINE"
python3 - "$EVOLUTION" "$TEST_LINE" <<'PYEOF'
import sys
path, status = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
old = "**Test status**: pending"
if old not in text:
    raise SystemExit("new EVOLUTION entry has no pending test-status marker")
open(path, "w", encoding="utf-8").write(text.replace(old, "**Test status**: " + status, 1))
PYEOF
python3 "$RECORDS_TOOL" validate --require-rendered --check-current >/dev/null

# ---------- 5. Build the real .app before commit ----------
echo "==> Building .app bundle"
if [[ "$MODE" == "local" ]]; then
  if ! TAPGO_LOCAL_BUILD=1 "$BUILD_SCRIPT" >/dev/null; then
    echo "BUILD FAILED — rolling back version edits" >&2
    exit 4
  fi
else
  if ! "$BUILD_SCRIPT" >/dev/null; then
    echo "BUILD FAILED — rolling back version edits" >&2
    exit 4
  fi
fi
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Tapgo AICoding.app/Contents/Info.plist" 2>/dev/null || true)"
if [[ "$BUILT_VERSION" != "$NEW_VERSION" ]]; then
  echo "BUILD FAILED — built version '${BUILT_VERSION}' != '${NEW_VERSION}'" >&2
  exit 4
fi
echo "==> Built .app version: ${BUILT_VERSION}"


# ---------- 6. Release notes (publish only; rendered from the record) ----------
if [[ "$MODE" == "publish" ]]; then
  NOTES_FILE="${ROOT}/AppBuilder/release-notes-${NEW_VERSION}.md"
  if [[ ! -f "$NOTES_FILE" ]]; then
    python3 "$RECORDS_TOOL" render-notes --version "$NEW_VERSION" > "$NOTES_FILE"
  fi
fi

# ---------- 7. Commit + tag (explicit allowlist; script-managed files auto-added) ----------
ALLOWED_PATHS+=("$PLIST" "$HELPER_PLIST" "$PROJECT_YML" "$EVOLUTION" "$ROOT/evolution")
[[ -n "$NOTES_FILE" ]] && ALLOWED_PATHS+=("$NOTES_FILE")
if [[ -n "$DIRTY_STATUS" ]]; then
  # Auto-managed files are registered as absolute paths; normalize them to
  # repo-relative form before matching git status paths.
  REL_ALLOWED_PATHS=()
  for allowed in "${ALLOWED_PATHS[@]}"; do
    case "$allowed" in
      "$ROOT"/*) REL_ALLOWED_PATHS+=("${allowed#"$ROOT"/}") ;;
      *) REL_ALLOWED_PATHS+=("$allowed") ;;
    esac
  done
  while IFS= read -r dirty_line; do
    [[ -n "$dirty_line" ]] || continue
    dirty_path="${dirty_line:3}"
    dirty_path="${dirty_path%% -> *}"
    if ! evo_path_covered "$dirty_path" "${REL_ALLOWED_PATHS[@]}"; then
      echo "ERROR: dirty path is not covered by --paths: $dirty_path" >&2
      exit 9
    fi
  done <<< "$DIRTY_STATUS"
fi
git add -A -- "${ALLOWED_PATHS[@]}"
if git diff --cached --quiet; then
  echo "ERROR: nothing staged; refusing to create an empty evolution tag." >&2
  exit 8
fi
git commit -m "${MSG} (v${NEW_VERSION})" >/dev/null
SHA="$(git rev-parse --short HEAD)"
FULL_SHA="$(git rev-parse HEAD)"
git tag -a "v${NEW_VERSION}" -m "${MSG} (v${NEW_VERSION})"
COMMITTED=1
echo "==> Commit + tag created locally: ${SHA} → v${NEW_VERSION}"

write_state() {
  local status="$1"
  mkdir -p "$STATE_DIR"
  EVO_STATUS="$status" EVO_VERSION="$NEW_VERSION" EVO_SHA="$SHA" \
  EVO_MODE="$MODE" EVO_NOTE="$MSG" EVO_SUMMARY="$SUMMARY" \
  EVO_NEXT="$NEXT_ACTION" EVO_PREV="${LATEST_TAG}" EVO_BRANCH="$BRANCH" \
  EVO_ROOT="$ROOT" EVO_START_HEAD="$START_HEAD" EVO_TEST_LINE="$TEST_LINE" \
  python3 - "$STATE_FILE" <<'PY'
import json, os, sys, datetime
path = sys.argv[1]
version = os.environ["EVO_VERSION"]
prev = os.environ.get("EVO_PREV") or "(none)"
next_action = os.environ.get("EVO_NEXT", "").strip()
mode = os.environ["EVO_MODE"]
state = {
    "schemaVersion": 2,
    "status": os.environ["EVO_STATUS"],
    "version": version,
    "commitSha": os.environ["EVO_SHA"],
    "tag": "v" + version,
    "mode": mode,
    "branch": os.environ["EVO_BRANCH"],
    "repoRoot": os.environ["EVO_ROOT"],
    "startHead": os.environ["EVO_START_HEAD"],
    "testStatus": os.environ.get("EVO_TEST_LINE", ""),
    "builtAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "evolutionNote": os.environ["EVO_NOTE"],
    "evolutionSummary": os.environ.get("EVO_SUMMARY", ""),
    "threadToResume": None,
    "nextActions": [
        next_action or "Read EVOLUTION.md and evolution_state.json, then pick the next highest-value real problem.",
        "Inspect this iteration diff: git diff %s..v%s" % (prev, version),
        "Re-run scripts/evolve.sh --dry-run before the next iteration.",
    ],
    "stopConditions": [
        "Tests and .app build must be green before any commit.",
        "A new tag is only valid after clean-tree preflight, tests, and a matching .app build.",
        "Do not start the next iteration until this state is terminal (local_built or published).",
        "Never edit ~/.codex/ — only the isolated Application Support tree.",
        "Never bump major without explicit user approval.",
    ],
}
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(state, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.chmod(tmp, 0o600)
os.replace(tmp, path)
PY

  # Append every state transition to JSONL so metrics can distinguish
  # published / failed / retried iterations instead of only seeing the last one.
  STATE_HISTORY="${EVOLVE_STATE_HISTORY:-$STATE_DIR/evolution_state_history.jsonl}"
  python3 - "$STATE_FILE" "$STATE_HISTORY" <<'PY'
import json, os, sys
state_path, history_path = sys.argv[1], sys.argv[2]
with open(state_path, encoding="utf-8") as fh:
    state = json.load(fh)
parent = os.path.dirname(history_path)
if parent:
    os.makedirs(parent, exist_ok=True)
with open(history_path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(state, ensure_ascii=False) + "\n")
    fh.flush()
    os.fsync(fh.fileno())
os.chmod(history_path, 0o600)
PY
}

# ---------- 8. Publish (optional) ----------
if [[ "$MODE" == "publish" ]]; then
  write_state "committed"
  echo "==> Pushing to ${UPSTREAM_REMOTE} (main + tag v${NEW_VERSION})"
  if ! git push "$UPSTREAM_REMOTE" HEAD:main "v${NEW_VERSION}"; then
    write_state "push_failed"
    echo "PUSH FAILED — local commit ${SHA} and tag v${NEW_VERSION} retained." >&2
    exit 6
  fi
  echo "==> Building signed zip + publishing GitHub Release + refreshing appcast"
  if ! TAPGO_REPO_SLUG="${REPO_SLUG}" "$RELEASE_SCRIPT" "$NOTES_FILE"; then
    write_state "release_failed"
    echo "WARN: tag pushed but release/appcast publish failed; state=release_failed." >&2
    exit 7
  fi
  write_state "published"
else
  write_state "local_built"
  echo "==> [local] skipped push / GitHub Release / appcast"
fi

# ---------- 9. Summary ----------
echo
echo "==================================================="
echo "  EVOLUTION COMPLETE: v${NEW_VERSION}  (${SHA})"
echo "==================================================="
echo "  Mode:           ${MODE}"
echo "  State file:     ${STATE_FILE}"
echo "  App bundle:     ${ROOT}/Tapgo AICoding.app"
if [[ -n "$LATEST_TAG" ]]; then
  echo "  Rollback:       git checkout ${LATEST_TAG} && ./scripts/build-app.sh"
else
  echo "  Rollback:       git checkout ${START_HEAD} && ./scripts/build-app.sh"
fi
echo "  Restart+resume: ./scripts/restart-and-resume.sh"
echo "==================================================="
