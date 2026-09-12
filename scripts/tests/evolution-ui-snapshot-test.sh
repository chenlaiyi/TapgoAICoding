#!/usr/bin/env bash
# Offscreen render check + baseline pixel comparison for the evolution UI.
#
# 渲染在同一台机器上是确定的（实测两次逐字节一致），所以这里把当前渲染结果和
# evolution/ui-baseline/evolution-ui.png 比对，超过容差即视作 UI 回归。
# 有意改 UI 时用：./scripts/tests/evolution-ui-snapshot-test.sh --update-baseline
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-evolution-ui-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/evolution-ui.png"
BASELINE="${EVOLVE_UI_BASELINE:-$ROOT/evolution/ui-baseline/evolution-ui.png}"
TOOL="$ROOT/scripts/evolution-ui-diff.py"

PASSED=0; FAILED=0
ok()  { PASSED=$((PASSED + 1)); }
bad() { FAILED=$((FAILED + 1)); echo "FAIL: $1" >&2; }

RESULT="$("$ROOT/scripts/preview-evolution-ui.sh" "$OUT")"
[[ "$RESULT" == *"EVOLUTION UI VERIFY OK"* ]] && ok || bad "preview output: $RESULT"
[[ -f "$OUT" ]] && ok || bad "missing snapshot"
SIZE="$(stat -f%z "$OUT")"
[[ "$SIZE" -gt 10000 ]] && ok || bad "blank snapshot size=$SIZE"

if [[ "${1:-}" == "--update-baseline" ]]; then
  mkdir -p "$(dirname "$BASELINE")"
  cp "$OUT" "$BASELINE"
  echo "BASELINE UPDATED: $BASELINE（记得提交）"
  echo "evolution-ui-snapshot tests: $PASSED passed, $FAILED failed"
  exit 0
fi

# 基线必须存在，否则这个门禁等于没开
if [[ -f "$BASELINE" ]]; then ok; else bad "missing baseline $BASELINE（用 --update-baseline 生成）"; fi

# 正向：当前渲染 vs 基线
set +e
DIFF_OUT="$("$TOOL" compare "$BASELINE" "$OUT" --diff-out "$TMP/diff.png" 2>&1)"
RC=$?
set -e
[[ "$RC" -eq 0 ]] && ok || { bad "baseline compare rc=$RC out=$DIFF_OUT"; }
[[ "$DIFF_OUT" == *"UI DIFF OK"* ]] && ok || bad "diff output: $DIFF_OUT"

# 负向 1：尺寸/内容不同的候选必须失败（不依赖 Pillow）
cp "$OUT" "$TMP/broken.png"
sips -Z 200 "$TMP/broken.png" >/dev/null 2>&1   # 真改尺寸（追加字节 Pillow 会忽略）
set +e
"$TOOL" compare "$BASELINE" "$TMP/broken.png" > "$TMP/broken.log" 2>&1
RC=$?
set -e
[[ "$RC" -eq 1 ]] && ok || bad "size-mismatch candidate must fail (rc=$RC)"

# 负向 2：局部 UI 变化（200x20 条带 ≈ 0.11% 像素）超过容差必须失败
if python3 -c 'import PIL' >/dev/null 2>&1; then
  python3 - "$OUT" "$TMP/strip.png" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
im.paste((255, 0, 0), (100, 100, 300, 120))
im.save(sys.argv[2])
PY
  set +e
  "$TOOL" compare "$BASELINE" "$TMP/strip.png" --json > "$TMP/strip.json" 2> "$TMP/strip.err"
  RC=$?
  set -e
  [[ "$RC" -eq 1 ]] && ok || bad "local UI change must fail (rc=$RC)"
  python3 - "$TMP/strip.json" <<'PY' && ok || bad "strip diff payload"
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["passed"] is False, d
assert d["diffBBox"] == [100, 100, 300, 120], d
PY
else
  echo "NOTE: 未安装 Pillow，跳过局部差异对照组（仍做字节级/尺寸级比对）"
fi

echo "evolution-ui-snapshot tests: $PASSED passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
