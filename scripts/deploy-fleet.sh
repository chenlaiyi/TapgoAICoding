#!/usr/bin/env bash
# deploy-fleet.sh — install one verified .app build on all three Macs.
#
# Targets (fixed by AGENTS.md):
#   local          = this machine (fafa's Mac mini)
#   jkmacmini      = chanlaiyi@jkmacmini
#   chenlaiyi-mbp  = chenlaiyi@100.100.191.111
#
# The script copies the already-built bundle (same bytes locally and remotely),
# re-signs ad-hoc on the target when the original signature is not portable,
# restarts the app, then reads back version + PID. It never builds or pulls.
#
# EVO-039：版本/PID 回读之后还会跑一遍界面断言（scripts/evolution-ui-assert.sh，
# 经 ssh stdin 管道执行，不依赖远端仓库版本）：H5 /api/state 的 appVersion 必须
# 等于部署版本、H5 骨架与 app.js 标记齐全、无 token 请求仍被拒绝。
# 失败即视为部署失败（版本到位 ≠ 界面可用）。EVOLVE_SKIP_UI_ASSERT=1 可跳过。
#
# 可覆盖入口（测试/自定义部署，真实环境走默认值）：
#   EVOLVE_FLEET_APP / LOCAL_DEST / REMOTE_APP / SSH / SCP / RESTART_SCRIPT /
#   UI_ASSERT_SCRIPT / RESTART_WAIT / TARGETS_OVERRIDE / OPEN / PGREP /
#   EVOLVE_FLEET_DAEMON_SCRIPT / EVOLVE_FLEET_DAEMON(=0 跳过) / EVOLVE_FORCE_DAEMON
#
# Usage:
#   ./scripts/deploy-fleet.sh                 # version from AppBuilder/Info.plist
#   ./scripts/deploy-fleet.sh 0.5.257
#   ./scripts/deploy-fleet.sh --dry-run 0.5.257
#   ./scripts/deploy-fleet.sh --restart-local # also restart the local GUI app
#   ./scripts/deploy-fleet.sh --only jkmacmini 0.5.282      # canary host only
#   ./scripts/deploy-fleet.sh --exclude jkmacmini 0.5.282   # remaining hosts
#   ./scripts/deploy-fleet.sh --skip-daemon 0.5.319        # 只装 App（daemon 单独发）
#
# NOTE: --restart-local kills the currently running Tapgo AICoding, which may
# terminate the Codex session driving this script. It is opt-in for that reason.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DRY_RUN=""
RESTART_LOCAL=""
SKIP_DAEMON=""
ONLY_HOST=""
EXCLUDE_HOST=""
VERSION=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --restart-local) RESTART_LOCAL=1 ;;
    --skip-daemon) SKIP_DAEMON=1 ;;
    --only) ONLY_HOST="${2:-}"; shift ;;
    --exclude) EXCLUDE_HOST="${2:-}"; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) [[ -z "$VERSION" ]] || { echo "ERROR: unexpected arg: $1" >&2; exit 2; }; VERSION="$1" ;;
  esac
  shift
done
[[ -z "$ONLY_HOST" || -z "$EXCLUDE_HOST" ]] || { echo "ERROR: --only and --exclude are mutually exclusive." >&2; exit 2; }
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' AppBuilder/Info.plist)}"
# 可覆盖入口（EVO-045）：测试与自定义部署用；真实环境全部落到默认值。
APP="${EVOLVE_FLEET_APP:-$ROOT/Tapgo AICoding.app}"
BIN_REL="Contents/MacOS/TapgoAICoding"
LOCAL_DEST="${EVOLVE_FLEET_LOCAL_DEST:-/Applications/Tapgo AICoding.app}"
# 远端 App 路径默认值写在远端脚本内部：ssh 会把 ProgramArguments 拼成一条命令，
# 含空格的路径作为参数传过去会被拆开（v0.5.302 真机踩过：sleep 收到 AICoding.app）。
# 需要覆盖时用不含空格的路径（EVOLVE_FLEET_REMOTE_APP）。
REMOTE_APP_OVERRIDE="${EVOLVE_FLEET_REMOTE_APP:-}"
if [[ -n "$REMOTE_APP_OVERRIDE" && "$REMOTE_APP_OVERRIDE" == *" "* ]]; then
  echo "ERROR: EVOLVE_FLEET_REMOTE_APP 不能含空格（ssh 参数会被重新分词）：$REMOTE_APP_OVERRIDE" >&2
  exit 2
fi
SSH_BIN="${EVOLVE_FLEET_SSH:-ssh}"
SCP_BIN="${EVOLVE_FLEET_SCP:-scp}"
RESTART_SCRIPT="${EVOLVE_FLEET_RESTART_SCRIPT:-$ROOT/scripts/restart-and-resume.sh}"
DAEMON_SCRIPT="${EVOLVE_FLEET_DAEMON_SCRIPT:-$ROOT/scripts/deploy-harness-daemon.sh}"
UI_ASSERT_SCRIPT="${EVOLVE_FLEET_UI_ASSERT_SCRIPT:-$ROOT/scripts/evolution-ui-assert.sh}"
RESTART_WAIT="${EVOLVE_FLEET_RESTART_WAIT:-3}"
[[ -d "$APP" ]] || { echo "ERROR: $APP missing; run scripts/build-app.sh first." >&2; exit 3; }
BUILT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$BUILT" == "$VERSION" ]] || { echo "ERROR: bundle $BUILT != requested $VERSION" >&2; exit 3; }

