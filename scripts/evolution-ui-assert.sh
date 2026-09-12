#!/usr/bin/env bash
# evolution-ui-assert.sh — 断言"运行中的 App 界面真的可用、而且跑的是新版本"（EVO-039）。
#
# 为什么不用截图：ssh 会话没有 GUI/录屏权限。这里改用 App 自己的 H5 远程界面
# （token 存在 UserDefaults、端口 8723+、/api/state 带 appVersion），可以在任意
# 机器上无权限地证明界面栈真的活着，并区分"版本到位"与"界面可用"。
#
# 探针：
#   1. 进程      pgrep 找到 App 主进程
#   2. token     defaults read com.tapgo.aicoding tapgo.remote.token
#   3. 端口      lsof 找该 PID 的 LISTEN 端口（优先 8723..8733）
#   4. /api/state            HTTP 200 + JSON.appVersion == --expect-version + hostname/rev
#   5. /r/<token>            HTTP 200 且引用 app.js（H5 骨架可渲染）
#   6. /r/<token>/assets/app.js  HTTP 200 且含 --marker（默认 evolutionCard）
#   7. 无 token 路径          必须 403/404（鉴权仍然生效）
#
# 用法：
#   ./scripts/evolution-ui-assert.sh --expect-version 0.5.294
#   ssh host bash -s -- --expect-version 0.5.294 < scripts/evolution-ui-assert.sh
#
# 退出码：21 无进程 / 22 无 token / 23 无监听端口 / 24 状态接口失败 /
#         25 版本不一致 / 26 H5 骨架异常 / 27 资源缺少标记 / 28 鉴权回归
# 重试：EVOLVE_UI_ATTEMPTS（默认 6，每次间隔 1s；刚重启时 H5 端口可能还没绑好）
# 测试覆盖点：EVOLVE_UI_PID / TOKEN / PORT / ATTEMPTS / PGREP / DEFAULTS / LSOF / CURL
set -euo pipefail

EXPECT_VERSION=""
APP_PATH="${EVOLVE_UI_APP_PATH:-/Applications/Tapgo AICoding.app}"
BINARY_REL="Contents/MacOS/TapgoAICoding"
BUNDLE_ID="${EVOLVE_UI_BUNDLE_ID:-com.tapgo.aicoding}"
TOKEN_KEY="${EVOLVE_UI_TOKEN_KEY:-tapgo.remote.token}"
MARKER="${EVOLVE_UI_MARKER:-evolutionCard}"
PORT="${EVOLVE_UI_PORT:-}"
PID="${EVOLVE_UI_PID:-}"
TOKEN="${EVOLVE_UI_TOKEN:-}"
TIMEOUT="${EVOLVE_UI_TIMEOUT:-5}"
ATTEMPTS="${EVOLVE_UI_ATTEMPTS:-6}"
JSON=0

PGREP_BIN="${EVOLVE_UI_PGREP:-pgrep}"
DEFAULTS_BIN="${EVOLVE_UI_DEFAULTS:-defaults}"
LSOF_BIN="${EVOLVE_UI_LSOF:-lsof}"
CURL_BIN="${EVOLVE_UI_CURL:-curl}"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --expect-version) EXPECT_VERSION="${2:-}"; shift ;;
    --app-path) APP_PATH="${2:-}"; shift ;;
    --marker) MARKER="${2:-}"; shift ;;
    --port) PORT="${2:-}"; shift ;;
    --timeout) TIMEOUT="${2:-}"; shift ;;
    --json) JSON=1 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "ERROR: unexpected arg: $1" >&2; exit 2 ;;
  esac
  shift
done

fail() { # fail <code> <message>
  echo "UI ASSERT FAILED (${1}): ${2}" >&2
  exit "$1"
}

result() { # result <field> <value>
  local field="$1" value="$2"
  if [[ "$JSON" -eq 1 ]]; then
    RESULT_FIELDS+=("$field=$value")
  else
    echo "UI ASSERT ${field}: $value"
  fi
}

RESULT_FIELDS=()
BIN="$APP_PATH/$BINARY_REL"

# 1) 进程
if [[ -z "$PID" ]]; then
  PID="$("$PGREP_BIN" -f "$BIN" 2>/dev/null | head -1 || true)"
fi
[[ -n "$PID" ]] || fail 21 "找不到运行中的 App 进程（${BIN}）"

# 2) H5 鉴权 token
if [[ -z "$TOKEN" ]]; then
  TOKEN="$("$DEFAULTS_BIN" read "$BUNDLE_ID" "$TOKEN_KEY" 2>/dev/null || true)"
fi
[[ -n "$TOKEN" ]] || fail 22 "读不到 H5 token（defaults read ${BUNDLE_ID} ${TOKEN_KEY}）"

