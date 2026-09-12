#!/usr/bin/env bash
# evolve.sh — One-command self-evolution cycle (hardened v0.5.257).
#
# Usage:
#   ./scripts/evolve.sh [--local|--publish] [--dry-run] [--next "..."] \
#       <version-bump> "<commit message>" "<evolution summary>"
#
#   ./scripts/evolve.sh --publish --resume [--resume-from <stage>]
#       (续跑未完成的发布；stage = verify|push|release|deploy)
#
# Modes:
#   --local    (默认) 只 commit + tag 到本地,构建并安装本机 .app。
#   --publish  维护者完整闭环: 清理树预检 → 测试 → App 构建 → commit + tag
#              → push main + tag → GitHub Release + appcast。
#   --dry-run  只打印计划,不修改任何文件。
#   --resume   读 evolution_state.json,从失败的发布阶段继续:跳过版本号/记录/
#              测试/构建/commit,直接重跑 worktree 验证、push、release、部署。
#
# Environment preflight (EVO-034): 版本号确定后立刻检查工具链/SDK/磁盘/远端/
#   gh 认证/三机 SSH/tag 冲突,失败以 12 退出且不改任何文件;EVOLVE_SKIP_PREFLIGHT=1
#   可跳过,EVOLVE_PREFLIGHT_SKIP_SSH=1 只跳过三机连通性。
# Remote lock (EVO-037): 跨机锁带 started 元数据，超过 EVOLVE_LOCK_TTL_SECONDS
#   （默认 4h）的陈旧锁会被下一次 acquire 自动回收；--break-remote-lock 走
#   reclaim（force-with-lease 覆盖），用于显式抢占仍在运行的锁。
# Runtime state schema (EVO-035): 预检后立即补齐/校验 state json/jsonl 的
#   schemaVersion,发现未来版本以 13 退出;EVOLVE_SKIP_SCHEMA_CHECK=1 可跳过。
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
# SDK 探测：TAPGO_SDK 显式指定优先，否则按 evolution-deps.sh 的偏好/回退链解析。
# shellcheck source=scripts/evolution-deps.sh
source "$ROOT/scripts/evolution-deps.sh"
if [[ -z "${TAPGO_SDK:-}" ]]; then
  TAPGO_SDK="$(evo_detect_sdk)" || {
    echo "ERROR: 无法解析 macOS SDK；用 TAPGO_SDK=macosxXX ./scripts/evolve.sh 显式指定。" >&2
    exit 7
  }
fi
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
WORKTREE_VERIFY_SCRIPT="${EVOLVE_WORKTREE_VERIFY_SCRIPT:-$ROOT/scripts/worktree-verify.sh}"
BENCHMARK_TOOL="${EVOLVE_BENCHMARK_TOOL:-$ROOT/scripts/evolution-benchmark.py}"
REMOTE_LOCK_SCRIPT="${EVOLVE_REMOTE_LOCK_SCRIPT:-$ROOT/scripts/evolution-remote-lock.sh}"
CANARY_PROMOTE_SCRIPT="${EVOLVE_CANARY_PROMOTE_SCRIPT:-$ROOT/scripts/canary-promote.sh}"
ARCHIVE_TOOL="${EVOLVE_ARCHIVE_TOOL:-$ROOT/scripts/evolution-archive.py}"
PREFLIGHT_SCRIPT="${EVOLVE_PREFLIGHT_SCRIPT:-$ROOT/scripts/evolution-preflight.sh}"
SCHEMA_TOOL="${EVOLVE_SCHEMA_TOOL:-$ROOT/scripts/evolution-schema.py}"
DEPLOY_SCRIPT="${EVOLVE_DEPLOY_SCRIPT:-$ROOT/scripts/deploy-fleet.sh}"
HEALTH_STATUS="pending"
FLEET_STATUS="skipped"

