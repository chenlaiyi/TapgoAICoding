#!/usr/bin/env bash
# harness-daemon-probe.sh — 校验 TapgoHarness daemon 是否真的在服务。
#
# 只读探针：不改任何文件、不重启任何服务，只连 socket 发一条 JSON-RPC
# `initialize`。除了「有没有响应」，还会验证**多客户端并发**——v0.5.319
# 之前 daemon 是单客户端串行，第二个连接会一直排队，App 侧表现为
# `Harness RPC 超时：initialize`（30 秒）。
#
# 用法:
#   scripts/harness-daemon-probe.sh [socket-path]
#
# 退出码: 0 通过 / 2 用法或环境 / 3 socket 缺失 / 4 单连接 initialize 超时 /
#         5 并发被阻塞（第二个连接拿不到响应）
set -uo pipefail

SOCKET="${1:-$HOME/Library/Application Support/Tapgo AICoding/run/harness.sock}"
TIMEOUT="${TAPGO_PROBE_TIMEOUT:-8}"
PYTHON="${TAPGO_PROBE_PYTHON:-python3}"

if [[ ! -e "$SOCKET" ]]; then
  echo "PROBE FAIL socket 不存在: $SOCKET（App 会回落到 LocalHarnessTransport）" >&2
  exit 3
fi
if ! command -v "$PYTHON" >/dev/null 2>&1; then
  echo "PROBE FAIL 缺少 python3（探针需要）" >&2
  exit 2
fi

"$PYTHON" - "$SOCKET" "$TIMEOUT" <<'PY'
import json, socket, sys, time

path, timeout = sys.argv[1], float(sys.argv[2])

def dial():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    s.connect(path)
    return s

def initialize(s):
    s.sendall((json.dumps({
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {"clientInfo": {"name": "tapgo-aicoding-daemon-probe",
                                  "title": "TapgoHarness probe", "version": "probe"}},
    }) + "\n").encode())
    buf = b""
    while b"\n" not in buf:
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
    return buf.splitlines()[0].decode(errors="replace") if buf else ""

# 1) 单连接
try:
    a = dial()
except Exception as exc:  # noqa: BLE001 - 探针只关心成败
    print(f"PROBE FAIL 连接 socket 失败: {exc}")
    sys.exit(4)
t0 = time.time()
try:
    line = initialize(a)
except socket.timeout:
    line = ""
elapsed = time.time() - t0
if "userAgent" not in line:
    print(f"PROBE FAIL 单连接 initialize 无有效响应（{elapsed:.2f}s）: {line[:120] or '超时'}")
    a.close()
    sys.exit(4)
print(f"PROBE OK 单连接 initialize {elapsed:.2f}s")

# 2) 并发：A 保持连接不发请求，B 必须同样拿到响应
try:
    b = dial()
except Exception as exc:  # noqa: BLE001
    print(f"PROBE FAIL 第二条连接失败: {exc}")
    a.close()
    sys.exit(5)
t1 = time.time()
try:
    line2 = initialize(b)
except socket.timeout:
    line2 = ""
elapsed2 = time.time() - t1
a.close(); b.close()
if "userAgent" not in line2:
    print(f"PROBE FAIL 并发被阻塞：A 占线时 B 的 initialize 无响应（{elapsed2:.2f}s）—— daemon 仍是单客户端串行")
    sys.exit(5)
print(f"PROBE OK 并发 initialize {elapsed2:.2f}s（A 占线时 B 仍被服务）")
PY
