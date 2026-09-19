#!/usr/bin/env bash
# deploy-harness-daemon.sh — 把当前仓库的 TapgoHarness daemon 部署到 fleet。
#
# 为什么需要它：daemon 不在 .app 包内，`deploy-fleet.sh` 只装 App。此前升级
# daemon 要逐台手工 `install-harness-daemon.sh`，本次 v0.5.319 修复就因此在
# 三台机之间来回折腾。本脚本把三件事一次做完：
#
#   1. 目标机**本地编译**（Swift 源码只依赖 Foundation/Darwin）。
#      跨机拷贝的二进制会被 taskgated 以 `Code Signature Invalid` SIGKILL
#      （v0.5.319 真机踩过），本地编译是唯一稳态做法。
#   2. bootout + bootstrap 重新注册 launchd job。只 `kickstart -k` 有概率被
#      缓存的签名判定卡住（同样在 v0.5.319 踩过），必须整job 重注册。
#   3. 跑并发探针（harness-daemon-probe.sh）：确认 daemon 真在服务，且
#      「A 连接占线时 B 的 initialize 仍能拿到响应」。
#
# 幂等：源码 sha256 与安装时记录的标记一致、daemon 在跑、探针通过 → 跳过重启。
# 所以可以安全地挂在每次 App 发版之后，不会无谓打断正在跑的会话。
#
# 用法:
#   scripts/deploy-harness-daemon.sh                 # 本机 + 两台远端
#   scripts/deploy-harness-daemon.sh --only local
#   scripts/deploy-harness-daemon.sh --dry-run
#   scripts/deploy-harness-daemon.sh --force         # 会话占线时也重启
#   scripts/deploy-harness-daemon.sh --skip-probe
#
# 环境覆盖（测试/自定义）: EVOLVE_FLEET_SSH / EVOLVE_FLEET_SCP / EVOLVE_CODEX_BIN /
#   TAPGO_FLEET_TARGETS / TAPGO_FLEET_LOCAL / TAPGO_HARNESS_DIR
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/fleet-hosts.sh
source "$ROOT/scripts/fleet-hosts.sh"

DAEMON_SRC="$ROOT/Sources/TapgoHarness/main.swift"
PLIST_TEMPLATE="$ROOT/scripts/launchd/com.tapgo.aicoding.harness.plist"
PROBE_SCRIPT="$ROOT/scripts/harness-daemon-probe.sh"
API_KEY_SCRIPT="$ROOT/scripts/harness-api-key.sh"
LOCAL_INSTALLER="$ROOT/scripts/install-harness-daemon.sh"
SSH_BIN="${EVOLVE_FLEET_SSH:-ssh}"
SCP_BIN="${EVOLVE_FLEET_SCP:-scp}"
LABEL="com.tapgo.aicoding.harness"

DRY_RUN=""
ONLY_HOST=""
FORCE=""
SKIP_PROBE=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --only) ONLY_HOST="${2:-}"; shift ;;
    --force) FORCE=1 ;;
    --skip-probe) SKIP_PROBE=1 ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "ERROR: unexpected arg: $1" >&2; exit 2 ;;
  esac
  shift
done

[[ -f "$DAEMON_SRC" ]] || { echo "ERROR: 找不到 daemon 源码 $DAEMON_SRC" >&2; exit 2; }
[[ -f "$PLIST_TEMPLATE" ]] || { echo "ERROR: 找不到 plist 模板 $PLIST_TEMPLATE" >&2; exit 2; }
[[ -x "$PROBE_SCRIPT" || -f "$PROBE_SCRIPT" ]] || { echo "ERROR: 找不到探针 $PROBE_SCRIPT" >&2; exit 2; }

SRC_SHA="$(shasum -a 256 "$DAEMON_SRC" | awk '{print $1}')"
echo "==> daemon 源码 sha256: ${SRC_SHA:0:16}…  (Sources/TapgoHarness/main.swift)"

run_probe() { # run_probe <label> <ssh-host-or-empty>
  local label="$1" host="$2"
  [[ -n "$SKIP_PROBE" ]] && return 0
  if [[ -z "$host" ]]; then
    "$PROBE_SCRIPT" || return 1
  else
    "$SSH_BIN" -o BatchMode=yes "$host" bash -s -- < "$PROBE_SCRIPT" || return 1
  fi
  return 0
}