# ---------- Args ----------
MODE="local"
DRY_RUN=""
BREAK_REMOTE_LOCK=0
CANARY=0
RESUME=0
RESUME_FROM=""
RESUME_STAGE=""
PUSHED_TAG=""
TAG_COMMIT=""
CANARY_HOST="jkmacmini"
BUMP=""; MSG=""; SUMMARY=""; NEXT_ACTION=""; WHY_ACTION=""; PROTECT_APPROVAL=""
ALLOWED_PATHS=()
CHANGES=()
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --local)   MODE="local" ;;
    --publish) MODE="publish" ;;
    --dry-run) DRY_RUN="1" ;;
    --break-remote-lock) BREAK_REMOTE_LOCK=1 ;;
    --resume) RESUME=1 ;;
    --resume-from)
      [[ -n "${2:-}" ]] || { echo "ERROR: --resume-from needs a stage (verify|push|release|deploy)" >&2; exit 2; }
      RESUME=1; RESUME_FROM="$2"; shift
      ;;
    --canary) CANARY=1 ;;
    --canary-host) CANARY_HOST="${2:-jkmacmini}"; shift ;;
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
BENCHMARK_HISTORY="${EVOLVE_BENCHMARK_HISTORY:-$STATE_DIR/evolution_benchmark_history.jsonl}"
PROGRESS_FILE="${EVOLVE_PROGRESS_FILE:-$STATE_DIR/evolution_progress.json}"
STOP_FILE="${EVOLVE_STOP_FILE:-$STATE_DIR/evolution_stop_request}"
PROGRESS_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RUN_START_EPOCH="$(date +%s)"
PROGRESS_PHASE_INDEX=0
STOPPED=0
NOTES_FILE=""
NEW_VERSION=""
WORKTREE_VERIFIED=""
BENCHMARK_SCORE=""
REMOTE_LOCK_SHA=""
REMOTE_LOCK_HELD=0
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
  if [[ "$REMOTE_LOCK_HELD" -eq 1 && -n "$REMOTE_LOCK_SHA" ]]; then
    if ! "$REMOTE_LOCK_SCRIPT" release --remote "$UPSTREAM_REMOTE" --sha "$REMOTE_LOCK_SHA" >/dev/null 2>&1; then
      echo "WARN: failed to release remote evolution lock ${REMOTE_LOCK_SHA}" >&2
    fi
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

