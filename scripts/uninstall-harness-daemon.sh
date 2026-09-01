#!/usr/bin/env bash
# uninstall-harness-daemon.sh — 卸载 TapgoHarness daemon

set -euo pipefail
LABEL="com.tapgo.aicoding.harness"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
SOCKET_PATH="$HOME/Library/Application Support/Tapgo AICoding/run/harness.sock"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
[ -e "$PLIST_PATH" ] && unlink "$PLIST_PATH"
[ -e "$SOCKET_PATH" ] && unlink "$SOCKET_PATH"
echo "uninstalled: $LABEL"
