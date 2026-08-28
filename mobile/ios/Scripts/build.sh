#!/usr/bin/env bash
# 构建 mobile/ios/TapgoTerminal.xcodeproj。
# 前置: macOS + Xcode 14+ + `brew install xcodegen` + `gem install xcodeproj`。
# 行为:
#   1. 跑 mobile/ios/Scripts/check-sync.sh, 失败即退出
#   2. `xcodegen generate` 生成 .xcodeproj (已有则跳过)
#   3. `xcodebuild -scheme TapgoTerminal -destination 'generic/platform=iOS Simulator' build`
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IOS_DIR="$ROOT/mobile/ios"
PROJ="$IOS_DIR/TapgoTerminal.xcodeproj"

echo "[1/3] 校验 MobilePairing 协议同步..."
"$IOS_DIR/Scripts/check-sync.sh"

echo "[2/3] 生成 Xcode 工程..."
if [[ ! -d "$PROJ" ]]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "缺少 xcodegen：brew install xcodegen" >&2
    exit 2
  fi
  (cd "$IOS_DIR" && xcodegen generate)
fi

echo "[3/3] xcodebuild..."
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "缺少 xcodebuild：请装 Xcode 后重试 (App Store -> Xcode)" >&2
  exit 2
fi
xcodebuild \
  -project "$PROJ" \
  -scheme TapgoTerminal \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$IOS_DIR/build" \
  CODE_SIGNING_ALLOWED=NO \
  build