write_state() {
  local status="$1"
  local CANARY_STATE=""
  [[ "$CANARY" == "1" ]] && CANARY_STATE="$CANARY_HOST"
  # EVO-036：单轮墙钟时长 + 可选的 token/成本（由 harness/操作者通过环境变量提供）。
  local RUN_DURATION="$(( $(date +%s) - RUN_START_EPOCH ))"
  mkdir -p "$STATE_DIR"
  EVO_STATUS="$status" EVO_VERSION="$NEW_VERSION" EVO_SHA="$SHA" \
  EVO_MODE="$MODE" EVO_NOTE="$MSG" EVO_SUMMARY="$SUMMARY" \
  EVO_NEXT="$RESOLVED_NEXT" EVO_PREV="${LATEST_TAG}" EVO_BRANCH="$BRANCH" \
  EVO_ITER_BRANCH="$ITER_BRANCH" EVO_HEALTH="$HEALTH_STATUS" EVO_FLEET="$FLEET_STATUS" \
  EVO_PROTECT="$PROTECT_STATUS" EVO_WORKTREE_VERIFIED="$WORKTREE_VERIFIED" \
  EVO_BENCHMARK="$BENCHMARK_SCORE" EVO_REMOTE_LOCK="$REMOTE_LOCK_SHA" EVO_CANARY="$CANARY_STATE" \
  EVO_ROOT="$ROOT" EVO_START_HEAD="$START_HEAD" EVO_TEST_LINE="$TEST_LINE" \
  EVO_STARTED_AT="$PROGRESS_STARTED_AT" EVO_DURATION="$RUN_DURATION" \
  EVO_TOKENS="${EVOLVE_RUN_TOKENS:-}" EVO_COST="${EVOLVE_RUN_COST_USD:-}" \
  python3 - "$STATE_FILE" <<'PY'
from __future__ import annotations

import json, os, sys, datetime
path = sys.argv[1]
version = os.environ["EVO_VERSION"]
prev = os.environ.get("EVO_PREV") or "(none)"
next_action = os.environ.get("EVO_NEXT", "").strip()
mode = os.environ["EVO_MODE"]
def _optional_int(raw: str) -> int | None:
    return int(raw) if raw.strip().isdigit() else None


def _optional_float(raw: str) -> float | None:
    try:
        return float(raw)
    except (TypeError, ValueError):
        return None


state = {
    "schemaVersion": 3,
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
    "worktreeVerified": os.environ.get("EVO_WORKTREE_VERIFIED", ""),
    "benchmarkScore": int(os.environ["EVO_BENCHMARK"]) if os.environ.get("EVO_BENCHMARK", "").strip().isdigit() else None,
    "remoteLock": os.environ.get("EVO_REMOTE_LOCK") or None,
    "canary": os.environ.get("EVO_CANARY") or None,
    "repoRoot": os.environ["EVO_ROOT"],
    "startHead": os.environ["EVO_START_HEAD"],
    "testStatus": os.environ.get("EVO_TEST_LINE", ""),
    "builtAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "startedAt": os.environ.get("EVO_STARTED_AT") or None,
    "durationSeconds": _optional_int(os.environ.get("EVO_DURATION", "")),
    "tokens": _optional_int(os.environ.get("EVO_TOKENS", "")),
    "costUSD": _optional_float(os.environ.get("EVO_COST", "")),
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
        "Publish must pass a clean-checkout git worktree build before any push.",
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

publish_verify() {
  echo "==> Clean-checkout worktree verification for v${NEW_VERSION}"
  if ! "$WORKTREE_VERIFY_SCRIPT" "v${NEW_VERSION}"; then
    write_state "worktree_verify_failed"
    echo "WORKTREE VERIFY FAILED — commit/tag retained locally; nothing pushed." >&2
    exit 10
  fi
  WORKTREE_VERIFIED="yes"
  write_state "committed"
}

publish_push() {
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
}

publish_release() {
  check_stop 6 "release"
  write_progress "release" 7 "running" "building signed zip + GitHub Release"
  echo "==> Building signed zip + publishing GitHub Release + refreshing appcast"
  if ! TAPGO_REPO_SLUG="${REPO_SLUG}" TAPGO_CANARY="${CANARY}" "$RELEASE_SCRIPT" "$NOTES_FILE"; then
    write_state "release_failed"
    echo "WARN: tag pushed but release/appcast publish failed; state=release_failed." >&2
    exit 7
  fi

  write_progress "release" 7 "done" "release + appcast published"
}

publish_deploy() {
  check_stop 7 "deploy"
  write_progress "deploy" 8 "running" "deploying three-Mac fleet"
  if [[ "${EVOLVE_SKIP_DEPLOY:-}" == "1" ]]; then
    FLEET_STATUS="skipped"
    echo "==> [health] fleet deploy skipped (EVOLVE_SKIP_DEPLOY=1)"
  elif [[ "$CANARY" == "1" ]]; then
    echo "==> [canary] deploying v${NEW_VERSION} to canary host ${CANARY_HOST} only"
    if ! "$DEPLOY_SCRIPT" --only "$CANARY_HOST" "$NEW_VERSION"; then
      FLEET_STATUS="canary_failed"
      write_state "canary_failed"
      echo "CANARY FAILED: draft release retained; appcast not published." >&2
      exit 10
    fi
    echo "==> [canary] promoting appcast + deploying remaining hosts"
    if ! "$CANARY_PROMOTE_SCRIPT" "$NEW_VERSION" "$CANARY_HOST"; then
      FLEET_STATUS="canary_failed"
      write_state "canary_failed"
      echo "CANARY PROMOTE FAILED: appcast may already be public; inspect and roll back if needed." >&2
      exit 10
    fi
    FLEET_STATUS="passed"
    write_progress "deploy" 8 "done" "canary ${CANARY_HOST} promoted; fleet verified"
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
}

# publish_tail <verify|push|release|deploy> — 从指定阶段一路跑到 published。
# 正常一轮发布从 verify 开始；--resume 会按失败阶段直接进入对应阶段，
# 跳过已完成的工作（版本/记录/测试/构建/commit）。
publish_tail() {
  local stage="${1:-verify}"

  if [[ "$stage" == "verify" ]]; then
    publish_verify
    stage="push"
  else
    echo "==> [stage-skip] worktree verification already done (resume)"
  fi

  if [[ "$stage" == "push" ]]; then
    publish_push
    stage="release"
  fi

  if [[ "$stage" == "release" ]]; then
    publish_release
    stage="deploy"
  fi

  if [[ "$stage" == "deploy" ]]; then
    publish_deploy
  fi

  write_state "published"
  write_progress "done" 9 "done" "v${NEW_VERSION} published"
}

# ---------- Self-evolution resume (EVO-033) ----------
# state_field <key> — 读运行态 JSON 的单个字段；缺失/None 打印空串。
state_field() {
  python3 -c 'import json,sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
v = d.get(sys.argv[2])
print("" if v is None else v)' "$STATE_FILE" "${1:-}"
}

# record_field <record-path> <key>
record_field() {
  python3 -c 'import json,sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
v = d.get(sys.argv[2])
print("" if v is None else v)' "$1" "$2"
}

# resume_prepare — 从 evolution_state.json 续跑未完成的发布：
# 校验 tag/HEAD/记录，设置 publish 尾段所需变量，并按失败阶段决定入口。
resume_prepare() {
  [[ -f "$STATE_FILE" ]] || {
    echo "ERROR: --resume needs an existing state file: $STATE_FILE" >&2
    echo "       run a normal evolve.sh --publish first (or drop --resume)." >&2
    exit 3
  }
  local r_version r_status r_iter r_bench r_protect r_canary
  r_version="$(state_field version)"
  r_status="$(state_field status)"
  r_iter="$(state_field iterationBranch)"
  r_bench="$(state_field benchmarkScore)"
  r_protect="$(state_field protectedGate)"
  r_canary="$(state_field canary)"

  [[ -n "$r_version" ]] || { echo "ERROR: state file has no version; cannot resume." >&2; exit 3; }
  case "$r_status" in
    published)
      echo "==> NOTE: v${r_version} is already published; nothing to resume."
      exit 0 ;;
    committed|worktree_verify_failed|push_failed|release_failed|canary_failed|health_failed|local_built) ;;
    *)
      echo "ERROR: state status '${r_status}' is not a resumable publish state." >&2
      echo "       resumable: committed / worktree_verify_failed / push_failed / release_failed /" >&2
      echo "                  canary_failed / health_failed / local_built" >&2
      exit 3 ;;
  esac

  NEW_VERSION="$r_version"
  ITER_BRANCH="${r_iter:-codex/evolution-v${NEW_VERSION}}"
  local tag="v${NEW_VERSION}"
  TAG_COMMIT="$(git rev-parse "${tag}^{commit}" 2>/dev/null || true)"
  [[ -n "$TAG_COMMIT" ]] || {
    echo "ERROR: tag ${tag} not found locally; nothing to resume from." >&2
    exit 3
  }
  if [[ "$(git rev-parse HEAD)" != "$TAG_COMMIT" ]]; then
    echo "ERROR: HEAD is not at ${tag}; resume needs the tagged iteration checked out." >&2
    echo "       git checkout main && git reset --hard ${tag}   (or git checkout ${tag})" >&2
    exit 3
  fi

  local record="$ROOT/evolution/versions/v${NEW_VERSION}.json"
  [[ -f "$record" ]] || { echo "ERROR: version record missing: $record" >&2; exit 3; }

  LATEST_TAG="$(git describe --tags --abbrev=0 "${tag}^" 2>/dev/null || true)"
  SHA="$(git rev-parse --short HEAD)"
  FULL_SHA="$TAG_COMMIT"
  COMMITTED=1
  MUTATED=0
  WORKTREE_VERIFIED="$(state_field worktreeVerified)"
  BENCHMARK_SCORE="$r_bench"
  PROTECT_STATUS="$r_protect"
  TEST_LINE="$(record_field "$record" testStatus)"
  MSG="$(record_field "$record" message)"
  SUMMARY="$(record_field "$record" details)"
  RESOLVED_NEXT="$(record_field "$record" next)"
  NOTES_FILE="${ROOT}/AppBuilder/release-notes-${NEW_VERSION}.md"
  if [[ ! -f "$NOTES_FILE" ]]; then
    python3 "$RECORDS_TOOL" render-notes --version "$NEW_VERSION" > "$NOTES_FILE"
    echo "==> [resume] regenerated release notes: ${NOTES_FILE#"$ROOT"/}"
  fi

  if [[ "$CANARY" != "1" && -n "$r_canary" ]]; then
    CANARY=1
    CANARY_HOST="$r_canary"
    echo "==> [resume] inherited canary host: ${CANARY_HOST}"
  fi

  PUSHED_TAG=""
  if git ls-remote --tags "$UPSTREAM_REMOTE" "refs/tags/${tag}" 2>/dev/null | grep -q .; then
    PUSHED_TAG="yes"
  fi

  if [[ -n "$RESUME_FROM" ]]; then
    RESUME_STAGE="$RESUME_FROM"
  else
    case "$r_status" in
      health_failed|canary_failed) RESUME_STAGE="deploy" ;;
      release_failed)              RESUME_STAGE="release" ;;
      push_failed)                 RESUME_STAGE="push" ;;
      *)                           RESUME_STAGE="verify" ;;
    esac
  fi
  case "$RESUME_STAGE" in
    verify|push|release|deploy) ;;
    *) echo "ERROR: unknown resume stage '${RESUME_STAGE}' (verify|push|release|deploy)" >&2; exit 2 ;;
  esac
  if [[ -z "$PUSHED_TAG" && ( "$RESUME_STAGE" == "release" || "$RESUME_STAGE" == "deploy" ) ]]; then
    echo "==> [resume] remote tag ${tag} missing; falling back to push stage" >&2
    RESUME_STAGE="push"
  fi
  if [[ "$RESUME_STAGE" != "verify" && -z "$WORKTREE_VERIFIED" ]]; then
    echo "WARN: state has no worktreeVerified; re-running clean-checkout verification" >&2
    RESUME_STAGE="verify"
  fi

  echo "==> RESUME: v${NEW_VERSION} (state=${r_status}) → stage=${RESUME_STAGE}"
  echo "    tag:        ${tag} @ ${SHA}"
  if [[ -n "$PUSHED_TAG" ]]; then
    echo "    remote tag: pushed"
  else
    echo "    remote tag: not-pushed"
  fi
  echo "    benchmark:  ${BENCHMARK_SCORE:-n/a}"
}

