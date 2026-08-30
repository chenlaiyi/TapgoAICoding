#!/usr/bin/env bash
# Wrap the SwiftPM-built TapgoAICoding binary into a double-clickable .app
# bundle.
#
# What this does:
#   1. swift build -c release (executable: TapgoAICoding)
#
# Toolchain note (v0.4.2+):
#   As of macOS 27 SDK, Apple's CommandLineTools Swift ships WITHOUT the
#   SwiftUI macros plugin (SwiftUIMacros.StateMacro / .Environment / etc.),
#   so a bare `swift build` against the default SDK errors out with
#   `external macro implementation type ... could not be found`. We pin
#   to SDK 26.5 which still ships the plugin, via:
#       xcrun -sdk macosx26.5 swift build ...
#   Override with:   TAPGO_SDK=macosx27.0 ./scripts/build-app.sh
#   Detect with:     xcrun --show-sdk-path  (check for missing SwiftUIMacros)
#   2. Creates Tapgo AICoding.app/Contents/{MacOS,Resources}/
#   3. Copies the binary, Info.plist, entitlements
#   4. Ad-hoc codesigns so Gatekeeper is lenient for local use
#
# Result: a real macOS application — drop it in /Applications, or just
# `open` from the project root.
#
# The resulting app reads/writes EXCLUSIVELY from
# ~/Library/Application Support/Tapgo AICoding/codex/ (independent of
# the official ~/.codex/). Run scripts/init-tapgo.sh first to set up
# that isolated Codex home.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ---------- SDK selection ----------
# Pick a Swift SDK that actually carries the SwiftUI macros plugin.
# Default = macosx26.5 (last SDK that ships the plugin via
# CommandLineTools). Override via TAPGO_SDK=macosx27.0 to try the
# bleeding edge — that build will fail until Apple re-adds the plugin.
TAPGO_SDK="${TAPGO_SDK:-macosx26.5}"
if ! xcrun -sdk "$TAPGO_SDK" --show-sdk-path >/dev/null 2>&1; then
  echo "ERROR: TAPGO_SDK=$TAPGO_SDK is not installed on this machine." >&2
  echo "  Installed SDKs:" >&2
  ls -1 /Library/Developer/CommandLineTools/SDKs/ 2>/dev/null | sed "s/^/    /" >&2
  exit 7
fi
SWIFT=(xcrun -sdk "$TAPGO_SDK" swift)
echo "==> Using SDK: $TAPGO_SDK (override via TAPGO_SDK=...)"

APP_DISPLAY_NAME="Tapgo AICoding"
APP_DIR_NAME="Tapgo AICoding"
APP_BUNDLE_DIR="${ROOT}/${APP_DIR_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
HELPER_ROOT_DIR="${RESOURCES_DIR}/computer-use-helper"
HELPER_APP_DIR="${HELPER_ROOT_DIR}/Tapgo Computer Use.app"
HELPER_CONTENTS_DIR="${HELPER_APP_DIR}/Contents"
HELPER_MACOS_DIR="${HELPER_CONTENTS_DIR}/MacOS"
HELPER_RESOURCES_DIR="${HELPER_CONTENTS_DIR}/Resources"

BIN_NAME="TapgoAICoding"
BIN_SRC="${ROOT}/.build/release/${BIN_NAME}"
PLIST_SRC="${ROOT}/AppBuilder/Info.plist"
ENTITLEMENTS_SRC="${ROOT}/AppBuilder/TapgoAICoding.entitlements"
HELPER_PLIST_SRC="${ROOT}/AppBuilder/ComputerUseHelper-Info.plist"
PKGINFO_SRC="${ROOT}/AppBuilder/PkgInfo"
ICNS_SRC="${ROOT}/AppBuilder/AppIcon.icns"

echo "==> Building ${BIN_NAME} (release)"
# Build only the app product — the TapgoTests target isn't part of the
# .app bundle and uses `@testable import TapgoCore`, which SwiftPM
# rejects in a release build (only enabled for debug/testing).
"${SWIFT[@]}" build -c release --product TapgoAICoding

# Computer-use MCP server (v0.5.18): embedded next to the app binary so
# the isolated Codex home config.toml can point at a stable path.
MCP_NAME="TapgoComputerUseMCP"
MCP_SRC="${ROOT}/.build/release/${MCP_NAME}"
echo "==> Building ${MCP_NAME} (release)"
"${SWIFT[@]}" build -c release --product "${MCP_NAME}"

if [[ ! -f "$BIN_SRC" ]]; then
  echo "ERROR: built binary not found at $BIN_SRC" >&2
  exit 1
fi
if [[ ! -f "$MCP_SRC" ]]; then
  echo "ERROR: built MCP binary not found at $MCP_SRC" >&2
  exit 1
fi

# Build the .icns if missing or stale.
if [[ ! -f "$ICNS_SRC" ]]; then
  echo "==> Generating app icon"
  "${ROOT}/scripts/build-icon.sh"
else
  echo "==> App icon already present at $ICNS_SRC (delete to regenerate)"
fi

echo "==> Assembling .app bundle at ${APP_BUNDLE_DIR}"
mavis-trash "$APP_BUNDLE_DIR" 2>/dev/null || rm -rf "$APP_BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$HELPER_MACOS_DIR" "$HELPER_RESOURCES_DIR"

cp "$BIN_SRC" "$MACOS_DIR/${BIN_NAME}"
chmod +x "$MACOS_DIR/${BIN_NAME}"

cp "$MCP_SRC" "$HELPER_MACOS_DIR/${MCP_NAME}"
chmod +x "$HELPER_MACOS_DIR/${MCP_NAME}"
cp "$HELPER_PLIST_SRC" "$HELPER_CONTENTS_DIR/Info.plist"
echo "  embedded computer-use helper: Tapgo Computer Use.app"

cp "$PLIST_SRC" "$CONTENTS_DIR/Info.plist"
cp "$PKGINFO_SRC" "$CONTENTS_DIR/PkgInfo"

if [[ -f "$ICNS_SRC" ]]; then
  cp "$ICNS_SRC" "${RESOURCES_DIR}/AppIcon.icns"
  cp "$ICNS_SRC" "${HELPER_RESOURCES_DIR}/AppIcon.icns"
  echo "  embedded icon: AppIcon.icns"
fi

# Ad-hoc codesign — no developer account needed.
if command -v codesign >/dev/null 2>&1; then
  echo "==> Ad-hoc codesigning"
  codesign --force --sign - \
    --entitlements "$ENTITLEMENTS_SRC" \
    --options runtime \
    "$HELPER_APP_DIR" 2>&1 | sed 's/^/    /'
  codesign --force --sign - \
    --entitlements "$ENTITLEMENTS_SRC" \
    --options runtime \
    "$APP_BUNDLE_DIR" 2>&1 | sed 's/^/    /'
else
  echo "WARN: codesign not found; Gatekeeper will require right-click → Open"
fi

echo
echo "==> Done"
echo "    App:  ${APP_BUNDLE_DIR}"
echo "    Run:  open '${APP_BUNDLE_DIR}'"
echo
echo "    First-time setup:  ./scripts/init-tapgo.sh"
echo "    Logs:              tail -f ~/Library/Logs/Tapgo\\ AICoding/harness.log"
echo
echo "    First launch note: if macOS shows a Gatekeeper warning,"
echo "    right-click the app in Finder → Open → Open. After that,"
echo "    double-click works normally."
