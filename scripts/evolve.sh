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
BACKLOG_TOOL="${EVOLVE_BACKLOG_TOOL:-$ROOT/scripts/evolution-backlog.py}"
HEALTH_SCRIPT="${EVOLVE_HEALTH_SCRIPT:-$ROOT/scripts/health-check.sh}"
TEST_REPORT_TOOL="${EVOLVE_TEST_REPORT_TOOL:-$ROOT/scripts/test-failure-report.py}"
PROTECT_TOOL="${EVOLVE_PROTECT_TOOL:-$ROOT/scripts/evolution-protect.py}"
DEPLOY_SCRIPT="${EVOLVE_DEPLOY_SCRIPT:-$ROOT/scripts/deploy-fleet.sh}"
HEALTH_STATUS="pending"
FLEET_STATUS="skipped"

# ---------- Args ----------
MODE="local"
DRY_RUN=""
BUMP=""; MSG=""; SUMMARY=""; NEXT_ACTION=""; WHY_ACTION=""; PROTECT_APPROVAL=""
ALLOWED_PATHS=()
CHANGES=()
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --local)   MODE="local" ;;
    --publish) MODE="publish" ;;
    --dry-run) DRY_RUN="1" ;;
    --next)    NEXT_ACTION="${2:-}"; shift ;;
    --why)     WHY_ACTION="${2:-}"; shift ;;
    --approve-protected)
      [[ -n "${2:-}" ]] || { echo "ERROR: --approve-protected needs a token" >&2; exit 2; }
      PROTECT_APPROVAL="$2"; shift
      ;;
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
TEST_HISTORY="${EVOLVE_TEST_HISTORY:-$STATE_DIR/test_run_history.jsonl}"
PROGRESS_FILE="${EVOLVE_PROGRESS_FILE:-$STATE_DIR/evolution_progress.json}"
STOP_FILE="${EVOLVE_STOP_FILE:-$STATE_DIR/evolution_stop_request}"
PROGRESS_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PROGRESS_PHASE_INDEX=0
STOPPED=0
NOTES_FILE=""
NEW_VERSION=""
ITER_BRANCH=""
BRANCH_CREATED=0
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
  if [[ "$rc" -ne 0 && "$STOPPED" -eq 0 ]]; then
    write_progress "failed" "${PROGRESS_PHASE_INDEX:-1}" "failed" "exit=${rc}"
  fi
  if [[ "$rc" -ne 0 && "$COMMITTED" -eq 0 && "$BRANCH_CREATED" -eq 1 ]]; then
    if [[ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)" == "$ITER_BRANCH" ]]; then
      git checkout "$BRANCH" >/dev/null 2>&1 || true
    fi
    git branch -D "$ITER_BRANCH" >/dev/null 2>&1 || true
  fi
  evo_lock_release "$LOCK_DIR"
}
trap cleanup EXIT

