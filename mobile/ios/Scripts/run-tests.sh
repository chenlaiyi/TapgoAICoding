#!/usr/bin/env bash
# 在本机 (即使只有 CommandLineTools, 无 iOS SDK) 跑 iOS 端测试。
# 任何移动端协议字段改动必须通过此脚本, 防止两端 MobilePairing.swift 漂移。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
IOS_DIR="$ROOT/mobile/ios"
TS=$(date +%s)

echo "[1/4] 校验 MobilePairing 同步..."
"$IOS_DIR/Scripts/check-sync.sh"

echo "[2/4] swiftc 编译 MobilePairing 协议层测试..."
BIN_PROTO=/tmp/tapgo_pairing_proto_${TS}
(cd "$IOS_DIR" && swiftc -emit-executable -o "$BIN_PROTO" \
  Tests/MobilePairingProtocolTests.swift \
  Sources/MobilePairing.swift)

echo "[3/4] swiftc 编译 PairingStore + MobileRemoteLink 测试..."
BIN_STORE=/tmp/tapgo_pairing_store_${TS}
BIN_REMOTE=/tmp/tapgo_remote_${TS}
(cd "$IOS_DIR" && swiftc -emit-executable -o "$BIN_STORE" \
  Tests/PairingStoreTests.swift \
  Sources/MobilePairing.swift \
  Sources/PairingStore.swift \
  Sources/PairingKeychain.swift \
  Sources/PairingLink.swift \
  Sources/MobileRemoteLink.swift)
(cd "$IOS_DIR" && swiftc -emit-executable -o "$BIN_REMOTE" \
  Tests/MobileRemoteLinkTests.swift \
  Sources/MobileRemoteLink.swift)

echo "[4/4] 运行测试..."
PROTO_RC=0
STORE_RC=0
REMOTE_RC=0
"$BIN_PROTO" || PROTO_RC=$?
"$BIN_STORE" || STORE_RC=$?
"$BIN_REMOTE" || REMOTE_RC=$?
rm -f "$BIN_PROTO" "$BIN_STORE" "$BIN_REMOTE"

if [[ $PROTO_RC -ne 0 ]]; then
  echo "MobilePairing 协议测试失败 (exit=$PROTO_RC)" >&2
  exit $PROTO_RC
fi
if [[ $STORE_RC -ne 0 ]]; then
  echo "PairingStore 测试失败 (exit=$STORE_RC)" >&2
  exit $STORE_RC
fi
if [[ $REMOTE_RC -ne 0 ]]; then
  echo "MobileRemoteLink 测试失败 (exit=$REMOTE_RC)" >&2
  exit $REMOTE_RC
fi
echo "✅ iOS 全部测试通过 (协议层 + PairingStore + MobileRemoteLink)"
