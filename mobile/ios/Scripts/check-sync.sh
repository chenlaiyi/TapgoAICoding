#!/usr/bin/env bash
# 强制保持 mobile/ios/Sources/MobilePairing.swift 与 Sources/TapgoCore/MobilePairing.swift
# 的协议层字节级一致 (忽略 iOS 副本末尾的 "iOS 工程自包含副本" 注释块)。
# 在任何一边改动 MobilePairing 时, 必须同步另一边, 否则此脚本非零退出。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CORE="$ROOT/Sources/TapgoCore/MobilePairing.swift"
IOS="$ROOT/mobile/ios/Sources/MobilePairing.swift"

if [[ ! -f "$CORE" || ! -f "$IOS" ]]; then
  echo "check-sync: 缺少 MobilePairing.swift (core=$CORE ios=$IOS)" >&2
  exit 2
fi

# 1) 剥离 iOS 副本中 // MARK: - iOS 工程自包含副本 之后的所有内容。
# 2) 把末尾的空行 (若有) 一并去掉, 让 stripped 与 Core 字节级一致。
ios_stripped=$(mktemp)
trap 'rm -f "$ios_stripped"' EXIT
awk '
  /^\/\/ MARK: - iOS 工程自包含副本/ { found=1; next }
  found==1 { next }
  { print }
' "$IOS"   | awk 'BEGIN{trailing=0} {lines[NR]=$0; if($0!="")trailing=NR} END{for(i=1;i<=trailing;i++)print lines[i]}'   > "$ios_stripped"

# 如果 Core 末尾没有 newline, 给 stripped 补一个, 保证字节级一致
if [[ "$(tail -c 1 "$CORE" | wc -l | tr -d ' ')" == "0" ]]; then
  printf '\n' >> "$ios_stripped"
fi

core_hash=$(shasum -a 256 "$CORE" | awk '{print $1}')
ios_hash=$(shasum -a 256 "$ios_stripped" | awk '{print $1}')

if [[ "$core_hash" != "$ios_hash" ]]; then
  echo "MobilePairing.swift 同步失败：" >&2
  diff "$CORE" "$ios_stripped" >&2 || true
  echo "" >&2
  echo "请让 ../../Sources/TapgoCore/MobilePairing.swift 与本文件保持一致 (忽略底部 MARK 注释)。" >&2
  exit 1
fi

echo "MobilePairing 同步校验通过 (sha256=${core_hash:0:12}\u2026)"