write_progress() {
  local phase="$1" index="$2" status="${3:-running}" message="${4:-}"
  PROGRESS_PHASE_INDEX="$index"
  if [[ "${EVOLVE_SKIP_PROGRESS:-}" == "1" ]]; then return 0; fi
  mkdir -p "$STATE_DIR"
  EVO_P_VERSION="${NEW_VERSION:-pending}" EVO_P_PHASE="$phase" EVO_P_INDEX="$index" \
  EVO_P_STATUS="$status" EVO_P_MESSAGE="$message" EVO_P_BRANCH="${ITER_BRANCH:-}" \
  EVO_P_STARTED="$PROGRESS_STARTED_AT" python3 - "$PROGRESS_FILE" <<'PY'
import datetime, json, os, sys
path = sys.argv[1]
state = {
    "schemaVersion": 1,
    "version": os.environ.get("EVO_P_VERSION", ""),
    "phase": os.environ["EVO_P_PHASE"],
    "phaseIndex": int(os.environ["EVO_P_INDEX"]),
    "phaseCount": 9,
    "status": os.environ["EVO_P_STATUS"],
    "message": os.environ.get("EVO_P_MESSAGE", ""),
    "iterationBranch": os.environ.get("EVO_P_BRANCH", ""),
    "startedAt": os.environ.get("EVO_P_STARTED", ""),
    "updatedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(state, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
os.replace(tmp, path)
PY
}

check_stop() {
  local index="$1" phase="$2"
  if [[ -f "$STOP_FILE" ]]; then
    rm -f "$STOP_FILE"
    STOPPED=1
    write_progress "stopped" "$index" "stopped" "用户请求停止（${phase}）"
    echo "STOP REQUESTED before ${phase}; aborting self-evolution." >&2
    exit 9
  fi
}

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
if [[ "$BRANCH" == "HEAD" ]]; then
  echo "ERROR: detached HEAD is not supported for self-evolution; checkout a branch first." >&2
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
write_progress "preflight" 1 "running" "branch=${BRANCH}"

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

# ---------- Protected-path gate ----------
PROTECT_STATUS="clean"
if [[ -n "$LATEST_TAG" ]]; then
  PROTECT_JSON="$(python3 "$PROTECT_TOOL" status --base "$LATEST_TAG" 2>/dev/null || echo '{}')"
  PROTECT_CHANGED="$(python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("changed", [])))' <<< "$PROTECT_JSON" 2>/dev/null || echo 0)"
  PROTECT_TOKEN="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("token", ""))' <<< "$PROTECT_JSON" 2>/dev/null || true)"
  if [[ "$PROTECT_CHANGED" != "0" ]]; then
    if [[ -n "$PROTECT_APPROVAL" ]] && python3 "$PROTECT_TOOL" check --base "$LATEST_TAG" --approve "$PROTECT_APPROVAL" >/dev/null 2>&1; then
      PROTECT_STATUS="approved:${PROTECT_APPROVAL}"
      echo "==> Protected paths approved (${PROTECT_CHANGED} file(s), token=${PROTECT_APPROVAL})"
    elif [[ -n "$DRY_RUN" ]]; then
      PROTECT_STATUS="blocked:${PROTECT_TOKEN}"
      echo "==> NOTE: dry-run — protected paths changed; real run needs --approve-protected ${PROTECT_TOKEN}" >&2
    else
      echo "==> Protected path changes require explicit approval:" >&2
      python3 "$PROTECT_TOOL" check --base "$LATEST_TAG" --approve "" >&2 || true
      exit 9
    fi
  fi
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
  echo "  branch:    codex/evolution-v${NEW_VERSION} (${BRANCH} only fast-forward)"
  echo "  protect:   ${PROTECT_STATUS}"
  echo "  steps:     lock → prepend EVOLUTION.md → tests → build .app → notes"
  echo "             → git add <allowlist> → commit + tag"
  if [[ "$MODE" == "publish" ]]; then
    echo "             → push main + tag → GitHub Release → appcast"
  else
    echo "             → local commit/tag only"
  fi
  exit 0
fi

# ---------- 2. Create the iteration branch (main only ever fast-forwards) ----------
ITER_BRANCH="codex/evolution-v${NEW_VERSION}"
if git show-ref --verify --quiet "refs/heads/$ITER_BRANCH"; then
  echo "ERROR: iteration branch already exists: $ITER_BRANCH" >&2
  exit 3
fi
git checkout -b "$ITER_BRANCH" >/dev/null
BRANCH_CREATED=1
echo "==> Iteration branch: ${ITER_BRANCH} (from ${BRANCH}@${START_HEAD:0:8})"

# ---------- 3. Patch version sources ----------
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
RESOLVED_NEXT="${NEXT_ACTION:-$(python3 "$BACKLOG_TOOL" top 2>/dev/null || true)}"
RESOLVED_NEXT="${RESOLVED_NEXT:-see state file evolution_state.json}"
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
write_progress "record" 2 "done" "record + EVOLUTION rendered"

# ---------- 5. Tests (before any commit) ----------
check_stop 2 "tests"
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
  echo "TESTS FAILED — collecting failure evidence" >&2
  PARSED="$(python3 "$TEST_REPORT_TOOL" parse --log "$TEST_LOG" 2>/dev/null || echo '{}')"
  RERUN_ARGS=()
  if [[ "${EVOLVE_SKIP_RERUN:-}" != "1" && -n "$PARSED" ]]; then
    while IFS= read -r section; do
      [[ -n "$section" ]] || continue
      if env "${TEST_ENV[@]}" "$TESTS_SCRIPT" --filter "$section" >/dev/null 2>&1; then
        RERUN_ARGS+=("$section" "1")
      else
        RERUN_ARGS+=("$section" "0")
      fi
    done < <(python3 -c 'import json,sys; d=json.load(sys.stdin); print("\n".join(s["section"] for s in d.get("failedSections", [])[:3]))' <<< "$PARSED" 2>/dev/null || true)
  fi
  RERUN_JSON="$(python3 - "${RERUN_ARGS[@]+"${RERUN_ARGS[@]}"}" <<'PY'
import json, sys
args = sys.argv[1:]
print(json.dumps([{"section": args[i], "passed": args[i + 1] == "1"} for i in range(0, len(args), 2)], ensure_ascii=False))
PY
)"
  python3 "$TEST_REPORT_TOOL" record --log "$TEST_LOG" --history "$TEST_HISTORY" \
    --version "$NEW_VERSION" --status fail --reruns "$RERUN_JSON" >/dev/null 2>&1 || true
  FLAKY_SUMMARY="$(python3 "$TEST_REPORT_TOOL" flaky --history "$TEST_HISTORY" 2>/dev/null || true)"
  echo "==> Failure evidence: ${FLAKY_SUMMARY//$'\n'/ }" >&2
  rm -f "$TEST_LOG"
  echo "TESTS FAILED — rolling back version edits" >&2
  exit 5