# ---------- Monthly archive + final summary (shared by normal and resume runs) ----------
archive_state_history() {
  if [[ -x "$ARCHIVE_TOOL" || -f "$ARCHIVE_TOOL" ]]; then
    if ! python3 "$ARCHIVE_TOOL" archive --state-dir "$STATE_DIR" --keep-days "${EVOLVE_ARCHIVE_KEEP_DAYS:-90}" >/dev/null 2>&1; then
      echo "WARN: state history archive failed; live files left untouched." >&2
    fi
  fi
}

print_summary() {
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
}

# run_env_preflight <version|-> [--expect-existing-tag] — EVO-034 环境预检。
# 失败返回 12，不修改任何文件；EVOLVE_SKIP_PREFLIGHT=1 可跳过。
run_env_preflight() {
  local version="$1" extra="${2:-}"
  if [[ "${EVOLVE_SKIP_PREFLIGHT:-}" == "1" ]]; then
    echo "==> Environment preflight skipped (EVOLVE_SKIP_PREFLIGHT=1)"
    return 0
  fi
  local args=(--mode "$MODE" --remote "$UPSTREAM_REMOTE" --sdk "$TAPGO_SDK" --state-dir "$STATE_DIR")
  if [[ -n "$version" && "$version" != "-" ]]; then
    args+=(--next-version "$version")
  fi
  if [[ "$extra" == "--expect-existing-tag" ]]; then
    args+=(--expect-existing-tag)
  fi
  if [[ "${EVOLVE_PREFLIGHT_SKIP_SSH:-}" == "1" ]]; then
    args+=(--skip-ssh)
  fi
  echo "==> Environment preflight (${MODE})"
  if ! "$PREFLIGHT_SCRIPT" ${args[@]+"${args[@]}"}; then
    echo "ENVIRONMENT PREFLIGHT FAILED — 未修改版本号/记录，也未开始测试。" >&2
    return 12
  fi
}