# 3+4) 端口与 /api/state：刚重启时 H5 服务可能还没绑好，带重试
FIXED_PORT="$PORT"
STATE_JSON=""
BASE=""
attempt=1
while [[ "$attempt" -le "$ATTEMPTS" ]]; do
  if [[ -z "$PORT" ]]; then
    PORTS="$("$LSOF_BIN" -nP -a -p "$PID" -iTCP -sTCP:LISTEN 2>/dev/null \
      | awk 'NR > 1 {print $9}' | sed -n 's/.*:\([0-9][0-9]*\)$/\1/p' | sort -u || true)"
    if [[ -n "$PORTS" ]]; then
      PORT="$(printf '%s\n' "$PORTS" | awk '$1 >= 8723 && $1 <= 8733' | head -1 || true)"
      [[ -n "$PORT" ]] || PORT="$(printf '%s\n' "$PORTS" | head -1)"
    fi
  fi
  if [[ -n "$PORT" ]]; then
    BASE="http://127.0.0.1:${PORT}/r/${TOKEN}"
    STATE_JSON="$("$CURL_BIN" -fsS --max-time "$TIMEOUT" "${BASE}/api/state" 2>/dev/null || true)"
    [[ -n "$STATE_JSON" ]] && break
  fi
  PORT="$FIXED_PORT"
  attempt=$((attempt + 1))
  if [[ "$attempt" -le "$ATTEMPTS" ]]; then sleep 1; fi
done
[[ -n "$PORT" ]] || fail 23 "PID ${PID} 在 ${ATTEMPTS} 次尝试内没有监听端口（H5 服务未起）"
[[ -n "$STATE_JSON" ]] || fail 24 "取不到 ${BASE:-http://127.0.0.1/}/api/state（端口 ${PORT} 未提供 H5 状态）"
APP_VERSION="$(printf '%s' "$STATE_JSON" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit("bad-json")
print(data.get("appVersion") or "")
' 2>/dev/null || true)"
[[ -n "$APP_VERSION" ]] || fail 24 "/api/state 不是合法 JSON 或缺 appVersion"
HOSTNAME_SEEN="$(printf '%s' "$STATE_JSON" | python3 -c '
import json, sys
data = json.load(sys.stdin)
print("%s|%s" % (data.get("hostname") or "", data.get("rev")))
' 2>/dev/null || true)"
[[ "$HOSTNAME_SEEN" == *"|"* ]] || fail 24 "/api/state 缺 hostname/rev 字段"
if [[ -n "$EXPECT_VERSION" && "$APP_VERSION" != "$EXPECT_VERSION" ]]; then
  fail 25 "运行中的界面版本 ${APP_VERSION} != 期望 ${EXPECT_VERSION}（App 未真正重启）"
fi
result "version" "$APP_VERSION"
result "pid" "$PID"
result "port" "$PORT"

# 5) H5 骨架
PAGE="$("$CURL_BIN" -fsS --max-time "$TIMEOUT" "${BASE}/" 2>/dev/null || true)"
[[ -n "$PAGE" ]] || fail 26 "${BASE}/ 返回空（H5 骨架不可用）"
printf '%s' "$PAGE" | grep -q "app.js" || fail 26 "H5 骨架未引用 app.js"
printf '%s' "$PAGE" | grep -q "<html" || fail 26 "H5 骨架不是 HTML"
result "page" "ok(${#PAGE}B)"

# 6) H5 资源含目标界面标记
ASSET="$("$CURL_BIN" -fsS --max-time "$TIMEOUT" "${BASE}/assets/app.js" 2>/dev/null || true)"
[[ -n "$ASSET" ]] || fail 27 "${BASE}/assets/app.js 返回空"
printf '%s' "$ASSET" | grep -q -- "$MARKER" || fail 27 "app.js 缺少界面标记 '${MARKER}'"
result "marker" "$MARKER"

# 7) 鉴权：无 token 路径必须被拒
CODE="$("$CURL_BIN" -sS -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" \
  "http://127.0.0.1:${PORT}/" 2>/dev/null || echo 000)"
case "$CODE" in
  403|404) ;;
  *) fail 28 "无 token 请求返回 ${CODE}，鉴权可能失效" ;;
esac
result "auth" "rejected(${CODE})"

if [[ "$JSON" -eq 1 ]]; then
  python3 - "$APP_VERSION" "$PID" "$PORT" "$MARKER" "$CODE" <<'PY'
import json, sys
version, pid, port, marker, code = sys.argv[1:6]
print(json.dumps({"appVersion": version, "pid": int(pid), "port": int(port),
                  "marker": marker, "unauthenticatedStatus": int(code)},
                 ensure_ascii=False))
PY
else
  echo "UI ASSERT OK version=${APP_VERSION} pid=${PID} port=${PORT} marker=${MARKER}"
fi
