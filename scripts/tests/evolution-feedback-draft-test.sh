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

echo "evolution-feedback-draft tests: 5 passed, 0 failed"
