#!/usr/bin/env bash
# Regression tests for scripts/evolution-preflight.sh (fixture repo + mocked tools).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/evolution-preflight.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-preflight-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASSED=0; FAILED=0
ok()  { PASSED=$((PASSED + 1)); }
bad() { FAILED=$((FAILED + 1)); echo "FAIL: $1" >&2; }
expect_eq() { [[ "$2" == "$3" ]] && ok || bad "$1 (expected [$2] got [$3])"; }
expect_grep() { grep -q -- "$2" "$3" 2>/dev/null && ok || bad "$1 (no match '$2')"; }
expect_no_grep() { ! grep -q -- "$2" "$3" 2>/dev/null && ok || bad "$1 (unexpected '$2')"; }

# ---------- fixture：一个含 tag、bare origin、关键文件的假仓库 ----------
REPO="$TMP/repo"
mkdir -p "$REPO"/{scripts,evolution,AppBuilder} "$TMP/bin"
for f in scripts/evolve.sh scripts/deploy-fleet.sh scripts/health-check.sh \
         scripts/worktree-verify.sh scripts/build-app.sh scripts/evolution-records.py; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$REPO/$f"
done
printf '# backlog\n' > "$REPO/evolution/BACKLOG.md"
printf '{"version":1,"paths":["scripts/evolve.sh"]}\n' > "$REPO/evolution/protected-paths.json"
printf '<plist><dict><key>CFBundleShortVersionString</key><string>0.5.1</string></dict></plist>\n' > "$REPO/AppBuilder/Info.plist"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name Test
git -C "$REPO" add -A
git -C "$REPO" commit -qm baseline
git -C "$REPO" tag -a v0.5.1 -m v0.5.1
git -C "$REPO" init -q --bare "$TMP/origin.git"
git -C "$REPO" remote add origin "$TMP/origin.git"
git -C "$REPO" push -q -u origin main --tags

# ---------- mocks ----------
cat > "$TMP/bin/xcrun" <<'MOCK'
#!/usr/bin/env bash
[[ "${XC_RC:-0}" == "0" ]] || exit 1
if [[ "$*" == *"--show-sdk-path"* ]]; then echo /tmp/fake-sdk; exit 0; fi
echo "Apple Swift version 6.3.3 (fake)"
MOCK
mkdir -p /tmp/fake-sdk
cat > "$TMP/bin/gh" <<'MOCK'
#!/usr/bin/env bash
[[ "${GH_RC:-0}" == "0" ]] || { echo "not logged in" >&2; exit 1; }
echo "github.com"
echo "  ✓ Logged in to github.com account tester (keyring)"
MOCK
cat > "$TMP/bin/ssh" <<'MOCK'
#!/usr/bin/env bash
[[ "${SSH_RC:-0}" == "0" ]] || exit 255
echo "${!#}"
MOCK
cat > "$TMP/bin/df" <<'MOCK'
#!/usr/bin/env bash
echo "Filesystem   1G-blocks Used Available Capacity iused     ifree %iused  Mounted on"
echo "/dev/disk3s1       228  137       10    94% 1688846 727040600    0%   /System/Volumes/Data"
MOCK
chmod +x "$TMP/bin/"*

run_preflight() { # run_preflight <log> [args...]
  local log="$1"; shift
  set +e
  EVOLVE_PREFLIGHT_ROOT="$REPO" \
  EVOLVE_PREFLIGHT_XCRUN="$TMP/bin/xcrun" \
  EVOLVE_PREFLIGHT_GH="$TMP/bin/gh" \
  EVOLVE_PREFLIGHT_SSH="$TMP/bin/ssh" \
  EVOLVE_PREFLIGHT_DF="$TMP/bin/df" \
  GH_RC="${GH_RC:-0}" SSH_RC="${SSH_RC:-0}" XC_RC="${XC_RC:-0}" \
  EVOLVE_STATE_DIR="$TMP/state" \
    "$TOOL" "$@" > "$log" 2>&1
  RC=$?
  set -e
}

