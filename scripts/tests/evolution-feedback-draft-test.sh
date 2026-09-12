#!/usr/bin/env bash
# Regression tests for scripts/evolution-feedback-draft.py.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/evolution-feedback-draft.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-feedback-draft.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/feedback"
cat > "$TMP/feedback/2026-09-12-demo.md" <<'MD'
# Thread snapshot
## User inputs

### turn 1
```
帮我看下这个页面
```

### turn 2
```
输入问号没有反应，应该是快捷键拦截了
```

### turn 3
```
build 报错: missing symbol
```
MD

OUT="$TMP/drafts.json"
FIRST="$("$TOOL" discover --feedback-dir "$TMP/feedback" --out "$OUT")"
[[ "$FIRST" == *"+2 new, total=2"* ]] || { echo "FAIL first discover: $FIRST" >&2; exit 1; }
SECOND="$("$TOOL" discover --feedback-dir "$TMP/feedback" --out "$OUT")"
[[ "$SECOND" == *"+0 new, total=2"* ]] || { echo "FAIL dedupe: $SECOND" >&2; exit 1; }
LIST="$("$TOOL" list --out "$OUT")"
[[ "$(echo "$LIST" | wc -l | tr -d ' ')" == "2" ]] || { echo "FAIL list: $LIST" >&2; exit 1; }
RENDER="$("$TOOL" render --out "$OUT")"
[[ "$RENDER" == *"快捷键拦截"* && "$RENDER" == *"missing symbol"* ]] || { echo "FAIL render: $RENDER" >&2; exit 1; }

# 建议生成: 分类 + 现有测试 section 匹配 + 幂等。
SUGGEST="$("$TOOL" suggest --out "$OUT" --testmain "$ROOT/Sources/TapgoTests/TestMain.swift")"
[[ "$SUGGEST" == *"sections=199"* || "$SUGGEST" == *"sections="* ]] || { echo "FAIL suggest: $SUGGEST" >&2; exit 1; }
python3 - "$OUT" <<'PY'
import json, sys
drafts = json.load(open(sys.argv[1]))["drafts"]
by_title = {d["title"]: d for d in drafts}
ui = next(d for t, d in by_title.items() if "快捷键" in t)
reg = next(d for t, d in by_title.items() if "报错" in t)
assert ui["suggestionKind"] == "ui", ui
assert ui["candidateSections"], ui
assert "TapgoTests --filter" in ui["suggestedCheck"], ui
assert reg["suggestionKind"] == "regression", reg
PY
SECOND_SUGGEST="$("$TOOL" suggest --out "$OUT" --testmain "$ROOT/Sources/TapgoTests/TestMain.swift")"
[[ "$SECOND_SUGGEST" == *"0 field update(s)"* ]] || { echo "FAIL suggest idempotence: $SECOND_SUGGEST" >&2; exit 1; }
RENDER2="$("$TOOL" render --out "$OUT")"
[[ "$RENDER2" == *"suggested check"* ]] || { echo "FAIL render suggestion: $RENDER2" >&2; exit 1; }

echo "evolution-feedback-draft tests: 9 passed, 0 failed"
