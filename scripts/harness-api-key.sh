#!/usr/bin/env bash
# harness-api-key.sh — 从 codex config.toml 提取 launchd daemon 需要的 bearer。
#
# 规则（v0.5.319 修）：
#   1. 优先取 `[model_providers.deepseek]` 段里的 `experimental_bearer_token`；
#   2. 跳过注释行（模板里有一行注释形式的 `# experimental_bearer_token …`）；
#   3. 接受**任意** token 前缀 —— 旧实现只认 `sk-cp-`，供应商精简成 DeepSeek 后
#      配置里是 `sk-…`，会导致 `install-harness-daemon.sh` 直接报「找不到 API key」。
#
# 用法: harness-api-key.sh <config.toml>
# 退出码: 0 成功（key 打到 stdout）/ 1 找不到 / 2 用法错误
set -uo pipefail

CONFIG="${1:-}"
if [[ -z "$CONFIG" ]]; then
  echo "usage: harness-api-key.sh <config.toml>" >&2
  exit 2
fi
if [[ ! -f "$CONFIG" ]]; then
  echo "harness-api-key: 文件不存在: $CONFIG" >&2
  exit 1
fi

KEY="$(awk '
  /^\[/ { in_ds = ($0 == "[model_providers.deepseek]") }
  /^[[:space:]]*#/ { next }
  /experimental_bearer_token[[:space:]]*=/ {
    line = $0
    sub(/^[^"]*"/, "", line); sub(/".*$/, "", line)
    if (in_ds && ds == "") { ds = line }
    if (first == "") { first = line }
  }
  END { print (ds != "" ? ds : first) }
' "$CONFIG")"

if [[ -z "$KEY" ]]; then
  echo "harness-api-key: $CONFIG 里没有可用的 experimental_bearer_token" >&2
  exit 1
fi
printf '%s' "$KEY"