# 部署目标来自 scripts/fleet-hosts.sh（唯一真源，预检脚本共用）。
# shellcheck source=scripts/fleet-hosts.sh
source "$ROOT/scripts/fleet-hosts.sh"
if [[ -n "${EVOLVE_FLEET_TARGETS_OVERRIDE:-}" ]]; then
  IFS=',' read -r -a ALL_TARGETS <<< "$EVOLVE_FLEET_TARGETS_OVERRIDE"
else
  ALL_TARGETS=("${TAPGO_FLEET_TARGETS[@]}")
fi
TARGETS=()
for target in "${ALL_TARGETS[@]}"; do
  host="${target%%:*}"
  [[ -n "$ONLY_HOST" && "$host" != "$ONLY_HOST" ]] && continue
  [[ -n "$EXCLUDE_HOST" && "$host" == "$EXCLUDE_HOST" ]] && continue
  TARGETS+=("$target")
done

INCLUDE_LOCAL=1
[[ -n "$ONLY_HOST" && "$ONLY_HOST" != "local" ]] && INCLUDE_LOCAL=0
[[ -n "$EXCLUDE_HOST" && "$EXCLUDE_HOST" == "local" ]] && INCLUDE_LOCAL=0

install_local() {
  local dest="$LOCAL_DEST"
  echo "==> [local] installing v${VERSION}"
  if [[ -n "$DRY_RUN" ]]; then
    echo "    [dry-run] rm -rf $dest && ditto '$APP' $dest"
    return 0
  fi
  rm -rf "$dest"
  if ! ditto "$APP" "$dest"; then
    echo "ERROR: [local] 复制到 ${dest} 失败" >&2
    return 1
  fi
  local got
  got="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$dest/Contents/Info.plist")"
  [[ "$got" == "$VERSION" ]] || { echo "ERROR: local installed version $got != $VERSION" >&2; return 1; }
  echo "==> [local] installed version=${got} (restart deferred)"
  if [[ -n "$RESTART_LOCAL" ]]; then
    "$RESTART_SCRIPT"
    if [[ "${EVOLVE_SKIP_UI_ASSERT:-}" == "1" ]]; then
      echo "==> [local] UI assert skipped (EVOLVE_SKIP_UI_ASSERT=1)"
    elif ! "$UI_ASSERT_SCRIPT" --expect-version "$VERSION"; then
      echo "ERROR: [local] 界面断言失败：版本到位但界面不可用" >&2
      return 1
    else
      echo "==> [local] UI assert passed (H5 state + assets + auth)"
    fi
  else
    echo "==> [local] UI assert skipped（本地 App 未重启；加 --restart-local 才断言）"
  fi
}