install_local() {
  echo "==> [local] 部署 daemon"
  local bin_dir="${TAPGO_HARNESS_DIR:-$HOME/.tapgo-aicoding/bin}"
  local marker="$bin_dir/.TapgoHarness.src.sha256"
  local current_pid busy installed_sha
  current_pid="$(launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | awk '/pid = /{print $3; exit}')"
  installed_sha="$(cat "$marker" 2>/dev/null || echo "")"
  busy="0"
  if [[ -n "$current_pid" ]]; then
    busy="$(lsof -p "$current_pid" 2>/dev/null | grep -c 'harness.sock' || true)"
  fi

  if [[ -n "$DRY_RUN" ]]; then
    echo "    [dry-run] 编译 Sources/TapgoHarness/main.swift → ${bin_dir}/TapgoHarness"
    echo "    [dry-run] bootout + bootstrap + kickstart ${LABEL}（当前 pid=${current_pid:-none}，socket fd=${busy}）"
    echo "    [dry-run] 运行并发探针"
    return 0
  fi

  # 幂等短路：同一份源码 + 进程在跑 + 探针通过 → 不动它
  if [[ "$installed_sha" == "$SRC_SHA" && -n "$current_pid" ]] && run_probe local "" ; then
    echo "    [local] 源码未变且探针通过，跳过重启（pid=${current_pid}）"
    return 0
  fi
  if [[ "$busy" -ge 2 && -z "$FORCE" ]]; then
    echo "    [local] WARN: daemon(pid=${current_pid}) 正在服务会话，跳过重启；" >&2
    echo "            空闲后重跑本脚本，或加 --force 强制重启。" >&2
    return 1
  fi

  if ! "$LOCAL_INSTALLER" >/tmp/tapgo-daemon-local-install.log 2>&1; then
    echo "ERROR: [local] install-harness-daemon.sh 失败：" >&2
    tail -12 /tmp/tapgo-daemon-local-install.log >&2
    return 1
  fi
  current_pid="$(launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | awk '/pid = /{print $3; exit}')"
  if [[ -z "$current_pid" ]]; then
    echo "ERROR: [local] 安装后 launchd job 没有运行中的 pid" >&2
    tail -12 "/Users/$USER/Library/Logs/TapgoAICoding/harness.err.log" >&2 2>/dev/null || true
    return 1
  fi
  mkdir -p "$bin_dir" && printf '%s\n' "$SRC_SHA" > "$marker"
  if ! run_probe local ""; then
    echo "ERROR: [local] 并发探针失败（daemon 起来了但没在正常服务）" >&2
    return 1
  fi
  echo "==> [local] daemon pid=${current_pid} 已更新并通过并发探针"
  return 0
}

