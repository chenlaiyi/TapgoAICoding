#!/usr/bin/env bash
# 把当前 build 产物安装到真机并启动, 用于真机冒烟回归。
#
# 用法:
#   ./Scripts/install-device.sh <DEVICE_UDID> [DEVICE_NAME]
#   ./Scripts/install-device.sh A35FE5C0-C4C1-5438-8243-B8645E02AAF9 JK14pro
#
# 前置: 已在 JKmacmini 上跑过 BUILD_TARGET=device 真机构建,
#       且 `security unlock-keychain login.keychain-db` 已解锁。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
IOS_DIR="$ROOT/mobile/ios"
APP="$IOS_DIR/build/Build/Products/Debug-iphoneos/点点够终端.app"

DEVICE_UDID="${1:-}"
DEVICE_NAME="${2:-}"

if [[ -z "$DEVICE_UDID" ]]; then
  echo "用法: $0 <DEVICE_UDID> [DEVICE_NAME]"
  echo ""
  echo "已连接设备:"
  xcrun devicectl list devices 2>&1 | grep -v "^---" | head -10
  exit 2
fi

if [[ ! -d "$APP" ]]; then
  echo "缺少 build 产物: $APP"
  echo "请先跑: BUILD_TARGET=device DEVICE_UDID=$DEVICE_UDID ./Scripts/build.sh"
  exit 2
fi

echo "[1/4] 解锁 login keychain..."
security unlock-keychain -p "" login.keychain-db 2>/dev/null || true

echo "[2/4] 安装到 $DEVICE_UDID ($DEVICE_NAME)..."
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP" 2>&1 | tail -2

echo "[3/4] 启动 (TAPGO_FORCE_PAIRED=1 让 DashboardView 可截图回归)..."
xcrun devicectl device process launch \
  --device "$DEVICE_UDID" \
  com.devtools.terminalSimple \
  TAPGO_FORCE_PAIRED=1 2>&1 | tail -2

echo "[4/4] 验证..."
xcrun devicectl device info apps --device "$DEVICE_UDID" 2>&1 \
  | grep -B 1 -A 1 "com.devtools.terminalSimple" | head -5

echo ""
echo "✅ 安装完成; JKmacmini 端如需截图, 在 Xcode → Window → Devices and Simulators → 选 $DEVICE_NAME → Take Screenshot"