# 1. 本地模式：全部通过
run_preflight "$TMP/local.log" --mode local
expect_eq "local: exit 0" "0" "$RC"
expect_grep "local: summary ok" "PREFLIGHT OK" "$TMP/local.log"
expect_grep "local: next tag computed" "tag:v0.5.2" "$TMP/local.log"
expect_no_grep "local: no gh check" "gh-auth" "$TMP/local.log"
expect_no_grep "local: no ssh check" "ssh:" "$TMP/local.log"

# 2. 发布模式：远端/上游/gh/三机全通过
run_preflight "$TMP/publish.log" --mode publish --remote origin
expect_eq "publish: exit 0" "0" "$RC"
expect_grep "publish: remote reachable" "OK   remote" "$TMP/publish.log"
expect_grep "publish: upstream matches" "HEAD == origin/main" "$TMP/publish.log"
expect_grep "publish: gh auth ok" "gh-auth" "$TMP/publish.log"
expect_grep "publish: fleet host jkmacmini checked" "ssh:jkmacmini" "$TMP/publish.log"
expect_grep "publish: fleet host mbp checked" "ssh:chenlaiyi@100.100.191.111" "$TMP/publish.log"

# 3. gh 未登录 -> 失败
GH_RC=1 run_preflight "$TMP/gh.log" --mode publish --remote origin
expect_eq "gh: exit 12" "12" "$RC"
expect_grep "gh: failure reported" "FAIL gh-auth" "$TMP/gh.log"
expect_grep "gh: summary failed" "PREFLIGHT FAILED" "$TMP/gh.log"

# 4. 磁盘空间不足 -> 失败
run_preflight "$TMP/disk.log" --mode local --min-free-gb 9999
expect_eq "disk: exit 12" "12" "$RC"
expect_grep "disk: reported" "FAIL disk" "$TMP/disk.log"

# 5. 三机不可达 -> 失败；--skip-ssh 只降级为 warn
SSH_RC=255 run_preflight "$TMP/ssh.log" --mode publish --remote origin
expect_eq "ssh: exit 12" "12" "$RC"
expect_grep "ssh: failure reported" "FAIL ssh:jkmacmini" "$TMP/ssh.log"
run_preflight "$TMP/skipssh.log" --mode publish --remote origin --skip-ssh
expect_eq "skip-ssh: exit 0" "0" "$RC"
expect_grep "skip-ssh: warned" "WARN ssh" "$TMP/skipssh.log"

# 6. 远端不可达 -> 失败
run_preflight "$TMP/remote.log" --mode publish --remote "$TMP/does-not-exist.git"
expect_eq "remote: exit 12" "12" "$RC"
expect_grep "remote: failure reported" "FAIL remote" "$TMP/remote.log"

# 7. SDK 缺失 -> 失败
XC_RC=1 run_preflight "$TMP/sdk.log" --mode local
expect_eq "sdk: exit 12" "12" "$RC"
expect_grep "sdk: failure reported" "FAIL sdk" "$TMP/sdk.log"

# 8. tag 冲突 -> 失败；--expect-existing-tag 则要求存在
git -C "$REPO" tag -a v0.5.2 -m v0.5.2
run_preflight "$TMP/tag.log" --mode local --next-version 0.5.2
expect_eq "tag: exit 12" "12" "$RC"
expect_grep "tag: conflict reported" "本地 tag 已存在" "$TMP/tag.log"
run_preflight "$TMP/tag-resume.log" --mode local --next-version 0.5.2 --expect-existing-tag
expect_eq "tag: resume ok" "0" "$RC"
expect_grep "tag: resume accepted" "本地已存在" "$TMP/tag-resume.log"

# 9. JSON 输出可解析且带失败计数
GH_RC=1 run_preflight "$TMP/json.log" --mode publish --remote origin --json
expect_eq "json: exit 12" "12" "$RC"
python3 - "$TMP/json.log" <<'PY' && ok || bad "json: payload shape"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["mode"] == "publish", data
assert data["failed"] >= 1, data
assert any(c["name"] == "gh-auth" and c["level"] == "fail" for c in data["checks"]), data
PY

echo "evolution-preflight tests: $PASSED passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
