#!/usr/bin/env bash
# EVO-054: 手机端 H5（app.js）执行级渲染测试。
#
# 用最小 DOM stub 在 node 里跑真实 app.js：注入 fixture 快照 → 真实 fetch 回调 →
# 真实 refresh()/render() → 断言渲染进 DOM 的文案与 hidden 语义。补的是此前只有
# `appJS.contains("…")` 字符串断言的盲区：键名写对但条件写反/分支写错也能被抓到。
#
# 共享 fixture: evolution/h5-fixtures/evolution-state.json
#   —— Swift 侧 Evolution: H5 field contract 会校验它仍是合法服务器 payload。
# 覆盖：完整渲染 / evolution 消失再恢复 / 漏斗与指标为空 / CSS hidden 不变量。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

NODE_BIN="${EVOLVE_NODE_BIN:-}"
if [[ -z "$NODE_BIN" ]] && command -v node >/dev/null 2>&1; then
  NODE_BIN="$(command -v node)"
fi
if [[ -z "$NODE_BIN" ]]; then
  echo "FAIL: 需要 node 才能跑 H5 渲染测试（brew install node，或设 EVOLVE_NODE_BIN=/path/to/node）" >&2
  exit 1
fi

OUT="$("$NODE_BIN" scripts/tests/evolution-h5-render.mjs 2>&1)" || {
  echo "$OUT"
  echo "FAIL: evolution-h5-render 有失败断言" >&2
  exit 1
}
echo "$OUT"

if ! echo "$OUT" | grep -q "evolution-h5-render tests: .* 0 failed"; then
  echo "FAIL: 未输出预期的汇总行（测试脚本可能提前退出）" >&2
  exit 1
fi
