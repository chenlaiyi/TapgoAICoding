#!/usr/bin/env bash
# evolution-preflight.sh — 发布前环境预检（EVO-034）。
#
# 在动版本号 / 跑测试 / 构建之前，把外部依赖一次性检查完；任一项失败即
# 列出原因并以 12 退出，避免跑到中段才失败回滚。
#
# 检查项：
#   工具链   git / python3(>=3.9) / xcrun + swift SDK
#   磁盘     仓库所在卷可用空间 >= --min-free-gb（默认 5G）
#   仓库     关键脚本与清单齐全
#   远端     origin 可达（发布）；本地 HEAD == origin/main（发布）
#   认证     gh auth status（发布，Release 必需）
#   三机     jkmacmini / chenlaiyi-mbp SSH 可登录（发布，可 --skip-ssh）
#   tag      下一个版本 tag 未被占用；--expect-existing-tag 时要求已存在（续跑）
#   运行态   state 目录可写、受保护清单可解析
#
# 用法：
#   ./scripts/evolution-preflight.sh                       # 本地模式
#   ./scripts/evolution-preflight.sh --mode publish
#   ./scripts/evolution-preflight.sh --mode publish --json
#   ./scripts/evolution-preflight.sh --next-version 0.5.290 --expect-existing-tag
#
# 测试覆盖入口（EVOLVE_PREFLIGHT_*）：
#   ROOT / GIT / PYTHON / GH / XCRUN / SSH / DF 以及 EVOLVE_PREFLIGHT_MIN_FREE_GB
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${EVOLVE_PREFLIGHT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
cd "$ROOT"
# 工具函数与三机清单始终取自脚本自身所在仓库（EVOLVE_PREFLIGHT_ROOT 只影响
# 被检查的仓库内容，测试里可以把 ROOT 指向 fixture）。
# shellcheck source=scripts/evolution-lib.sh
source "$SCRIPT_DIR/evolution-lib.sh"
# shellcheck source=scripts/fleet-hosts.sh
source "$SCRIPT_DIR/fleet-hosts.sh"
# shellcheck source=scripts/tapgo-repo-slug.sh
source "$SCRIPT_DIR/tapgo-repo-slug.sh"

MODE="local"
REMOTE=""
source "$SCRIPT_DIR/evolution-deps.sh"
SDK="${TAPGO_SDK:-$(evo_detect_sdk)}"
NEXT_VERSION=""
EXPECT_EXISTING_TAG=0
MIN_FREE_GB="${EVOLVE_PREFLIGHT_MIN_FREE_GB:-5}"
SKIP_SSH=0
JSON=0
STATE_DIR="${EVOLVE_STATE_DIR:-$HOME/Library/Application Support/Tapgo AICoding/state}"

GIT_BIN="${EVOLVE_PREFLIGHT_GIT:-git}"
PYTHON_BIN="${EVOLVE_PREFLIGHT_PYTHON:-python3}"
GH_BIN="${EVOLVE_PREFLIGHT_GH:-gh}"
XCRUN_BIN="${EVOLVE_PREFLIGHT_XCRUN:-xcrun}"
SSH_BIN="${EVOLVE_PREFLIGHT_SSH:-ssh}"
DF_BIN="${EVOLVE_PREFLIGHT_DF:-df}"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-local}"; shift ;;
    --remote) REMOTE="${2:-}"; shift ;;
    --sdk) SDK="${2:-}"; shift ;;
    --next-version) NEXT_VERSION="${2:-}"; shift ;;
    --expect-existing-tag) EXPECT_EXISTING_TAG=1 ;;
    --min-free-gb) MIN_FREE_GB="${2:-}"; shift ;;
    --state-dir) STATE_DIR="${2:-}"; shift ;;
    --skip-ssh) SKIP_SSH=1 ;;
    --json) JSON=1 ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "ERROR: unexpected arg: $1" >&2; exit 2 ;;
  esac
  shift
done

case "$MODE" in
  local|publish) ;;
  *) echo "ERROR: --mode must be local or publish (got: $MODE)" >&2; exit 2 ;;
esac
[[ "$MIN_FREE_GB" =~ ^[0-9]+$ ]] || { echo "ERROR: --min-free-gb must be an integer" >&2; exit 2; }
REMOTE="${REMOTE:-$(tapgo_upstream_remote 2>/dev/null || echo origin)}"

PASSED=0; WARNED=0; FAILED=0
RESULTS=()

