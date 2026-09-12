#!/usr/bin/env bash
# End-to-end drill for scripts/deploy-fleet.sh（EVO-045）。
#
# 真实链路里 deploy-fleet 是「发布已公开之后」才跑的最后一环，此前只有 stub 覆盖。
# 这里用合成 .app + fake ssh/scp（在本机执行远端 heredoc）真正跑一遍：
#   本地安装/回读 → 远端安装/回读 → 界面断言管道 → 失败传播 → 目标过滤
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/deploy-fleet.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-deploy-fleet.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
VERSION="9.9.9"

# 安全护栏：这个演练会真的执行远端 heredoc（fake ssh 在本机跑），必须确保
# 所有安装目标都在临时目录里；否则可能覆盖真实 /Applications（v0.5.302 曾误试）。
case "$TMP" in
  /var/folders/*|/tmp/*|/private/var/folders/*) ;;
  *) echo "REFUSING: TMP=$TMP 不在临时目录" >&2; exit 2 ;;
esac
for required in EVOLVE_FLEET_LOCAL_DEST EVOLVE_FLEET_REMOTE_APP; do :; done

PASSED=0; FAILED=0
ok()  { PASSED=$((PASSED + 1)); }
bad() { FAILED=$((FAILED + 1)); echo "FAIL: $1" >&2; }
expect_eq() { [[ "$2" == "$3" ]] && ok || bad "$1 (expected [$2] got [$3])"; }
expect_grep() { grep -q -- "$2" "$3" 2>/dev/null && ok || bad "$1 (no match '$2')"; }
expect_no_grep() { ! grep -q -- "$2" "$3" 2>/dev/null && ok || bad "$1 (unexpected '$2')"; }

mkdir -p "$TMP/bin"

# ---------- 合成 .app（版本 9.9.9）----------
APP="$TMP/build/Tapgo AICoding.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
cp /bin/echo "$APP/Contents/MacOS/TapgoAICoding"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>9.9.9</string>
<key>CFBundleVersion</key><string>9.9.9</string>
</dict></plist>
PLIST

# ---------- fake 工具 ----------
cat > "$TMP/bin/ssh" <<'FAKE'
#!/usr/bin/env bash
# ssh -o X host bash -s -- [args...]：把 stdin 当远端脚本在本机执行，并留痕。
args=()
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -o) shift 2 ;;
    bash) shift; [[ "${1:-}" == "-s" ]] && shift; [[ "${1:-}" == "--" ]] && shift; args=("$@"); break ;;
    *) shift ;;
  esac
done
stdin_file="$(mktemp)"
cat > "$stdin_file"
{ echo "=== ssh stdin ==="; cat "$stdin_file"; } >> "$SSH_STDIN_LOG"
{ echo "=== ssh args ==="; printf '[%s]\n' ${args[@]+"${args[@]}"}; } >> "${SSH_ARGS_LOG:-/dev/null}"
# 忠实模拟真实 ssh：把参数用空格拼成一条远端命令（含空格的参数会被重新分词）
bash -c "bash -s -- ${args[*]-}" < "$stdin_file"
FAKE

cat > "$TMP/bin/scp" <<'FAKE'
#!/usr/bin/env bash
# scp -q -o X <local> <host>:<remote> → 直接本地拷贝
src=""; dest=""; skip_next=0
for arg in "$@"; do
  if [[ "$skip_next" -eq 1 ]]; then skip_next=0; continue; fi
  case "$arg" in
    -q) continue ;;
    -o|-P|-i) skip_next=1; continue ;;
    *) if [[ -z "$src" ]]; then src="$arg"; elif [[ -z "$dest" ]]; then dest="$arg"; fi ;;
  esac
done
[[ -n "$src" && -n "$dest" ]] || { echo "fake scp: bad args" >&2; exit 2; }
mkdir -p "$(dirname "${dest##*:}")"
cp "$src" "${dest##*:}"
FAKE

cat > "$TMP/bin/scp-fail" <<'FAKE'
#!/usr/bin/env bash
echo "fake scp: forced failure" >&2
exit 1
FAKE

cat > "$TMP/bin/codesign" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE

cat > "$TMP/bin/open-noop" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE

cat > "$TMP/bin/pgrep-fake" <<'FAKE'
#!/usr/bin/env bash
echo 424242
FAKE

cat > "$TMP/bin/pgrep-none" <<'FAKE'
#!/usr/bin/env bash
exit 1
FAKE
chmod +x "$TMP/bin/"*

cat > "$TMP/restart.sh" <<'FAKE'
#!/usr/bin/env bash
echo "restart $*" >> "$RESTART_LOG"
FAKE
cat > "$TMP/ui-ok.sh" <<'FAKE'
#!/usr/bin/env bash
echo "UI-ASSERT-STUB OK $*"
exit 0
FAKE
cat > "$TMP/ui-fail.sh" <<'FAKE'
#!/usr/bin/env bash
echo "UI-ASSERT-STUB FAILED $*" >&2
exit 25
FAKE
chmod +x "$TMP/restart.sh" "$TMP/ui-ok.sh" "$TMP/ui-fail.sh"

# 统一环境（run_fleet 与内联用例共用）
FLEET_ENV_LIST=(
  "PATH=$TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  "SSH_STDIN_LOG=$TMP/ssh-stdin.log"
  "SSH_ARGS_LOG=$TMP/ssh-args.log"
  "RESTART_LOG=$TMP/restart.log"
  "EVOLVE_FLEET_APP=$APP"
  "EVOLVE_FLEET_LOCAL_DEST=$TMP/local/Applications/Tapgo AICoding.app"
  "EVOLVE_FLEET_REMOTE_APP=$TMP/remote.app"
  "EVOLVE_FLEET_SSH=$TMP/bin/ssh"
  "EVOLVE_FLEET_SCP=$TMP/bin/scp"
  "EVOLVE_FLEET_RESTART_SCRIPT=$TMP/restart.sh"
  "EVOLVE_FLEET_UI_ASSERT_SCRIPT=$TMP/ui-ok.sh"
  "EVOLVE_FLEET_RESTART_WAIT=0"
  "EVOLVE_FLEET_OPEN=$TMP/bin/open-noop"
  "EVOLVE_FLEET_PGREP=$TMP/bin/pgrep-fake"
  "EVOLVE_FLEET_TARGETS_OVERRIDE=fakehost:$TMP/fake-repo"
)

run_fleet() { # run_fleet <log> [args...]
  local log="$1"; shift
  set +e
  env "${FLEET_ENV_LIST[@]}" "$TOOL" "$@" > "$log" 2>&1
  RC=$?
  set -e
}

# ---------- 1. dry-run（不覆盖目标，验证真实三机列表）----------
set +e
EVOLVE_FLEET_APP="$APP" "$TOOL" --dry-run "$VERSION" > "$TMP/dry.log" 2>&1
RC=$?
set -e
expect_eq "dry-run: exit 0" "0" "$RC"
expect_grep "dry-run: local target" "\[local\] installing" "$TMP/dry.log"
expect_grep "dry-run: jkmacmini" "\[jkmacmini\] installing" "$TMP/dry.log"
expect_grep "dry-run: chenlaiyi" "chenlaiyi@100.100.191.111" "$TMP/dry.log"

# ---------- 2. 本地安装（不重启，跳过界面断言）----------
run_fleet "$TMP/local.log" --only local "$VERSION"
expect_eq "local install: exit 0" "0" "$RC"
expect_eq "local install: version landed" "$VERSION" \
  "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TMP/local/Applications/Tapgo AICoding.app/Contents/Info.plist")"
expect_grep "local install: restart deferred" "restart deferred" "$TMP/local.log"
expect_grep "local install: assert skipped" "UI assert skipped" "$TMP/local.log"

# ---------- 3. 本地重启 + 界面断言通过 ----------
rm -f "$TMP/restart.log"
run_fleet "$TMP/local-restart.log" --only local --restart-local "$VERSION"
expect_eq "local restart: exit 0" "0" "$RC"
expect_grep "local restart: restart script ran" "restart" "$TMP/restart.log"
expect_grep "local restart: ui assert passed" "UI assert passed" "$TMP/local-restart.log"

# ---------- 4. 本地界面断言失败 → 部署失败 ----------
set +e
env "${FLEET_ENV_LIST[@]}" EVOLVE_FLEET_UI_ASSERT_SCRIPT="$TMP/ui-fail.sh" \
  "$TOOL" --only local --restart-local "$VERSION" > "$TMP/local-fail.log" 2>&1
RC=$?
set -e
[[ "$RC" -ne 0 ]] && ok || bad "local ui assert failure must fail the deploy"
expect_grep "local ui assert failure: reason" "界面断言失败" "$TMP/local-fail.log"

# ---------- 5. 远端安装 + 界面断言管道 ----------
rm -f "$TMP/ssh-stdin.log"
run_fleet "$TMP/remote.log" --only fakehost "$VERSION"
expect_eq "remote install: exit 0" "0" "$RC"
expect_eq "remote install: version landed" "$VERSION" \
  "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$TMP/remote.app/Contents/Info.plist")"
expect_grep "remote install: verified line" "restart + version ${VERSION} verified" "$TMP/remote.log"
expect_grep "remote install: ui assert piped over ssh" "UI-ASSERT-STUB OK" "$TMP/ssh-stdin.log"
expect_grep "remote install: assert passed" "UI assert passed" "$TMP/remote.log"

# ---------- 6. EVOLVE_SKIP_UI_ASSERT=1 不喂断言脚本 ----------
rm -f "$TMP/ssh-stdin.log"
set +e
env "${FLEET_ENV_LIST[@]}" EVOLVE_SKIP_UI_ASSERT=1 \
  "$TOOL" --only fakehost "$VERSION" > "$TMP/skip.log" 2>&1
RC=$?
set -e
expect_eq "skip ui assert: exit 0" "0" "$RC"
expect_no_grep "skip ui assert: no assert script piped" "UI-ASSERT-STUB" "$TMP/ssh-stdin.log"
expect_grep "skip ui assert: reported" "UI assert skipped" "$TMP/skip.log"

# ---------- 7. 远端进程缺失 → 安装阶段就失败（不再误报 verified）----------
rm -f "$TMP/ssh-stdin.log"
set +e
env "${FLEET_ENV_LIST[@]}" EVOLVE_FLEET_PGREP="$TMP/bin/pgrep-none" \
  EVOLVE_FLEET_REMOTE_APP="$TMP/remote-nopid.app" \
  "$TOOL" --only fakehost "$VERSION" > "$TMP/nopid.log" 2>&1
RC=$?
set -e
[[ "$RC" -ne 0 ]] && ok || bad "missing remote PID must fail the deploy"
expect_grep "missing pid: none reported" "PID=none" "$TMP/nopid.log"
expect_grep "missing pid: install failure surfaced" "远端安装/重启失败" "$TMP/nopid.log"
expect_no_grep "missing pid: must not claim verified" "verified" "$TMP/nopid.log"

# ---------- 8. scp 失败 → 立刻失败，且不再误报 verified ----------
set +e
env "${FLEET_ENV_LIST[@]}" EVOLVE_FLEET_SCP="$TMP/bin/scp-fail" \
  EVOLVE_FLEET_REMOTE_APP="$TMP/remote-scpfail.app" \
  "$TOOL" --only fakehost "$VERSION" > "$TMP/scpfail.log" 2>&1
RC=$?
set -e
[[ "$RC" -ne 0 ]] && ok || bad "scp failure must fail the deploy"
expect_grep "scp failure: reported" "传输失败" "$TMP/scpfail.log"
expect_no_grep "scp failure: must not claim verified" "verified" "$TMP/scpfail.log"

# ---------- 9. 目标过滤 ----------
run_fleet "$TMP/both.log" --exclude fakehost --only fakehost "$VERSION"
expect_eq "only+exclude: rejected" "2" "$RC"

run_fleet "$TMP/allfiltered.log" --exclude fakehost "$VERSION"
expect_eq "all remotes filtered: exit 0" "0" "$RC"
expect_no_grep "all remotes filtered: no unbound error" "unbound variable" "$TMP/allfiltered.log"
expect_no_grep "all remotes filtered: no remote install" "\[fakehost\] installing" "$TMP/allfiltered.log"

# ---------- 10. 含空格的远端覆盖必须被拒绝（ssh 会拆参数）----------
set +e
env "${FLEET_ENV_LIST[@]}" EVOLVE_FLEET_REMOTE_APP="/tmp/bad path/Tapgo AICoding.app" \
  "$TOOL" --only fakehost "$VERSION" > "$TMP/badpath.log" 2>&1
RC=$?
set -e
expect_eq "spaced remote path: rejected" "2" "$RC"
expect_grep "spaced remote path: reason" "不能含空格" "$TMP/badpath.log"
expect_grep "remote default lives in remote script" "/Applications/Tapgo AICoding.app" "$ROOT/scripts/deploy-fleet.sh"

# ---------- 11. 哨兵：不传覆盖时用非空 "-"，避免空参数被 ssh 吃掉 ----------
expect_grep "sentinel: passed as 4th arg" 'REMOTE_APP_OVERRIDE:--' "$ROOT/scripts/deploy-fleet.sh"
expect_grep "sentinel: remote maps dash to default" 'APP="${4:--}"' "$ROOT/scripts/deploy-fleet.sh"
expect_grep "sentinel: default lives in remote script" '/Applications/Tapgo AICoding.app' "$ROOT/scripts/deploy-fleet.sh"
expect_grep "remote app override must be space-free" '不能含空格' "$ROOT/scripts/deploy-fleet.sh"

# ---------- 12. 远端路径不像 .app → 远端守卫拒绝 ----------
set +e
env "${FLEET_ENV_LIST[@]}" EVOLVE_FLEET_REMOTE_APP="$TMP/not-an-app" \
  "$TOOL" --only fakehost "$VERSION" > "$TMP/badapp.log" 2>&1
RC=$?
set -e
[[ "$RC" -ne 0 ]] && ok || bad "non-.app remote path must fail"
expect_grep "non-.app path: guard message" "远端 App 路径异常" "$TMP/badapp.log"

# ---------- 13. 护栏自检：所有安装目标都在临时目录 ----------
GUARD_OK=1
for entry in "${FLEET_ENV_LIST[@]}"; do
  case "$entry" in
    EVOLVE_FLEET_LOCAL_DEST=*|EVOLVE_FLEET_REMOTE_APP=*)
      value="${entry#*=}"
      [[ "$value" == "$TMP"/* ]] || { GUARD_OK=0; echo "  越界目标: $value" >&2; }
      ;;
  esac
done
[[ "$GUARD_OK" -eq 1 ]] && ok || bad "演练目标必须全部位于 $TMP 之内"

echo "deploy-fleet tests: $PASSED passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