fi
TEST_LINE="$(grep -E '— [0-9]+ passed, [0-9]+ failed —' "$TEST_LOG" | tail -1 || true)"
if [[ -z "$TEST_LINE" ]]; then
  TEST_LINE="$(grep -E 'passed=[0-9]+ failed=[0-9]+' "$TEST_LOG" | tail -1 || true)"
fi
[[ -n "$TEST_LINE" ]] || TEST_LINE="see test log"
python3 "$TEST_REPORT_TOOL" record --log "$TEST_LOG" --history "$TEST_HISTORY" \
  --version "$NEW_VERSION" --status pass >/dev/null 2>&1 || true
rm -f "$TEST_LOG"
echo "==> Tests: ${TEST_LINE}"
write_progress "tests" 3 "done" "${TEST_LINE}"

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

# ---------- 6. Build the real .app before commit ----------
check_stop 3 "build"
write_progress "build" 4 "running" "building .app"
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
echo "==> Bundle health check"
if ! "$HEALTH_SCRIPT" "$ROOT/Tapgo AICoding.app" "$NEW_VERSION"; then
  echo "HEALTH CHECK FAILED — rolling back version edits" >&2
  exit 4
fi
HEALTH_STATUS="passed"
write_progress "build" 4 "done" "health check passed"


# ---------- 7. Release notes (publish only; rendered from the record) ----------
if [[ "$MODE" == "publish" ]]; then
  NOTES_FILE="${ROOT}/AppBuilder/release-notes-${NEW_VERSION}.md"
  if [[ ! -f "$NOTES_FILE" ]]; then
    python3 "$RECORDS_TOOL" render-notes --version "$NEW_VERSION" > "$NOTES_FILE"
  fi
fi

# ---------- 8. Commit + tag on the iteration branch ----------
check_stop 4 "commit"
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
echo "==> Commit + tag created on ${ITER_BRANCH}: ${SHA} → v${NEW_VERSION}"

if [[ "$(git rev-parse --abbrev-ref HEAD)" == "$ITER_BRANCH" ]]; then
  if [[ "$(git rev-parse "$BRANCH")" != "$START_HEAD" ]]; then
    echo "ERROR: ${BRANCH} moved during the iteration; refusing non-fast-forward merge." >&2
    echo "       iteration commit/tag retained on ${ITER_BRANCH}." >&2
    exit 8
  fi
  git checkout "$BRANCH" >/dev/null
  if ! git merge --ff-only "$ITER_BRANCH" >/dev/null; then
    echo "ERROR: failed to fast-forward ${BRANCH} to ${ITER_BRANCH}; branch retained." >&2
    exit 8
  fi
  echo "==> ${BRANCH} fast-forwarded to ${SHA}; iteration branch retained"
fi
write_progress "commit" 5 "done" "tag v${NEW_VERSION} @ ${SHA}"