record() { # record <ok|warn|fail> <name> [detail]
  local level="$1" name="$2" detail="${3:-}"
  case "$level" in
    ok)   PASSED=$((PASSED + 1)) ;;
    warn) WARNED=$((WARNED + 1)) ;;
    fail) FAILED=$((FAILED + 1)) ;;
  esac
  RESULTS+=("$level|$name|$detail")
  if [[ "$JSON" -ne 1 ]]; then
    local tag="OK  "
    [[ "$level" == "warn" ]] && tag="WARN"
    [[ "$level" == "fail" ]] && tag="FAIL"
    printf '%s %-18s %s\n' "$tag" "$name" "$detail"
  fi
}

# ---------- 工具链 ----------
if "$GIT_BIN" --version >/dev/null 2>&1; then
  record ok "git"
else
  record fail "git" "不可用（${GIT_BIN}）"
fi

PY_VER="$("$PYTHON_BIN" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null || true)"
if [[ -z "$PY_VER" ]]; then
  record fail "python3" "不可用（${PYTHON_BIN}）"
elif "$PYTHON_BIN" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
  record ok "python3" "$PY_VER"
else
  record fail "python3" "需要 >= 3.9（当前 ${PY_VER}）"
fi

SDK_PATH="$("$XCRUN_BIN" -sdk "$SDK" --show-sdk-path 2>/dev/null || true)"
if [[ -n "$SDK_PATH" && -d "$SDK_PATH" ]]; then
  record ok "sdk" "$SDK"
else
  record fail "sdk" "xcrun -sdk $SDK --show-sdk-path 失败"
fi
SWIFT_VER="$("$XCRUN_BIN" -sdk "$SDK" swift --version 2>/dev/null | head -1 || true)"
if [[ -n "$SWIFT_VER" ]]; then
  record ok "swift" "$SWIFT_VER"
else
  record fail "swift" "xcrun -sdk $SDK swift --version 失败"
fi

CODEX_PATH="$(evo_detect_codex 2>/dev/null || true)"
if [[ -n "$CODEX_PATH" ]]; then
  record ok "codex" "$CODEX_PATH"
else
  record warn "codex" "未找到（仅影响 harness 启动，不影响发布本身）"
fi

# ---------- 磁盘 ----------
FREE_GB="$("$DF_BIN" -g "$ROOT" 2>/dev/null | awk 'NR==2 {print $4}' || true)"
if [[ ! "$FREE_GB" =~ ^[0-9]+$ ]]; then
  record warn "disk" "无法读取可用空间"
elif (( FREE_GB < MIN_FREE_GB )); then
  record fail "disk" "可用 ${FREE_GB}G < 要求 ${MIN_FREE_GB}G"
else
  record ok "disk" "可用 ${FREE_GB}G / 要求 ${MIN_FREE_GB}G"
fi

# ---------- 仓库布局 ----------
MISSING_FILES=()
for required in scripts/evolve.sh scripts/deploy-fleet.sh scripts/health-check.sh \
                scripts/worktree-verify.sh scripts/build-app.sh scripts/evolution-records.py \
                evolution/BACKLOG.md evolution/protected-paths.json AppBuilder/Info.plist; do
  [[ -e "$ROOT/$required" ]] || MISSING_FILES+=("$required")
done
if [[ "${#MISSING_FILES[@]}" -eq 0 ]]; then
  record ok "repo-layout" "必需脚本/清单齐全"
else
  record fail "repo-layout" "缺失：${MISSING_FILES[*]}"
fi

# ---------- 受保护清单 ----------
if "$PYTHON_BIN" -c 'import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data.get("version", 0) >= 1 and len(data.get("paths", [])) >= 1' \
   "$ROOT/evolution/protected-paths.json" >/dev/null 2>&1; then
  record ok "protected-manifest" "可解析"
else
  record fail "protected-manifest" "evolution/protected-paths.json 无法解析"
fi

# ---------- 运行态目录 ----------
if mkdir -p "$STATE_DIR" 2>/dev/null && : > "$STATE_DIR/.preflight-probe" 2>/dev/null; then
  rm -f "$STATE_DIR/.preflight-probe"
  record ok "state-dir" "可写"
else
  record fail "state-dir" "$STATE_DIR 不可写"
fi

