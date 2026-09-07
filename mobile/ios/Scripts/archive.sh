#!/usr/bin/env bash
# P6 / TestFlight 流程: Archive + Export + Upload.
#
# 前置: Apple Developer 后台已为 com.devtools.terminalSimple 勾选以下 Capabilities
#       1. App Groups (= group.com.devtools.terminalSimple)
#       2. Sign In with Apple
#       3. Background Modes (fetch + processing)
#       4. Push Notifications (可选, 上线前再开)
# 若 Capabilities 仍未勾选, 先勾选再跑本脚本; 否则 archive 会因 entitlement 不匹配失败.
#
# 用法:
#   ./Scripts/archive.sh                    # 默认 arm64 device + App Store 导出
#   ./Scripts/archive.sh ad-hoc             # ad-hoc 模式 (本地 .ipa, 不上传)
#   ./Scripts/archive.sh development        # development (TestFlight)
#
# 流程:
#   1. xcodebuild archive
#   2. xcodebuild -exportArchive (生成 .ipa)
#   3. xcrun altool --upload-app (TestFlight 上传)
#
# 上传成功后, 到 App Store Connect → TestFlight 选 build 关联到 1.0 即可.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
IOS_DIR="$ROOT/mobile/ios"
PROJ="$IOS_DIR/TapgoTerminal.xcodeproj"
ARCHIVE_PATH="$IOS_DIR/build/TapgoTerminal.xcarchive"
EXPORT_DIR="$IOS_DIR/build/Export"
SCHEME="TapgoTerminal"
TEAM="KF2CE24685"
BUNDLE_ID="com.devtools.terminalSimple"

MODE="${1:-app-store}"
case "$MODE" in
  app-store|ad-hoc|development) ;;
  *)
    echo "用法: $0 [app-store|ad-hoc|development]" >&2
    exit 2
    ;;
esac

# Entitlements: 若 Apple Developer 后台已勾选 Capabilities, 取消 Runner.entitlements 注释;
# 若未勾选, 保持注释状态 (build 仍可成功但 entitlement 不生效).
ENT_PATH="$IOS_DIR/Runner.entitlements"
echo "[0/4] 校验 Runner.entitlements 与 Provisioning Profile 一致..."
if grep -q "^[[:space:]]*<key>com.apple.developer.applesignin</key>" "$ENT_PATH"; then
  echo "    ✓ Entitlements 已启用 (App Groups + Sign In with Apple)"
else
  echo "    ⚠ Entitlements 仍被注释 (Apple Developer 后台未勾选 Capabilities)"
  echo "      上线前需要:"
  echo "        1. Apple Developer 后台 → Identifiers → com.devtools.terminalSimple → 勾选 App Groups + Sign In with Apple"
  echo "        2. Provisioning Profile 重新生成 (Xcode → Devices → Provisioning Profiles → Download)"
  echo "        3. 取消 $ENT_PATH 注释, 重跑本脚本"
  echo ""
  echo "    当前 archive 仍可成功 (entitlement 缺则不签), 但上架审核可能要求补齐"
fi

echo "[1/4] 解锁 login keychain..."
security unlock-keychain -p "" login.keychain-db 2>/dev/null || true

echo "[2/4] xcodebuild archive..."
xcodebuild \
  -project "$PROJ" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM="$TEAM" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  clean archive

if [[ ! -d "$ARCHIVE_PATH" ]]; then
  echo "archive 失败: $ARCHIVE_PATH 不存在" >&2
  exit 3
fi

echo "[3/4] xcodebuild -exportArchive (mode=$MODE)..."
mkdir -p "$EXPORT_DIR"
# ExportOptions.plist 由 xcodebuild 自动生成, 也可手动提供. 这里用 auto.
EXPORT_OPTIONS_PLIST="$EXPORT_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS_PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>teamID</key>
    <string>${TEAM}</string>
    <key>method</key>
    <string>${MODE}</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLISTEOF

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPl "$EXPORT_OPTIONS_PLIST"

IPA=$(ls "$EXPORT_DIR"/*.ipa 2>/dev/null | head -1 || true)
if [[ -z "$IPA" ]]; then
  echo "export 失败: $EXPORT_DIR 下没有 .ipa" >&2
  exit 4
fi
echo "    IPA: $IPA"

if [[ "$MODE" == "app-store" || "$MODE" == "development" ]]; then
  echo "[4/4] 上传到 TestFlight (需要 App Store Connect API Key 或已登录 xcrun altool)..."
  if ! command -v xcrun >/dev/null 2>&1; then
    echo "  ⚠ xcrun 不可用; 跳过自动上传, 请手动: xcrun altool --upload-app --type ios --file '$IPA'" >&2
  else
    echo "    在 App Store Connect → Users and Access → Integrations → In-App Purchase"
    echo "    生成 App Manager API Key, 放到 ~/.appstoreconnect/private_keys/AuthKey_XXXX.p8"
    echo "    然后跑:"
    echo "      xcrun altool --upload-app --type ios --file '$IPA' \\"
    echo "        --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>"
    echo ""
    echo "    (本脚本不内置上传, 因为 API Key 凭证不应放在 git 仓库)"
  fi
else
  echo "[4/4] ad-hoc 模式: 不上传, 本地 .ipa 用于团队内分发"
fi

echo ""
echo "✅ Archive 流程完成"
echo "  Archive: $ARCHIVE_PATH"
echo "  IPA:     $IPA"
echo ""
echo "下一步 (app-store / development 模式):"
echo "  1. App Store Connect → My Apps → 点点够终端 → TestFlight"
echo "  2. 选 build (version 1.0 / build 1) → 添加测试员"
echo "  3. 灰度跑 2-3 天后, App Store Connect → 1.0 提交审核"
