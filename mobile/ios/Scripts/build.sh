#!/usr/bin/env bash
# 构建 mobile/ios/TapgoTerminal.xcodeproj。
# 前置: macOS + Xcode 14+ + `brew install xcodegen` + `gem install xcodeproj`。
#
# 默认: 模拟器 (iOS Simulator) + 不签名 (CODE_SIGNING_ALLOWED=NO)
# 真机:  设置 BUILD_TARGET=device DEVICE_UDID=<UDID> (或 DEVICE_NAME=<name>)
#       自动切换 destination + 启用 CODE_SIGNING_ALLOWED=YES (用默认 Team)
#
# 行为:
#   1. 跑 mobile/ios/Scripts/check-sync.sh, 失败即退出
#   2. `xcodegen generate` force regenerate
#   3. `xcodebuild` 按 destination build
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
IOS_DIR="$ROOT/mobile/ios"
PROJ="$IOS_DIR/TapgoTerminal.xcodeproj"

echo "[1/3] 校验 MobilePairing 协议同步..."
"$IOS_DIR/Scripts/check-sync.sh"

echo "[2/3] 生成 Xcode 工程 (force regenerate, 避免新增源文件漏扫描)..."
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "缺少 xcodegen：brew install xcodegen" >&2
  exit 2
fi
(cd "$IOS_DIR" && xcodegen generate)

echo "[3/3] 解锁 login keychain (真机构建需要)..."
if [[ "${BUILD_TARGET:-}" == "device" ]]; then
  security unlock-keychain -p "" login.keychain-db 2>/dev/null || true
fi
echo "[3/3] xcodebuild..."
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "缺少 xcodebuild：请装 Xcode 后重试 (App Store -> Xcode)" >&2
  exit 2
fi

# 选 destination
if [[ "${BUILD_TARGET:-}" == "device" ]]; then
  if [[ -n "${DEVICE_UDID:-}" ]]; then
    DEST="platform=iOS,id=${DEVICE_UDID}"
  elif [[ -n "${DEVICE_NAME:-}" ]]; then
    DEST="platform=iOS,name=${DEVICE_NAME}"
  else
    DEST="generic/platform=iOS"
  fi
  SIGNING_FLAG="CODE_SIGNING_ALLOWED=YES"
  echo "    destination: ${DEST} (real device, 启用签名)"
else
  DEST="generic/platform=iOS Simulator"
  SIGNING_FLAG="CODE_SIGNING_ALLOWED=NO"
  echo "    destination: ${DEST} (simulator, 不签名)"
fi

xcodebuild \
  -project "$PROJ" \
  -scheme TapgoTerminal \
  -configuration Debug \
  -destination "${DEST}" \
  -derivedDataPath "$IOS_DIR/build" \
  ${SIGNING_FLAG} \
  build
