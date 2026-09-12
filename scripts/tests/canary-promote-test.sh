#!/usr/bin/env bash
# Drill for scripts/canary-promote.sh（EVO-046）。
#
# canary 提升是"Release 已建但仍是 draft、appcast 未发布"的中间态收口动作：
# 推 appcast → 解除 draft → 部署其余机器。此前只有 stub 覆盖，这里在 fixture
# 仓库 + 假 gh/deploy 上真跑它的分支（推送失败/草稿失败/部署失败都必须显式失败）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/canary-promote.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-canary-promote.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
VERSION="9.9.9"; TAG="v${VERSION}"; CANARY_HOST="jkmacmini"

PASSED=0; FAILED=0
ok()  { PASSED=$((PASSED + 1)); }
bad() { FAILED=$((FAILED + 1)); echo "FAIL: $1" >&2; }
expect_eq() { [[ "$2" == "$3" ]] && ok || bad "$1 (expected [$2] got [$3])"; }
expect_grep() { grep -q -- "$2" "$3" 2>/dev/null && ok || bad "$1 (no match '$2')"; }
expect_no_grep() { ! grep -q -- "$2" "$3" 2>/dev/null && ok || bad "$1 (unexpected '$2')"; }

REPO="$TMP/repo"; ORIGIN="$TMP/origin.git"
mkdir -p "$REPO/AppBuilder/dist/$TAG"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name Test
printf 'base\n' > "$REPO/base.txt"
git -C "$REPO" add -A && git -C "$REPO" commit -qm base
git -C "$REPO" init -q --bare "$ORIGIN"
git -C "$REPO" remote add origin "$ORIGIN"
git -C "$REPO" push -q -u origin main
printf '<appcast version="9.9.9" rev="1" />\n' > "$REPO/AppBuilder/dist/$TAG/appcast.xml"

cat > "$TMP/gh" <<'FAKE'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_LOG"
case "$1 $2" in
  "release view")
    [[ "${GH_VIEW_RC:-0}" == "0" ]] || exit 1
    exit 0 ;;
  "release edit")
    [[ "${GH_EDIT_RC:-0}" == "0" ]] || exit 1
    exit 0 ;;
esac
exit 0
FAKE

cat > "$TMP/deploy.sh" <<'FAKE'
#!/usr/bin/env bash
echo "deploy $*" >> "$DEPLOY_LOG"
[[ "${DEPLOY_RC:-0}" == "0" ]] || exit 1
exit 0
FAKE
chmod +x "$TMP/gh" "$TMP/deploy.sh"

run_canary() { # run_canary <log> [args...]
  local log="$1"; shift
  set +e
  EVOLVE_CANARY_REPO_ROOT="$REPO" \
  EVOLVE_CANARY_REMOTE="origin" \
  EVOLVE_CANARY_GH="${CANARY_GH:-$TMP/gh}" \
  EVOLVE_CANARY_DEPLOY_SCRIPT="$TMP/deploy.sh" \
  GH_LOG="$TMP/gh.log" DEPLOY_LOG="$TMP/deploy.log" \
  GH_VIEW_RC="${GH_VIEW_RC:-0}" GH_EDIT_RC="${GH_EDIT_RC:-0}" DEPLOY_RC="${DEPLOY_RC:-0}" \
    "$TOOL" "$@" > "$log" 2>&1
  RC=$?
  set -e
}

# ---------- 1. 参数缺失 ----------
run_canary "$TMP/usage.log" "$VERSION"
expect_eq "missing host: exit 2" "2" "$RC"
expect_grep "missing host: usage" "usage: canary-promote.sh" "$TMP/usage.log"

# ---------- 2. 缺 canary appcast ----------
rm -f "$REPO/AppBuilder/dist/$TAG/appcast.xml"
run_canary "$TMP/noappcast.log" "$VERSION" "$CANARY_HOST"
expect_eq "missing appcast: exit 3" "3" "$RC"
expect_grep "missing appcast: reason" "canary appcast missing" "$TMP/noappcast.log"

# ---------- 3. 正常提升 ----------
printf '<appcast version="9.9.9" rev="2" />\n' > "$REPO/AppBuilder/dist/$TAG/appcast.xml"
BEFORE="$(git -C "$REPO" rev-list --count HEAD)"
rm -f "$TMP/gh.log" "$TMP/deploy.log"
run_canary "$TMP/ok.log" "$VERSION" "$CANARY_HOST"
expect_eq "happy: exit 0" "0" "$RC"
expect_grep "happy: appcast published" "appcast.xml published for ${TAG}" "$TMP/ok.log"
expect_eq "happy: appcast copied to repo root" "<appcast version=\"9.9.9\" rev=\"2\" />" "$(cat "$REPO/appcast.xml")"
expect_eq "happy: one new commit" "$((BEFORE + 1))" "$(git -C "$REPO" rev-list --count HEAD)"
expect_eq "happy: pushed to origin" "$(git -C "$REPO" rev-parse HEAD)" "$(git -C "$ORIGIN" rev-parse main)"
expect_grep "happy: gh view called" "release view ${TAG}" "$TMP/gh.log"
expect_grep "happy: gh undraft called" "release edit ${TAG} --draft=false" "$TMP/gh.log"
expect_grep "happy: deploy remaining hosts" "deploy --exclude ${CANARY_HOST} ${VERSION}" "$TMP/deploy.log"
expect_grep "happy: final banner" "CANARY PROMOTED ${TAG} canary=${CANARY_HOST}" "$TMP/ok.log"