write_state() {
  local status="$1"
  mkdir -p "$STATE_DIR"
  EVO_STATUS="$status" EVO_VERSION="$NEW_VERSION" EVO_SHA="$SHA" \
  EVO_MODE="$MODE" EVO_NOTE="$MSG" EVO_SUMMARY="$SUMMARY" \
  EVO_NEXT="$RESOLVED_NEXT" EVO_PREV="${LATEST_TAG}" EVO_BRANCH="$BRANCH" \
  EVO_ITER_BRANCH="$ITER_BRANCH" EVO_HEALTH="$HEALTH_STATUS" EVO_FLEET="$FLEET_STATUS" \
  EVO_PROTECT="$PROTECT_STATUS" \
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
    "originalBranch": os.environ["EVO_BRANCH"],
    "iterationBranch": os.environ.get("EVO_ITER_BRANCH", ""),
    "healthCheck": os.environ.get("EVO_HEALTH", ""),
    "fleetDeploy": os.environ.get("EVO_FLEET", ""),
    "protectedGate": os.environ.get("EVO_PROTECT", ""),
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
        "Iteration commits live on codex/evolution-vX.Y.Z; the original branch only fast-forwards.",
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

# ---------- 10. Publish (optional) ----------
if [[ "$MODE" == "publish" ]]; then
  write_state "committed"
  check_stop 5 "push"
  write_progress "push" 6 "running" "pushing main + audit branch"
  echo "==> Pushing iteration branch ${ITER_BRANCH} for audit"
  if ! git push "$UPSTREAM_REMOTE" "$ITER_BRANCH"; then
    write_state "push_failed"
    echo "PUSH FAILED (branch) — local commit ${SHA} and tag v${NEW_VERSION} retained." >&2
    exit 6
  fi
  echo "==> Pushing to ${UPSTREAM_REMOTE} (main fast-forward + tag v${NEW_VERSION})"
  if ! git push "$UPSTREAM_REMOTE" HEAD:main "v${NEW_VERSION}"; then
    write_state "push_failed"
    echo "PUSH FAILED (main) — local commit ${SHA} and tag v${NEW_VERSION} retained." >&2
    exit 6
  fi
  write_progress "push" 6 "done" "main + audit branch pushed"
  check_stop 6 "release"
  write_progress "release" 7 "running" "building signed zip + GitHub Release"
  echo "==> Building signed zip + publishing GitHub Release + refreshing appcast"
  if ! TAPGO_REPO_SLUG="${REPO_SLUG}" "$RELEASE_SCRIPT" "$NOTES_FILE"; then
    write_state "release_failed"
    echo "WARN: tag pushed but release/appcast publish failed; state=release_failed." >&2
    exit 7
  fi

  write_progress "release" 7 "done" "release + appcast published"
  check_stop 7 "deploy"
  write_progress "deploy" 8 "running" "deploying three-Mac fleet"
  if [[ "${EVOLVE_SKIP_DEPLOY:-}" == "1" ]]; then
    FLEET_STATUS="skipped"
    echo "==> [health] fleet deploy skipped (EVOLVE_SKIP_DEPLOY=1)"
  else
    echo "==> [health] deploying v${NEW_VERSION} to the three-Mac fleet"
    if ! "$DEPLOY_SCRIPT" "$NEW_VERSION"; then
      FLEET_STATUS="failed"
      write_state "health_failed"
      echo "HEALTH FAILED: release is published but fleet deploy/readback failed." >&2
      echo "Rollback: git checkout ${LATEST_TAG:-${START_HEAD}} && ./scripts/build-app.sh" >&2
      exit 10
    fi
    FLEET_STATUS="passed"
    write_progress "deploy" 8 "done" "fleet version/PID verified"
  fi
  write_state "published"
  write_progress "done" 9 "done" "v${NEW_VERSION} published"
else
  write_state "local_built"
  echo "==> [local] skipped push / GitHub Release / appcast"
  write_progress "done" 9 "done" "v${NEW_VERSION} local_built"
fi

# ---------- 11. Summary ----------
echo
echo "==================================================="
echo "  EVOLUTION COMPLETE: v${NEW_VERSION}  (${SHA})"
echo "==================================================="
echo "  Mode:           ${MODE}"
echo "  Iteration:      ${ITER_BRANCH}"
echo "  State file:     ${STATE_FILE}"
echo "  App bundle:     ${ROOT}/Tapgo AICoding.app"
if [[ -n "$LATEST_TAG" ]]; then
  echo "  Rollback:       git checkout ${LATEST_TAG} && ./scripts/build-app.sh"
else
  echo "  Rollback:       git checkout ${START_HEAD} && ./scripts/build-app.sh"
fi
echo "  Restart+resume: ./scripts/restart-and-resume.sh"
echo "==================================================="