install_remote() {
  local target="$1"
  local host="${target%%:*}"
  local repo="${target#*:}"
  local zip
  zip="$(mktemp -t tapgo-fleet.XXXXXX).zip"
  local remote_zip="/tmp/tapgo-fleet-${VERSION}.zip"
  local remote_unpack="/tmp/tapgo-fleet-unpack-${VERSION}"
  echo "==> [${host}] installing v${VERSION}"
  if [[ -n "$DRY_RUN" ]]; then
    echo "    [dry-run] copy bundle to ${host}${repo}, install ${REMOTE_APP_OVERRIDE:-/Applications/Tapgo AICoding.app}, restart, verify version/PID + UI assert"
    rm -f "$zip"
    return 0
  fi

  ditto -c -k --keepParent "$APP" "$zip"
  # 注意：install_remote 是从 `if ! install_remote` 里调用的，bash 在这种上下文
  # 会关闭 errexit —— 所以每一步都必须显式判状态，否则传输/安装失败会被后续步骤
  # 掩盖（EVO-045 演练实测：scp 失败时旧代码仍打印 "restart + version verified"）。
  if ! "$SCP_BIN" -q -o BatchMode=yes "$zip" "${host}:${remote_zip}"; then
    rm -f "$zip"
    echo "ERROR: [${host}] 传输失败：无法把 ${zip} 复制到 ${remote_zip}" >&2
    return 1
  fi
  rm -f "$zip"

  # 注意：空字符串参数经 ssh 拼接会消失，导致后续参数整体前移（v0.5.302 真机踩过：
  # $4 变成等待秒数、App 被装到名为 "3" 的目录）。所以用 "-" 作哨兵，永不传空串。
  if ! "$SSH_BIN" -o BatchMode=yes "$host" bash -s -- \
    "$VERSION" "$remote_zip" "$remote_unpack" "${REMOTE_APP_OVERRIDE:--}" "$RESTART_WAIT" <<'REMOTE'
set -euo pipefail
VERSION="$1"; ZIP="$2"; UNPACK="$3"
APP="${4:--}"
[[ "$APP" == "-" ]] && APP="/Applications/Tapgo AICoding.app"   # 默认值留在远端，避免空格路径被 ssh 拆开
WAIT="${5:-3}"
[[ "$APP" == *.app ]] || { echo "ERROR: 远端 App 路径异常（应为 *.app）: ${APP}" >&2; exit 1; }
[[ "$WAIT" =~ ^[0-9]+$ ]] || { echo "ERROR: 远端等待秒数非法: ${WAIT}" >&2; exit 1; }
OPEN_BIN="${EVOLVE_FLEET_OPEN:-open}"
PGREP_BIN="${EVOLVE_FLEET_PGREP:-pgrep}"
BIN="$APP/Contents/MacOS/TapgoAICoding"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
HELPER="$APP/Contents/Resources/computer-use-helper/Tapgo Computer Use.app/Contents/MacOS/TapgoComputerUseHelper"

pkill -f "$BIN" 2>/dev/null || true
sleep 1
rm -rf "$APP" "$UNPACK"
mkdir -p "$UNPACK" "$(dirname "$APP")"
ditto -x -k "$ZIP" "$UNPACK"
mv "$UNPACK/Tapgo AICoding.app" "$APP"
rm -rf "$UNPACK" "$ZIP"

# Portable signature: strip the build-host signature, then deep ad-hoc sign.
codesign --remove-signature "$BIN" >/dev/null 2>&1 || true
[[ -f "$SPARKLE" ]] && codesign --remove-signature "$SPARKLE" >/dev/null 2>&1 || true
[[ -f "$HELPER" ]] && codesign --remove-signature "$HELPER" >/dev/null 2>&1 || true
codesign --force --deep --sign - "$APP" >/dev/null 2>&1

GOT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo missing)"
[[ "$GOT" == "$VERSION" ]] || { echo "ERROR: installed version ${GOT} != ${VERSION}" >&2; exit 1; }
"$OPEN_BIN" "$APP" >/dev/null 2>&1 || true
sleep "$WAIT"
PID="$("$PGREP_BIN" -f "$BIN" 2>/dev/null | head -1 || true)"
echo "VERSION=${GOT}"
echo "PID=${PID:-none}"
[[ -n "$PID" ]]
REMOTE
  then
    echo "ERROR: [${host}] 远端安装/重启失败（见上方远端输出）" >&2
    return 1
  fi
  echo "==> [${host}] restart + version ${VERSION} verified"

  if [[ "${EVOLVE_SKIP_UI_ASSERT:-}" == "1" ]]; then
    echo "==> [${host}] UI assert skipped (EVOLVE_SKIP_UI_ASSERT=1)"
    return 0
  fi
  # 把本机的最新断言脚本喂给远端 bash，避免依赖远端仓库版本。
  if ! "$SSH_BIN" -o BatchMode=yes "$host" bash -s -- --expect-version "$VERSION" \
       < "$UI_ASSERT_SCRIPT"; then
    echo "ERROR: [${host}] 界面断言失败：版本到位但界面不可用（H5 状态/资源/鉴权）" >&2
    return 1
  fi
  echo "==> [${host}] UI assert passed (H5 state + assets + auth)"
}

[[ "$INCLUDE_LOCAL" -eq 1 ]] && install_local
FAIL=0
for target in ${TARGETS[@]+"${TARGETS[@]}"}; do
  if ! install_remote "$target"; then
    echo "ERROR: deployment failed on ${target%%:*}" >&2
    FAIL=1
  fi
done
[[ "$FAIL" -eq 0 ]] || exit 1

# ---------- daemon（TapgoHarness）----------
# daemon 不在 .app 包内，只装 App 不会更新它（v0.5.319 的并发修复就是这样漏掉
# 过远端机器）。默认顺带部署 daemon 并跑并发探针；只想发 App、或目标机正在跑
# 会话时用 --skip-daemon / EVOLVE_FLEET_DAEMON=0 跳过。
if [[ -n "$SKIP_DAEMON" || "${EVOLVE_FLEET_DAEMON:-1}" == "0" ]]; then
  echo "==> daemon 部署跳过（--skip-daemon / EVOLVE_FLEET_DAEMON=0）"
elif [[ ! -f "$DAEMON_SCRIPT" ]]; then
  echo "WARN: 找不到 daemon 部署脚本 ${DAEMON_SCRIPT}，跳过" >&2
else
  DAEMON_ARGS=()
  [[ -n "$DRY_RUN" ]] && DAEMON_ARGS+=(--dry-run)
  [[ -n "$ONLY_HOST" ]] && DAEMON_ARGS+=(--only "$ONLY_HOST")
  if ! bash "$DAEMON_SCRIPT" ${DAEMON_ARGS[@]+"${DAEMON_ARGS[@]}"}; then
    echo "ERROR: daemon 部署失败（App 已装好；daemon 可单独重跑 scripts/deploy-harness-daemon.sh）" >&2
    exit 1
  fi
fi
