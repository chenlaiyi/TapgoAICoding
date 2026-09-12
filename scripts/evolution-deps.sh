#!/usr/bin/env bash
# evolution-deps.sh — 自进化链路的外部依赖探测（EVO-040）。
#
# 只定义函数，source 时无副作用；给 evolve.sh / build-app.sh / 测试与预检共用，
# 避免 SDK 与 codex 路径散落成十几处硬编码。
#
# 设计取舍：
#   * SDK 偏好 26.5 是历史原因（macOS 27 SDK 的 CommandLineTools Swift 缺 SwiftUI
#     宏插件，直接 build 会失败，见 build-app.sh 头部说明）。所以顺序是：
#       TAPGO_SDK 显式指定 → 偏好值（默认 macosx26.5，装了就用）→
#       本机最新已装 SDK → xcrun 默认 SDK
#     换机器/升级 SDK 时不会硬失败，但用非偏好 SDK 会在 stderr 打 WARNING。
#   * codex 路径同理：EVOLVE_CODEX_BIN → PATH → 常见安装位置。

# 已安装的 macOS SDK（新→旧），名字形如 macosx26.5。
evo_installed_sdks() {
  local dir version
  for dir in /Library/Developer/CommandLineTools/SDKs /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs; do
    [[ -d "$dir" ]] || continue
    for version in "$dir"/MacOSX*.sdk; do
      [[ -d "$version" ]] || continue
      version="$(basename "$version" .sdk)"
      version="${version#MacOSX}"
      [[ -n "$version" ]] || continue
      printf 'macosx%s\n' "$version"
    done
  done | sort -uVr
}

# evo_sdk_valid <sdk> → 0/1
evo_sdk_valid() {
  local sdk="${1:-}"
  [[ -n "$sdk" ]] || return 1
  xcrun -sdk "$sdk" --show-sdk-path >/dev/null 2>&1
}

# evo_detect_sdk — 打印选定的 SDK 名；全部失败时打印已安装列表并返回 1。
evo_detect_sdk() {
  local preferred="${EVOLVE_SDK_PREFERRED:-macosx26.5}"
  if [[ -n "${TAPGO_SDK:-}" ]]; then
    printf '%s\n' "$TAPGO_SDK"
    return 0
  fi
  if evo_sdk_valid "$preferred"; then
    printf '%s\n' "$preferred"
    return 0
  fi
  local candidate
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    if evo_sdk_valid "$candidate"; then
      echo "WARNING: 偏好 SDK ${preferred} 未安装，回退到 ${candidate}（EVOLVE_SDK_PREFERRED 可覆盖）" >&2
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(evo_installed_sdks)
  local default_version
  default_version="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
  if [[ -n "$default_version" ]] && evo_sdk_valid "macosx${default_version}"; then
    echo "WARNING: 未找到已安装 SDK，回退到 xcrun 默认 macosx${default_version}" >&2
    printf 'macosx%s\n' "$default_version"
    return 0
  fi
  echo "ERROR: 找不到可用的 macOS SDK。已安装：" >&2
  evo_installed_sdks | sed 's/^/    /' >&2
  return 1
}

# evo_detect_codex — 打印 codex 可执行文件路径；找不到返回 1。
evo_detect_codex() {
  local candidate path_codex=""
  if [[ -n "${EVOLVE_CODEX_BIN:-}" ]]; then
    if [[ -x "$EVOLVE_CODEX_BIN" ]]; then
      printf '%s\n' "$EVOLVE_CODEX_BIN"
      return 0
    fi
    echo "ERROR: EVOLVE_CODEX_BIN=${EVOLVE_CODEX_BIN} 不可执行" >&2
    return 1
  fi
  path_codex="$(command -v codex 2>/dev/null || true)"
  for candidate in "$path_codex" /opt/homebrew/bin/codex /usr/local/bin/codex "${HOME}/.local/bin/codex"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  echo "ERROR: 找不到 codex 可执行文件（查过 PATH、/opt/homebrew/bin、/usr/local/bin、~/.local/bin）" >&2
  return 1
}

# evo_require_tool <tool> [hint] → 0/1 并在缺失时打印可执行动作。
evo_require_tool() {
  local tool="${1:-}" hint="${2:-}"
  [[ -n "$tool" ]] || return 1
  if command -v "$tool" >/dev/null 2>&1; then
    return 0
  fi
  echo "ERROR: 缺少依赖命令 ${tool}${hint:+（${hint}）}" >&2
  return 1
}

# evo_deps_report — 供预检/诊断打印解析结果（缺 codex 只记 unknown，不算失败）。
evo_deps_report() {
  local sdk codex
  sdk="$(evo_detect_sdk 2>/dev/null || echo "unresolved")"
  codex="$(evo_detect_codex 2>/dev/null || echo "unresolved")"
  printf 'sdk=%s codex=%s\n' "$sdk" "$codex"
}
