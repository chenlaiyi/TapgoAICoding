#!/usr/bin/env bash
# Regression tests for scripts/evolution-metrics.py.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-evolution-metrics-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/evolution/versions"
cat > "$TMP/evolution/BACKLOG.md" <<'MD'
# Backlog
- [x] done item
- [ ] open item one
- [ ] open item two
MD
cat > "$TMP/evolution/versions/v0.5.1.json" <<'JSON'
{"version":"0.5.1","tag":"v0.5.1","date":"2026-09-01","scope":"mac","message":"m1","changes":["c"],"details":"d","why":"w","next":"n","testStatus":"— 100 passed, 0 failed —","commitSha":null}
JSON
cat > "$TMP/evolution/versions/v0.5.2.json" <<'JSON'
{"version":"0.5.2","tag":"v0.5.2","date":"2026-09-02","scope":"mac","message":"m2","changes":["c"],"details":"d","why":"w","next":"n","testStatus":"pending","commitSha":null}
JSON
cat > "$TMP/history.jsonl" <<'JSONL'
{"schemaVersion":3,"status":"published","version":"0.5.1","mode":"publish","builtAt":"2026-09-01T00:00:00Z","testStatus":"— 100 passed, 0 failed —","durationSeconds":600,"tokens":1000,"costUSD":0.5}
{"status":"committed","version":"0.5.2","mode":"publish","builtAt":"2026-09-02T00:00:00Z","testStatus":"— 200 passed, 0 failed —"}
{"status":"release_failed","version":"0.5.2","mode":"publish","builtAt":"2026-09-02T01:00:00Z","testStatus":"— 200 passed, 0 failed —"}
{"schemaVersion":5,"status":"published","version":"0.5.3","mode":"publish","builtAt":"2026-09-03T01:00:00Z","testStatus":"— 300 passed, 0 failed —","durationSeconds":900,"tokens":2000,"costUSD":1.5,"localApp":{"installed":"0.5.3","running":"0.5.1","stale":true}}
JSONL

cat > "$TMP/maintenance_history.jsonl" <<'JSONL'
{"ranAt":"2026-09-04T10:00:00Z","status":"ok","drill":{"status":"passed","reason":null},"archive":{"status":"passed","reason":null}}
{"ranAt":"2026-09-05T10:00:00Z","status":"failed","drill":{"status":"failed","reason":"remote tag v0.5.1 not found"},"archive":{"status":"passed","reason":null}}
JSONL

SUMMARY_OUT="$TMP/summary.json"
export SUMMARY_OUT
python3 "$ROOT/scripts/evolution-metrics.py" --root "$TMP" --history "$TMP/history.jsonl" \
  --out "$SUMMARY_OUT" --quiet >/dev/null
OUT="$(python3 "$ROOT/scripts/evolution-metrics.py" --root "$TMP" --history "$TMP/history.jsonl" --json)"
python3 - "$OUT" <<'PY'
import json, sys
m = json.loads(sys.argv[1])
assert m["recordCount"] == 2, m
assert m["iterations"] == 3, m
assert m["published"] == 2, m
assert m["failed"] == 1, m
assert abs(m["successRate"] - 2/3) < 1e-9, m
assert m["testPassedTotal"] == 600, m
assert m["openBacklog"] == 2 and m["doneBacklog"] == 1, m
assert m["medianCycleSeconds"] == 176400.0, m  # 49h between published v0.5.1 and v0.5.3
assert m["maintenanceRuns"] == 2, m
assert m["lastMaintenanceStatus"] == "failed", m
assert m["lastMaintenanceAt"] == "2026-09-05T10:00:00Z", m
assert m["lastMaintenanceReason"] == "remote tag v0.5.1 not found", m
# EVO-036：周期 P95 / MTTR / 单轮时长与成本
assert abs(m["p95CycleSeconds"] - 176400.0) < 1e-6, m
assert abs(m["maxCycleSeconds"] - 176400.0) < 1e-6, m
assert m["mttrSamples"] == 1, m
assert abs(m["mttrMedianSeconds"] - 86400.0) < 1e-6, m
assert m["unrecoveredFailures"] == 0, m
assert m["lastFailureVersion"] == "0.5.2", m
assert abs(m["lastRecoverySeconds"] - 86400.0) < 1e-6, m
assert m["runDurationSamples"] == 2, m
assert abs(m["runDurationMedianSeconds"] - 750.0) < 1e-6, m
assert abs(m["runDurationP95Seconds"] - 885.0) < 1e-6, m
assert m["runDurationTotalSeconds"] == 1500, m
assert m["runTokensTotal"] == 3000, m
assert m["runTokensMedian"] == 1500, m
assert abs(m["runCostUSDTotal"] - 2.0) < 1e-6, m
assert abs(m["lastRunCostUSD"] - 1.5) < 1e-6, m
assert m["localAppRunning"] == "0.5.1", m
assert m["localAppInstalled"] == "0.5.3", m
assert m["localAppStale"] is True, m

# EVO-047：--out 原子写 JSON 摘要（App/H5 只读）
import os, pathlib
summary = pathlib.Path(os.environ["SUMMARY_OUT"])
assert summary.exists(), summary
snap = json.loads(summary.read_text(encoding="utf-8"))
assert snap["p95CycleSeconds"] == m["p95CycleSeconds"], snap
assert snap["runDurationMedianSeconds"] == m["runDurationMedianSeconds"], snap
assert snap["latestRecord"]["version"] == "0.5.2", snap   # 记录真源是 evolution/versions/*.json
# 跨语言契约：App(EvolutionMetricsSummary) 读这些键，产物必须提供
for key in ("p95CycleSeconds", "mttrMedianSeconds", "mttrSamples", "runDurationMedianSeconds",
            "runTokensTotal", "runCostUSDTotal"):
    assert key in snap, (key, sorted(snap))
assert "localApp" in snap and snap["localApp"]["stale"] is True, snap.get("localApp")
assert m["lastRollbackDrillFullBuild"] is None, m   # fixture 无 drill 历史
print("evolution-metrics assertions: 28 passed, 0 failed")
PY
