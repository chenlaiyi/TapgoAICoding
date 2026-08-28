#!/usr/bin/env bash
# 在本机 (即使只有 CommandLineTools, 无 iOS SDK) 跑 iOS 端 MobilePairing 协议层测试。
# 任何移动端协议字段改动必须通过此脚本, 防止两端 MobilePairing.swift 漂移。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
IOS_DIR="$ROOT/mobile/ios"
BIN=/tmp/tapgo_pairing_tests_$(date +%s)

echo "[1/3] 校验 MobilePairing 同步..."
"$IOS_DIR/Scripts/check-sync.sh"

echo "[2/3] swiftc 编译..."
(cd "$IOS_DIR" && swiftc -emit-executable -o "$BIN" Tests/MobilePairingProtocolTests.swift Sources/MobilePairing.swift)

echo "[3/3] 运行测试..."
"$BIN"
rc=$?
rm -f "$BIN"
if [[ $rc -ne 0 ]]; then
  echo "iOS MobilePairing 协议测试失败 (exit=$rc)" >&2
  exit $rc
fi
echo "✅ iOS MobilePairing 协议测试通过"