install_remote() {
  local target="$1"
  local host="${target%%:*}"
  local remote_dir="/tmp/tapgo-daemon-${SRC_SHA:0:12}"
  echo "==> [${host}] 部署 daemon"
  if [[ -n "$DRY_RUN" ]]; then
    echo "    [dry-run] scp main.swift + plist 模板 → ${host}:${remote_dir}"
    echo "    [dry-run] 目标机 xcrun swiftc 编译 → ~/.tapgo-aicoding/bin/TapgoHarness"
    echo "    [dry-run] 写 launchd plist（本机 config.toml 的 bearer）+ bootout/bootstrap/kickstart"
    echo "    [dry-run] 运行并发探针"
    return 0
  fi

  if ! "$SSH_BIN" -o BatchMode=yes "$host" "mkdir -p '$remote_dir'"; then
    echo "ERROR: [${host}] 无法创建远端目录 ${remote_dir}" >&2
    return 1
  fi
  if ! "$SCP_BIN" -q -o BatchMode=yes "$DAEMON_SRC" "${host}:${remote_dir}/main.swift" \
    || ! "$SCP_BIN" -q -o BatchMode=yes "$PLIST_TEMPLATE" "${host}:${remote_dir}/daemon.plist" \
    || ! "$SCP_BIN" -q -o BatchMode=yes "$API_KEY_SCRIPT" "${host}:${remote_dir}/api-key.sh"; then
    echo "ERROR: [${host}] 源码/模板传输失败" >&2
    return 1
  fi

  if ! "$SSH_BIN" -o BatchMode=yes "$host" bash -s -- "$remote_dir" "$SRC_SHA" "${EVOLVE_CODEX_BIN:--}" "$FORCE" <<'REMOTE'
set -euo pipefail
DIR="$1"; SRC_SHA="$2"; CODEX_ARG="$3"; FORCE="${4:-}"
LABEL="com.tapgo.aicoding.harness"
BIN_DIR="$HOME/.tapgo-aicoding/bin"
BIN="$BIN_DIR/TapgoHarness"
MARKER="$BIN_DIR/.TapgoHarness.src.sha256"
SUPPORT="$HOME/Library/Application Support/Tapgo AICoding"
SOCKET="$SUPPORT/run/harness.sock"
CODEX_HOME_DIR="$SUPPORT/codex"
LOG_DIR="$HOME/Library/Logs/TapgoAICoding"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

# --- codex 可执行文件探测（PATH → /opt/homebrew → /usr/local → ~/.local）---
CODEX_BIN=""
if [[ "$CODEX_ARG" != "-" && -x "$CODEX_ARG" ]]; then
  CODEX_BIN="$CODEX_ARG"
else
  for cand in "$(command -v codex 2>/dev/null || true)" \
              /opt/homebrew/bin/codex /usr/local/bin/codex "$HOME/.local/bin/codex"; do
    [[ -n "$cand" && -x "$cand" ]] && { CODEX_BIN="$cand"; break; }
  done
fi
[[ -n "$CODEX_BIN" ]] || { echo "ERROR: 找不到 codex 可执行文件（EVOLVE_CODEX_BIN 可显式指定）" >&2; exit 1; }

# --- API key：共用 scripts/harness-api-key.sh（优先 deepseek 段、跳过注释、任意前缀）---
API_KEY="$(bash "$DIR/api-key.sh" "$CODEX_HOME_DIR/config.toml")" || {
  echo "ERROR: 找不到 API key（$CODEX_HOME_DIR/config.toml 的 experimental_bearer_token）" >&2; exit 1;
}

# --- 当前状态 ---
CURRENT_PID="$(launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | awk '/pid = /{print $3; exit}' || true)"
BUSY=0
if [[ -n "$CURRENT_PID" ]]; then
  BUSY="$(lsof -p "$CURRENT_PID" 2>/dev/null | grep -c 'harness.sock' || true)"
fi
INSTALLED_SHA="$(cat "$MARKER" 2>/dev/null || echo "")"

# --- 幂等短路：同一份源码 + 进程在跑 → 交给外层探针判断，这里不重启 ---
if [[ "$INSTALLED_SHA" == "$SRC_SHA" && -n "$CURRENT_PID" ]]; then
  echo "SKIP same-source pid=$CURRENT_PID"
  exit 0
fi
if [[ "$BUSY" -ge 2 && "$FORCE" != "1" ]]; then
  echo "BUSY pid=$CURRENT_PID（正在服务会话）" >&2
  exit 3
fi

# --- 目标机本地编译（避免跨机签名被 taskgated 拒杀）---
BUILD_DIR="$(mktemp -d -t tapgo-harness-build.XXXXXX)"
xcrun swiftc -O "$DIR/main.swift" -o "$BUILD_DIR/TapgoHarness" 2>&1 | tail -3 || true
[[ -x "$BUILD_DIR/TapgoHarness" ]] || { echo "ERROR: swiftc 编译失败" >&2; exit 1; }

mkdir -p "$BIN_DIR" "$SUPPORT/run" "$LOG_DIR" "$(dirname "$PLIST_PATH")"
install -m 0755 "$BUILD_DIR/TapgoHarness" "$BIN"
rm -rf "$BUILD_DIR"

sed -e "s|__HARNESS_BIN__|$BIN|g" \
    -e "s|__SOCKET_PATH__|$SOCKET|g" \
    -e "s|__CODEX_HOME__|$CODEX_HOME_DIR|g" \
    -e "s|__CODEX_BIN__|$CODEX_BIN|g" \
    -e "s|__API_KEY__|$API_KEY|g" \
    -e "s|__LOG_DIR__|$LOG_DIR|g" \
    "$DIR/daemon.plist" > "$PLIST_PATH"
chmod 0644 "$PLIST_PATH"

# 必须 bootout + bootstrap 重新注册：只 kickstart -k 有概率被缓存的签名判定卡住
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl enable "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/$LABEL" 2>/dev/null || true

NEW_PID=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 0.5
  NEW_PID="$(launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | awk '/pid = /{print $3; exit}' || true)"
  [[ -n "$NEW_PID" && -S "$SOCKET" ]] && break
done
[[ -n "$NEW_PID" ]] || { echo "ERROR: 注册后没有运行中的 daemon pid" >&2; tail -6 "$LOG_DIR/harness.err.log" 2>/dev/null >&2 || true; exit 1; }
printf '%s\n' "$SRC_SHA" > "$MARKER"
echo "STARTED pid=$NEW_PID codex=$CODEX_BIN"
REMOTE
  then
    echo "ERROR: [${host}] 远端 daemon 安装/注册失败（见上方输出）" >&2
    return 1
  fi

  if ! run_probe "$host" "$host"; then
    echo "ERROR: [${host}] 并发探针失败" >&2
    return 1
  fi
  echo "==> [${host}] daemon 已更新并通过并发探针"
  return 0
}

FAILED=0
if [[ -z "$ONLY_HOST" || "$ONLY_HOST" == "$TAPGO_FLEET_LOCAL" ]]; then
  install_local || FAILED=1
fi
for target in "${TAPGO_FLEET_TARGETS[@]}"; do
  host="${target%%:*}"
  [[ -n "$ONLY_HOST" && "$ONLY_HOST" != "$host" ]] && continue
  install_remote "$target" || FAILED=1
done

if [[ "$FAILED" -ne 0 ]]; then
  echo "ERROR: daemon 部署存在失败项" >&2
  exit 1
fi
echo "==> daemon 部署完成（本机 + 远端，均已通过并发探针）"
