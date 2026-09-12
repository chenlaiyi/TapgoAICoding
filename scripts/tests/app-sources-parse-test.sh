#!/usr/bin/env bash
# Gate: App target sources must at least parse.
#
# `swift run TapgoTests` 只编译 TapgoCore + 测试，不编译 TapgoAICoding(App)。
# 于是 App 里一个被 ASCII 引号截断的字符串（v0.5.295 真实踩过）能通过全部
# 单测，直到 evolve.sh 的 build 阶段才炸掉整轮发布。这里用 1.7s 的
# `swiftc -parse` 做语法门禁，把它提前到测试阶段。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/evolution-deps.sh"
SDK="${TAPGO_SDK:-$(evo_detect_sdk)}"

PASSED=0; FAILED=0
ok()  { PASSED=$((PASSED + 1)); }
bad() { FAILED=$((FAILED + 1)); echo "FAIL: $1" >&2; }

SOURCES=()
while IFS= read -r file; do
  [[ -n "$file" ]] && SOURCES+=("$file")
done < <(git ls-files 'Sources/TapgoAICoding/**/*.swift')
[[ "${#SOURCES[@]}" -gt 20 ]] && ok || bad "App target source list too small (${#SOURCES[@]})"

set +e
PARSE_OUT="$(xcrun -sdk "$SDK" swiftc -parse "${SOURCES[@]}" 2>&1)"
RC=$?
set -e
[[ "$RC" -eq 0 ]] && ok || { bad "App sources must parse (rc=$RC)"; printf '%s\n' "$PARSE_OUT" | grep "error:" | head -5 >&2; }

# Negative control：截断的字符串必须被这道门禁抓住
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-parse-gate.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
printf '%s\n' 'import Foundation' 'let broken = "oops"tail"' > "$TMP/broken.swift"
set +e
xcrun -sdk "$SDK" swiftc -parse "$TMP/broken.swift" >/dev/null 2>&1
RC=$?
set -e
[[ "$RC" -ne 0 ]] && ok || bad "negative control: broken source must fail parsing"

# 真实文件再抽样一次：EvolutionLogView 的 makeHistory 区域引号必须成对
VIEW="Sources/TapgoAICoding/Views/EvolutionLogView.swift"
python3 - "$VIEW" <<'PY' && ok || bad "makeHistory string literals must be quote-balanced"
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
start = next(i for i, l in enumerate(lines) if "private static func makeHistory()" in l)
end = next(i for i, l in enumerate(lines[start:], start) if "private static func makePlaybook" in l)
suspicious = [(i + 1, l.strip()[:80]) for i, l in enumerate(lines[start:end], start)
              if l.count('"') % 2 == 1]
if suspicious:
    print(suspicious[:3], file=sys.stderr)
    sys.exit(1)
PY

echo "app-sources-parse tests: $PASSED passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