# ---------- 4. 重复提升：appcast 无变化 ----------
BEFORE="$(git -C "$REPO" rev-list --count HEAD)"
rm -f "$TMP/gh.log" "$TMP/deploy.log"
run_canary "$TMP/again.log" "$VERSION" "$CANARY_HOST"
expect_eq "idempotent: exit 0" "0" "$RC"
expect_grep "idempotent: appcast up to date" "already up to date" "$TMP/again.log"
expect_eq "idempotent: no extra commit" "$BEFORE" "$(git -C "$REPO" rev-list --count HEAD)"
expect_grep "idempotent: still deployed remaining hosts" "deploy --exclude" "$TMP/deploy.log"

# ---------- 5. appcast 推送失败 → exit 4，且不部署其余机器 ----------
printf '<appcast version="9.9.9" rev="3" />\n' > "$REPO/AppBuilder/dist/$TAG/appcast.xml"
mkdir -p "$ORIGIN/hooks"
cat > "$ORIGIN/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
while read -r old new ref; do
  [[ "$ref" == "refs/heads/main" ]] && { echo "main push rejected by test hook" >&2; exit 1; }
done
exit 0
HOOK
chmod +x "$ORIGIN/hooks/pre-receive"
rm -f "$TMP/deploy.log"
run_canary "$TMP/pushfail.log" "$VERSION" "$CANARY_HOST"
expect_eq "push failure: exit 4" "4" "$RC"
expect_grep "push failure: reason" "appcast.xml 推送失败" "$TMP/pushfail.log"
if [[ -s "$TMP/deploy.log" ]]; then bad "push failure: must not deploy remaining hosts"; else ok; fi
rm -f "$ORIGIN/hooks/pre-receive"
git -C "$REPO" push -q origin HEAD:main   # 补推，供后续用例使用

# ---------- 6. draft 提升失败 → exit 5 ----------
printf '<appcast version="9.9.9" rev="4" />\n' > "$REPO/AppBuilder/dist/$TAG/appcast.xml"
rm -f "$TMP/deploy.log"
GH_EDIT_RC=1 run_canary "$TMP/ghfail.log" "$VERSION" "$CANARY_HOST"
expect_eq "gh edit failure: exit 5" "5" "$RC"
expect_grep "gh edit failure: reason" "release edit" "$TMP/ghfail.log"
if [[ -s "$TMP/deploy.log" ]]; then bad "gh edit failure: must not deploy"; else ok; fi
git -C "$REPO" push -q origin HEAD:main 2>/dev/null || true

# ---------- 7. Release 不存在 → 提示后继续部署 ----------
printf '<appcast version="9.9.9" rev="5" />\n' > "$REPO/AppBuilder/dist/$TAG/appcast.xml"
rm -f "$TMP/deploy.log"
GH_VIEW_RC=1 run_canary "$TMP/noview.log" "$VERSION" "$CANARY_HOST"
expect_eq "release missing: exit 0" "0" "$RC"
expect_grep "release missing: note" "跳过 draft 提升" "$TMP/noview.log"
expect_grep "release missing: still deploys" "deploy --exclude" "$TMP/deploy.log"

# ---------- 8. 无 gh → 提示后继续部署 ----------
printf '<appcast version="9.9.9" rev="6" />\n' > "$REPO/AppBuilder/dist/$TAG/appcast.xml"
rm -f "$TMP/deploy.log"
CANARY_GH="$TMP/no-such-gh" run_canary "$TMP/nogh.log" "$VERSION" "$CANARY_HOST"
expect_eq "no gh: exit 0" "0" "$RC"
expect_grep "no gh: note" "未找到 gh" "$TMP/nogh.log"
expect_grep "no gh: still deploys" "deploy --exclude" "$TMP/deploy.log"

# ---------- 9. 其余机器部署失败 → exit 6 ----------
printf '<appcast version="9.9.9" rev="7" />\n' > "$REPO/AppBuilder/dist/$TAG/appcast.xml"
DEPLOY_RC=1 run_canary "$TMP/deployfail.log" "$VERSION" "$CANARY_HOST"
expect_eq "deploy failure: exit 6" "6" "$RC"
expect_grep "deploy failure: reason" "其余机器部署失败" "$TMP/deployfail.log"

echo "canary-promote tests: $PASSED passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