# ---------- 远端 + 认证 + 三机（发布模式） ----------
if [[ "$MODE" == "publish" ]]; then
  if "$GIT_BIN" ls-remote --exit-code --heads "$REMOTE" main >/dev/null 2>&1; then
    record ok "remote" "$REMOTE 可达"
  else
    record fail "remote" "$REMOTE 不可达（git ls-remote 失败）"
  fi

  LOCAL_HEAD="$("$GIT_BIN" rev-parse HEAD 2>/dev/null || true)"
  REMOTE_HEAD="$("$GIT_BIN" rev-parse "$REMOTE/main" 2>/dev/null || true)"
  if [[ -z "$REMOTE_HEAD" ]]; then
    record warn "upstream" "无法解析 $REMOTE/main"
  elif [[ -n "$LOCAL_HEAD" && "$LOCAL_HEAD" == "$REMOTE_HEAD" ]]; then
    record ok "upstream" "HEAD == $REMOTE/main"
  else
    record fail "upstream" "本地 HEAD 与 $REMOTE/main 不一致，先跑 scripts/sync-upstream.sh --apply"
  fi

  GH_STATUS_RC=0
  GH_STATUS="$("$GH_BIN" auth status 2>&1)" || GH_STATUS_RC=$?
  if [[ "$GH_STATUS_RC" -eq 0 ]]; then
    record ok "gh-auth" "$(sed -n 's/.*account \([^ ]*\).*/\1/p' <<< "$GH_STATUS" | head -1)"
  else
    record fail "gh-auth" "gh auth status 未登录（Release 必需）"
  fi

  if [[ "$SKIP_SSH" -eq 1 ]]; then
    record warn "ssh" "已跳过三机连通性检查（--skip-ssh）"
  else
    for target in ${TAPGO_FLEET_TARGETS[@]+"${TAPGO_FLEET_TARGETS[@]}"}; do
      host="${target%%:*}"
      if "$SSH_BIN" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
           "$host" true >/dev/null 2>&1; then
        record ok "ssh:$host" "可登录"
      else
        record fail "ssh:$host" "无法登录（部署会失败）"
      fi
    done
  fi
fi

# ---------- 版本 tag ----------
if [[ -z "$NEXT_VERSION" ]]; then
  MAX_TAG="$("$GIT_BIN" tag --list 'v[0-9]*.[0-9]*.[0-9]*' --merged HEAD 2>/dev/null | evo_max_version || true)"
  BASE_VERSION="${MAX_TAG#v}"
  if [[ -z "$BASE_VERSION" ]]; then
    BASE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/AppBuilder/Info.plist" 2>/dev/null || echo 0.0.0)"
  fi
  NEXT_VERSION="$(evo_next_version "$BASE_VERSION" patch)"
fi
TAG="v${NEXT_VERSION}"
LOCAL_TAG="$("$GIT_BIN" rev-parse -q --verify "refs/tags/$TAG" 2>/dev/null || true)"
if [[ "$EXPECT_EXISTING_TAG" -eq 1 ]]; then
  if [[ -n "$LOCAL_TAG" ]]; then
    record ok "tag:$TAG" "本地已存在（续跑）"
  else
    record fail "tag:$TAG" "续跑要求本地 tag 已存在"
  fi
elif [[ -n "$LOCAL_TAG" ]]; then
  record fail "tag:$TAG" "本地 tag 已存在，需递增版本号"
elif [[ "$MODE" == "publish" ]] && \
     "$GIT_BIN" ls-remote --exit-code --tags "$REMOTE" "refs/tags/$TAG" >/dev/null 2>&1; then
  record fail "tag:$TAG" "远端 tag 已存在，需递增版本号或同步"
else
  record ok "tag:$TAG" "未被占用"
fi

# ---------- 结果 ----------
if [[ "$JSON" -eq 1 ]]; then
  python3 - "$PASSED" "$WARNED" "$FAILED" "$MODE" "$NEXT_VERSION" "${RESULTS[@]+"${RESULTS[@]}"}" <<'PY'
import json, sys
passed, warned, failed, mode, version = (int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]),
                                         sys.argv[4], sys.argv[5])
checks = []
for raw in sys.argv[6:]:
    level, name, detail = (raw.split("|", 2) + ["", ""])[:3]
    checks.append({"level": level, "name": name, "detail": detail})
print(json.dumps({"mode": mode, "nextVersion": version, "passed": passed,
                  "warned": warned, "failed": failed, "checks": checks},
                 ensure_ascii=False, indent=2))
PY
fi

if [[ "$FAILED" -gt 0 ]]; then
  [[ "$JSON" -eq 1 ]] || echo "PREFLIGHT FAILED: ${FAILED} 项不通过（warn ${WARNED}，ok ${PASSED}）" >&2
  exit 12
fi
[[ "$JSON" -eq 1 ]] || echo "PREFLIGHT OK: ${PASSED} 项通过（warn ${WARNED}）"
exit 0
