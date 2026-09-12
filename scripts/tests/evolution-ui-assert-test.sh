#!/usr/bin/env bash
# Regression tests for scripts/evolution-ui-assert.sh（真实 HTTP 桩服务）.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/evolution-ui-assert.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-ui-assert.XXXXXX")"
PORT="${EVOLVE_UI_TEST_PORT:-18723}"
SERVER_PID=""
cleanup() {
  [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

PASSED=0; FAILED=0
ok()  { PASSED=$((PASSED + 1)); }
bad() { FAILED=$((FAILED + 1)); echo "FAIL: $1" >&2; }
expect_eq() { [[ "$2" == "$3" ]] && ok || bad "$1 (expected [$2] got [$3])"; }
expect_grep() { grep -q -- "$2" "$3" 2>/dev/null && ok || bad "$1 (no match '$2')"; }

# ---------- 桩服务：可切换版本/标记/鉴权/H5 骨架 ----------
cat > "$TMP/server.py" <<'PY'
import json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

TOKEN = "testtoken"
VERSION = os.environ.get("STUB_VERSION", "0.5.295")
MARKER = os.environ.get("STUB_MARKER", "evolutionCard")
PAGE_JS = os.environ.get("STUB_PAGE_JS", "1") == "1"
AUTH_CODE = int(os.environ.get("STUB_AUTH_CODE", "404"))

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code, body, content_type="text/html"):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == f"/r/{TOKEN}/api/state":
            body = json.dumps({"rev": 7, "hostname": "stub-mac", "appVersion": VERSION,
                               "linkVersion": 3})
            return self._send(200, body, "application/json")
        if self.path == f"/r/{TOKEN}/assets/app.js":
            return self._send(200, f"// {MARKER}\n", "application/javascript")
        if self.path in (f"/r/{TOKEN}", f"/r/{TOKEN}/"):
            scripts = '<script src="assets/app.js"></script>' if PAGE_JS else "<p>no scripts</p>"
            return self._send(200, f"<!DOCTYPE html><html><body>{scripts}</body></html>")
        return self._send(AUTH_CODE, "no token")

HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
PY

start_server() {
  STUB_VERSION="${STUB_VERSION:-0.5.295}" STUB_MARKER="${STUB_MARKER:-evolutionCard}" \
  STUB_PAGE_JS="${STUB_PAGE_JS:-1}" STUB_AUTH_CODE="${STUB_AUTH_CODE:-404}" \
    python3 "$TMP/server.py" "$PORT" &
  SERVER_PID=$!
  for _ in $(seq 1 40); do
    if curl -sS -o /dev/null --max-time 1 "http://127.0.0.1:${PORT}/r/testtoken/api/state" 2>/dev/null; then return 0; fi
    sleep 0.1
  done
  echo "FAIL: stub server did not start" >&2
  exit 1
}
start_server

run_tool() { # run_tool <log> [args...]
  local log="$1"; shift
  set +e
  EVOLVE_UI_PID=4242 EVOLVE_UI_TOKEN=testtoken EVOLVE_UI_PORT="$PORT" EVOLVE_UI_ATTEMPTS=1 \
    "$TOOL" "$@" > "$log" 2>&1
  RC=$?
  set -e
}

# 1. 正常路径
run_tool "$TMP/ok.log" --expect-version 0.5.295
expect_eq "ok: exit 0" "0" "$RC"
expect_grep "ok: version line" "UI ASSERT version: 0.5.295" "$TMP/ok.log"
expect_grep "ok: pid line" "UI ASSERT pid: 4242" "$TMP/ok.log"
expect_grep "ok: marker line" "UI ASSERT marker: evolutionCard" "$TMP/ok.log"
expect_grep "ok: auth rejected" "auth: rejected(404)" "$TMP/ok.log"
expect_grep "ok: summary" "UI ASSERT OK version=0.5.295" "$TMP/ok.log"

# 2. JSON 输出
run_tool "$TMP/json.log" --expect-version 0.5.295 --json
expect_eq "json: exit 0" "0" "$RC"
python3 - "$TMP/json.log" <<'PY' && ok || bad "json: payload"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["appVersion"] == "0.5.295", data
assert data["port"] == int(__import__("os").environ.get("EVOLVE_UI_TEST_PORT", "18723")), data
assert data["unauthenticatedStatus"] == 404, data
PY

# 3. 运行中的版本与期望不一致（版本到位但界面没重启）
run_tool "$TMP/version.log" --expect-version 0.5.999
expect_eq "version mismatch: exit 25" "25" "$RC"
expect_grep "version mismatch: reason" "App 未真正重启" "$TMP/version.log"

# 4. H5 资源缺少界面标记
kill "$SERVER_PID"; wait "$SERVER_PID" 2>/dev/null || true
STUB_MARKER="__absent__" start_server
run_tool "$TMP/marker.log" --expect-version 0.5.295
expect_eq "marker missing: exit 27" "27" "$RC"
expect_grep "marker missing: reason" "缺少界面标记" "$TMP/marker.log"

# 5. H5 骨架不引用 app.js
kill "$SERVER_PID"; wait "$SERVER_PID" 2>/dev/null || true
STUB_PAGE_JS="0" start_server
run_tool "$TMP/page.log" --expect-version 0.5.295
expect_eq "page broken: exit 26" "26" "$RC"
expect_grep "page broken: reason" "未引用 app.js" "$TMP/page.log"

# 6. 鉴权回归：无 token 也能拿到内容
kill "$SERVER_PID"; wait "$SERVER_PID" 2>/dev/null || true
STUB_AUTH_CODE="200" start_server
run_tool "$TMP/auth.log" --expect-version 0.5.295
expect_eq "auth regression: exit 28" "28" "$RC"
expect_grep "auth regression: reason" "鉴权可能失效" "$TMP/auth.log"

# 7. H5 服务没起（端口不通）
kill "$SERVER_PID"; wait "$SERVER_PID" 2>/dev/null || true; SERVER_PID=""
run_tool "$TMP/noport.log" --expect-version 0.5.295
expect_eq "no server: exit 24" "24" "$RC"
expect_grep "no server: reason" "取不到" "$TMP/noport.log"

# 8. 进程/token 缺失与参数校验
cat > "$TMP/fail-pgrep" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
cat > "$TMP/fail-defaults" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
chmod +x "$TMP/fail-pgrep" "$TMP/fail-defaults"
set +e
EVOLVE_UI_PID="" EVOLVE_UI_PGREP="$TMP/fail-pgrep" EVOLVE_UI_TOKEN="" \
  EVOLVE_UI_DEFAULTS="$TMP/fail-defaults" EVOLVE_UI_PORT="$PORT" \
  "$TOOL" --expect-version 0.5.295 > "$TMP/noproc.log" 2>&1; RC=$?
set -e
expect_eq "no process: exit 21" "21" "$RC"
expect_grep "no process: reason" "找不到运行中的 App 进程" "$TMP/noproc.log"

set +e
EVOLVE_UI_PID=4242 EVOLVE_UI_TOKEN="" EVOLVE_UI_DEFAULTS="$TMP/fail-defaults" EVOLVE_UI_PORT="$PORT" \
  "$TOOL" > "$TMP/notoken.log" 2>&1; RC=$?
set -e
expect_eq "no token: exit 22" "22" "$RC"
expect_grep "no token: reason" "读不到 H5 token" "$TMP/notoken.log"

set +e; "$TOOL" --bogus >/dev/null 2>&1; RC=$?; set -e
expect_eq "bad arg: exit 2" "2" "$RC"

echo "evolution-ui-assert tests: $PASSED passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
