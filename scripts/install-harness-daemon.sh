#!/usr/bin/env bash
# install-harness-daemon.sh — 安装并注册 TapgoHarness daemon（v0.5.72 harness 解耦）
#
# 行为：
#   1. swift build TapgoHarness（如产物不存在）
#   2. 复制二进制到 ~/.tapgo-aicoding/bin/TapgoHarness
#   3. 写 launchd plist 到 ~/Library/LaunchAgents/，填充真实路径 + API key
#   4. launchctl load -w 注册
#
# 卸载：./scripts/uninstall-harness-daemon.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/Tapgo AICoding"
BIN_DIR="$HOME/.tapgo-aicoding/bin"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs/TapgoAICoding"
SOCKET_PATH="$APP_SUPPORT/run/harness.sock"
CODEX_HOME="$APP_SUPPORT/codex"
CODEX_BIN="/opt/homebrew/bin/codex"
LABEL="com.tapgo.aicoding.harness"
PLIST_PATH="$LAUNCH_AGENTS/$LABEL.plist"

echo "[1/5] 准备目录..."
mkdir -p "$APP_SUPPORT/run" "$BIN_DIR" "$LAUNCH_AGENTS" "$LOG_DIR"

echo "[2/5] 编译 TapgoHarness（如果还没编）..."
cd "$REPO_ROOT"
swift build --product TapgoHarness --configuration release 2>&1 | tail -3
BIN_SRC="$REPO_ROOT/.build/arm64-apple-macosx/release/TapgoHarness"
if [ ! -x "$BIN_SRC" ]; then
    BIN_SRC="$REPO_ROOT/.build/arm64-apple-macosx/debug/TapgoHarness"
fi
echo "  binary: $BIN_SRC"

echo "[3/5] 安装二进制..."
cp -f "$BIN_SRC" "$BIN_DIR/TapgoHarness"
chmod 0755 "$BIN_DIR/TapgoHarness"

echo "[4/5] 写 launchd plist..."
API_KEY="$(grep experimental_bearer_token "$CODEX_HOME/config.toml" | head -1 | sed 's/.*"\(sk-cp-[^"]*\)".*/\1/')"
if [ -z "${API_KEY:-}" ]; then
    echo "ERROR: 找不到 API key，请检查 $CODEX_HOME/config.toml" >&2
    exit 1
fi

PLIST_TEMPLATE="$REPO_ROOT/scripts/launchd/$LABEL.plist"
sed -e "s|__HARNESS_BIN__|$BIN_DIR/TapgoHarness|g" \
    -e "s|__SOCKET_PATH__|$SOCKET_PATH|g" \
    -e "s|__CODEX_HOME__|$CODEX_HOME|g" \
    -e "s|__API_KEY__|$API_KEY|g" \
    -e "s|__LOG_DIR__|$LOG_DIR|g" \
    "$PLIST_TEMPLATE" > "$PLIST_PATH"
chmod 0644 "$PLIST_PATH"

echo "[5/5] 注册 launchd 服务..."
# 先卸载旧的（如果有），避免重复注册报错
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl enable "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/$LABEL" 2>/dev/null || true

echo ""
echo "=== 安装完成 ==="
echo "  binary:  $BIN_DIR/TapgoHarness"
echo "  socket:  $SOCKET_PATH"
echo "  plist:   $PLIST_PATH"
echo "  logs:    $LOG_DIR/harness.{log,err.log}"
echo ""
echo "查看状态: launchctl print gui/\$(id -u)/$LABEL | head -20"
echo "查看日志: tail -f $LOG_DIR/harness.log"
