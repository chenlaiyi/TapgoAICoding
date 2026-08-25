#!/usr/bin/env bash
# restart-and-resume.sh — Gracefully restart Tapgo AICoding.
#
# What this does:
#   1. Find the running Tapgo AICoding process (the GUI app, not
#      the test runner / `swift run TapgoAICoding` dev mode).
#   2. Send SIGTERM; wait up to 5s for graceful exit.
#   3. If still alive: SIGKILL.
#   4. Re-open the .app bundle (the fresh binary from the latest
#      `./scripts/build-app.sh` / latest tag).
#   5. Echo the evolution_state.json path so the resumed session
#      knows where to read its "memory" from.
#
# Usage:
#   ./scripts/restart-and-resume.sh
#
# Why a dedicated script:
#   - `pkill -f TapgoAICoding` is dangerous (matches the swift build
#     invocation too, on some shells). We match only the bundled
#     .app binary path.
#   - macOS apps don't always respond to SIGTERM cleanly; we give
#     them a window before SIGKILL.
#   - `open <bundle>` is the canonical way to launch a .app — it
#     registers with LaunchServices and the Dock properly.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${ROOT}/Tapgo AICoding.app"
STATE="${HOME}/Library/Application Support/Tapgo AICoding/state/evolution_state.json"

if [[ ! -d "$APP" ]]; then
  echo "ERROR: ${APP} not found. Run ./scripts/build-app.sh first." >&2
  exit 1
fi

# Match only the binary inside the .app bundle, not `swift run TapgoAICoding`.
APP_BIN="${APP}/Contents/MacOS/TapgoAICoding"

echo "==> Looking for running app binary at ${APP_BIN}"
PIDS="$(pgrep -f "${APP_BIN}" || true)"

if [[ -n "$PIDS" ]]; then
  echo "==> Sending SIGTERM to: ${PIDS}"
  for pid in $PIDS; do
    kill -TERM "$pid" 2>/dev/null || true
  done

  # Give it up to 5s to die gracefully.
  for i in 1 2 3 4 5; do
    sleep 1
    if ! kill -0 $PIDS 2>/dev/null; then
      echo "==> Exited after ${i}s"
      break
    fi
  done

  # Anything still alive gets SIGKILL.
  STILL="$(pgrep -f "${APP_BIN}" || true)"
  if [[ -n "$STILL" ]]; then
    echo "==> Forcing SIGKILL on: ${STILL}"
    for pid in $STILL; do
      kill -KILL "$pid" 2>/dev/null || true
    done
    sleep 1
  fi
else
  echo "==> No running app found (clean start)"
fi

echo "==> Launching: ${APP}"
open "$APP"

# macOS `open` returns before the app is fully ready; give it a moment
# so the user / next agent turn sees the new session as soon as the
# harness finishes initializing.
sleep 2

echo
echo "==================================================="
echo "  RESTART COMPLETE"
echo "==================================================="
echo "  App:           ${APP}"
echo "  State file:    ${STATE}"
echo
if [[ -f "$STATE" ]]; then
  echo "  Latest tag:    $(grep -E '"tag"' "$STATE" | sed 's/.*: "//;s/".*//')"
  echo "  Evolution:     $(grep -E '"evolutionNote"' "$STATE" | sed 's/.*: "//;s/".*//')"
else
  echo "  WARN: state file not found — first evolution hasn't run yet."
fi
echo
echo "  Next: send a new turn to the resumed thread. The new session will"
echo "        read EVOLUTION.md + the state file to recover context."
echo "==================================================="
