#!/usr/bin/env bash
# Regression tests for scripts/evolution-deps.sh (SDK / codex 路径探测).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
# shellcheck source=scripts/evolution-deps.sh
source "$ROOT/scripts/evolution-deps.sh"

PASSED=0; FAILED=0
ok()  { PASSED=$((PASSED + 1)); }
bad() { FAILED=$((FAILED + 1)); echo "FAIL: $1" >&2; }
expect_eq() { [[ "$2" == "$3" ]] && ok || bad "$1 (expected [$2] got [$3])"; }
expect_grep() { grep -q -- "$2" "$3" 2>/dev/null && ok || bad "$1 (no match '$2')"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-deps-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# 1) SDK：显式 TAPGO_SDK 优先
expect_eq "explicit TAPGO_SDK wins" "macosx15.4" "$(TAPGO_SDK=macosx15.4 evo_detect_sdk)"

# 2) SDK：偏好值已安装时直接用
expect_eq "preferred installed sdk" "macosx15.4" "$(EVOLVE_SDK_PREFERRED=macosx15.4 evo_detect_sdk)"

# 3) SDK：偏好缺失 → 回退到本机最新已装并告警
set +e
RECLAIMED="$(EVOLVE_SDK_PREFERRED=macosx99.9 evo_detect_sdk 2> "$TMP/fallback.err")"
RC=$?
set -e
expect_eq "fallback exit 0" "0" "$RC"
printf '%s' "$RECLAIMED" | grep -Eq '^macosx[0-9]+(\.[0-9]+)?$' && ok || bad "fallback sdk name: $RECLAIMED"
expect_grep "fallback warns" "回退到" "$TMP/fallback.err"

# 4) SDK：全部不可用 → 明确报错
mkdir -p "$TMP/bin"
cat > "$TMP/bin/xcrun" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
chmod +x "$TMP/bin/xcrun"
set +e
PATH="$TMP/bin:/usr/bin:/bin" EVOLVE_SDK_PREFERRED=macosx99.9 evo_detect_sdk > "$TMP/no-sdk.out" 2> "$TMP/no-sdk.err"
RC=$?
set -e
expect_eq "no sdk exit 1" "1" "$RC"
expect_grep "no sdk message" "找不到可用的 macOS SDK" "$TMP/no-sdk.err"

# 5) codex：EVOLVE_CODEX_BIN / PATH / 常见位置
expect_eq "codex override" "/bin/echo" "$(EVOLVE_CODEX_BIN=/bin/echo evo_detect_codex)"
set +e
EVOLVE_CODEX_BIN="$TMP/not-here/codex" evo_detect_codex > "$TMP/codex-bad.out" 2> "$TMP/codex-bad.err"
RC=$?
set -e
expect_eq "bad codex override exit 1" "1" "$RC"
expect_grep "bad codex message" "不可执行" "$TMP/codex-bad.err"

mkdir -p "$TMP/path-bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/path-bin/codex"; chmod +x "$TMP/path-bin/codex"
expect_eq "codex found on PATH" "$TMP/path-bin/codex" \
  "$(PATH="$TMP/path-bin:/usr/bin:/bin" evo_detect_codex)"
expect_eq "codex fallback to known location" "/opt/homebrew/bin/codex" \
  "$(PATH="/usr/bin:/bin" evo_detect_codex 2>/dev/null || echo none)"

# 6) evo_require_tool
evo_require_tool git && ok || bad "require_tool git"
set +e
evo_require_tool definitely-not-a-real-tool "test hint" 2> "$TMP/req.err"
RC=$?
set -e
expect_eq "missing tool exit 1" "1" "$RC"
expect_grep "missing tool message" "缺少依赖命令 definitely-not-a-real-tool" "$TMP/req.err"

# 7) evo_deps_report 两个字段都在
REPORT="$(evo_deps_report)"
[[ "$REPORT" == sdk=* && "$REPORT" == *"codex="* ]] && ok || bad "deps report: $REPORT"

# 8) 静态守卫：链路脚本不再硬编码 SDK / codex 路径
HARDCODED_SDK="$(grep -rln -- ':-macosx26.5' scripts/ 2>/dev/null \
  | grep -v 'scripts/evolution-deps.sh' | grep -v 'tests/evolution-deps-test.sh' || true)"
expect_eq "sdk default has a single source of truth" "" "$HARDCODED_SDK"
HARDCODED_CODEX="$(grep -rln '/opt/homebrew/bin/codex' scripts/ 2>/dev/null \
  | grep -v 'scripts/evolution-deps.sh' | grep -v 'tests/evolution-deps-test.sh' || true)"
expect_eq "no hardcoded codex outside deps module" "" "$HARDCODED_CODEX"
expect_grep "harness plist uses placeholder" "__CODEX_BIN__" scripts/launchd/com.tapgo.aicoding.harness.plist
expect_grep "installer substitutes placeholder" "__CODEX_BIN__" scripts/install-harness-daemon.sh
expect_grep "evolve uses deps module" "evolution-deps.sh" scripts/evolve.sh
expect_grep "build uses deps module" "evolution-deps.sh" scripts/build-app.sh
expect_grep "run-all uses deps module" "evolution-deps.sh" scripts/tests/run-all.sh
expect_grep "preflight uses deps module" "evolution-deps.sh" scripts/evolution-preflight.sh
expect_grep "worktree-verify uses deps module" "evolution-deps.sh" scripts/worktree-verify.sh
expect_grep "rollback-drill uses deps module" "evolution-deps.sh" scripts/rollback-drill.sh
if grep -q -- '-sdk macosx' evolution/feedback/registry.json; then
  bad "registry 检查仍硬编码 -sdk"
else
  ok
fi

# ROOT 可被 EVOLVE_*_REPO_ROOT/EVOLVE_PREFLIGHT_ROOT 覆盖为 fixture 的脚本，
# 必须从自身目录加载 deps 模块，否则测试/fixture 环境直接 source 失败。
for script in scripts/evolution-preflight.sh scripts/rollback-drill.sh scripts/worktree-verify.sh; do
  if grep -q 'source "$ROOT/scripts/evolution-deps.sh"' "$script"; then
    bad "$script 从可覆盖的 ROOT 加载 deps（应用 SCRIPT_DIR）"
  else
    ok
  fi
done

echo "evolution-deps tests: $PASSED passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