# run_schema_gate — EVO-035：补齐/校验运行态 schemaVersion，版本不兼容时拒绝继续。
run_schema_gate() {
  if [[ "${EVOLVE_SKIP_SCHEMA_CHECK:-}" == "1" ]]; then
    echo "==> Runtime state schema check skipped (EVOLVE_SKIP_SCHEMA_CHECK=1)"
    return 0
  fi
  local out=""
  if ! out="$(python3 "$SCHEMA_TOOL" ensure --quiet 2>&1)"; then
    echo "$out" >&2
    echo "SCHEMA GATE FAILED — 运行态文件 schema 不兼容，未修改任何文件。" >&2
    return 13
  fi
  if [[ -n "$out" ]]; then
    echo "$out"
  fi
  echo "==> Runtime state schema: ok"
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

# ---------- Remote cross-machine lock (publish only) ----------
if [[ "$MODE" == "publish" && -z "$DRY_RUN" ]]; then
  if ! REMOTE_LOCK_SHA="$("$REMOTE_LOCK_SCRIPT" acquire --remote "$UPSTREAM_REMOTE")"; then
    if [[ "$BREAK_REMOTE_LOCK" == "1" ]]; then
      echo "==> Reclaiming remote evolution lock (explicit --break-remote-lock)" >&2
      REMOTE_LOCK_SHA="$("$REMOTE_LOCK_SCRIPT" reclaim --remote "$UPSTREAM_REMOTE")" || {
        echo "ERROR: could not reclaim remote lock after break." >&2; exit 9; }
    else
      echo "ERROR: another Mac holds the remote evolution lock." >&2
      echo "       Stale locks (older than EVOLVE_LOCK_TTL_SECONDS, default 4h) are reclaimed" >&2
      echo "       automatically; use --break-remote-lock only to force-take a live lock." >&2
      exit 9
    fi
  fi
  REMOTE_LOCK_HELD=1
  echo "==> Remote evolution lock acquired: ${REMOTE_LOCK_SHA}"
elif [[ "$MODE" == "publish" ]]; then
  echo "==> Remote evolution lock skipped (dry-run)"
fi

# ---------- Resume dispatch (continue an incomplete publish) ----------
if [[ "$RESUME" == "1" ]]; then
  if [[ "$MODE" != "publish" ]]; then
    echo "ERROR: --resume only applies to publish mode; use --publish --resume." >&2
    exit 2
  fi
  resume_prepare
  if [[ -n "$DRY_RUN" ]]; then
    echo
    echo "=== DRY RUN (resume) ==="
    echo "  version: ${NEW_VERSION}"
    echo "  stage:   ${RESUME_STAGE}"
    echo "  tag:     v${NEW_VERSION} @ ${SHA}"
    echo "  steps:   resume at ${RESUME_STAGE} → ... → published → fleet deploy"
    exit 0
  fi
  if ! run_env_preflight "$NEW_VERSION" --expect-existing-tag; then
    exit 12
  fi
  if ! run_schema_gate; then
    exit 13
  fi
  write_progress "push" 6 "running" "resume from ${RESUME_STAGE}"
  publish_tail "$RESUME_STAGE"
  archive_state_history
  print_summary
  exit 0
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

# ---------- 1b. Environment preflight (EVO-034) ----------
if ! run_env_preflight "$NEW_VERSION"; then
  exit 12
fi

# ---------- 1c. Runtime state schema gate (EVO-035) ----------
if ! run_schema_gate; then
  exit 13
fi

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

echo "==> Evolution benchmark"
BENCH_OUT="$(TAPGO_EXPECTED_VERSION="$NEW_VERSION" TAPGO_SKIP_REMOTE_INTEGRATION=1 python3 "$BENCHMARK_TOOL" run --version "$NEW_VERSION" --history "$BENCHMARK_HISTORY")"
echo "    ${BENCH_OUT}"
BENCHMARK_SCORE="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["score"])' "$BENCH_OUT" 2>/dev/null || echo "")"
if ! python3 "$BENCHMARK_TOOL" compare --history "$BENCHMARK_HISTORY"; then
  echo "BENCHMARK REGRESSED — rolling back version edits" >&2
  exit 10
fi

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

# ---------- 10. Publish (optional) ----------
if [[ "$MODE" == "publish" ]]; then
  publish_tail "verify"
else
  write_state "local_built"
  echo "==> [local] skipped push / GitHub Release / appcast"
  write_progress "done" 9 "done" "v${NEW_VERSION} local_built"
fi

# ---------- 12. Summary ----------
archive_state_history
print_summary
