#!/usr/bin/env bash
# 强制保持 mobile/ios/Sources/ 协议层副本与 Sources/TapgoCore/ 字节级一致.
#
# 校验两个协议文件:
#   1. MobilePairing.swift (v0.5.5+) — iOS 副本末尾有 `// MARK: - iOS 工程自包含副本`
#      注释块 (两个 MARK 行, 开始 + 结束), 校验时剥离.
#   2. MobileRemoteLink.swift (v1.0.0+) — 同上.
#
# 任何一端协议字段改动必须同步另一端, 否则此脚本非零退出.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
IOS_DIR="$ROOT/mobile/ios"
CORE_DIR="$ROOT/Sources/TapgoCore"
MARKER="// MARK: - iOS 工程自包含副本"

fail=0
check_pair() {
  local name="$1"
  local core="$CORE_DIR/${name}.swift"
  local ios="$IOS_DIR/Sources/${name}.swift"

  if [[ ! -f "$core" ]]; then
    echo "check-sync: 缺少 $core" >&2
    fail=1; return
  fi
  if [[ ! -f "$ios" ]]; then
    echo "check-sync: 缺少 $ios" >&2
    fail=1; return
  fi

  # 剥离 iOS 副本中两个 MARK 标记之间的内容.
  # 第一个 MARK 是"开始", 第二个 MARK 是"结束", 之间的注释块剥掉.
  # 之后是真正的源码, 应与 Core 真源字节级一致.
  local ios_stripped
  ios_stripped=$(mktemp)
  awk -v marker="$MARKER" '
    BEGIN { in_block = 0 }
    index($0, marker) > 0 {
      if (in_block == 0) { in_block = 1; next }
      else { in_block = 0; next }
    }
    in_block == 1 { next }
    { print }
  ' "$ios" > "$ios_stripped"

  # 末尾空行 trim, Core 末尾 newline 兜底.
  awk 'BEGIN{trailing=0} {lines[NR]=$0; if($0!="")trailing=NR} END{for(i=1;i<=trailing;i++)print lines[i]}' "$ios_stripped" > "${ios_stripped}.tmp" && mv "${ios_stripped}.tmp" "$ios_stripped"

  if [[ "$(tail -c 1 "$core" | wc -l | tr -d ' ')" == "0" ]]; then
    printf '\n' >> "$ios_stripped"
  fi

  local core_hash ios_hash
  core_hash=$(shasum -a 256 "$core" | awk '{print $1}')
  ios_hash=$(shasum -a 256 "$ios_stripped" | awk '{print $1}')

  if [[ "$core_hash" != "$ios_hash" ]]; then
    echo "$name.swift 同步失败：" >&2
    diff "$core" "$ios_stripped" >&2 || true
    fail=1
  else
    echo "$name 同步校验通过 (sha256=${core_hash:0:12}…)"
  fi
  rm -f "$ios_stripped"
}

check_pair MobilePairing
check_pair MobileRemoteLink

if [[ $fail -ne 0 ]]; then
  exit 1
fi
