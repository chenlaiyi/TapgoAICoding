#!/usr/bin/env bash
# Wrap the SwiftPM-built TapgoAICoding binary into a double-clickable .app
# bundle.
#
# What this does:
#   1. swift build -c release (executable: TapgoAICoding)
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

APP_DISPLAY_NAME="Tapgo AICoding"
APP_DIR_NAME="Tapgo AICoding"
APP_BUNDLE_DIR="${ROOT}/${APP_DIR_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

BIN_NAME="TapgoAICoding"
BIN_SRC="${ROOT}/.build/release/${BIN_NAME}"
PLIST_SRC="${ROOT}/AppBuilder/Info.plist"
ENTITLEMENTS_SRC="${ROOT}/AppBuilder/TapgoAICoding.entitlements"
PKGINFO_SRC="${ROOT}/AppBuilder/PkgInfo"
ICNS_SRC="${ROOT}/AppBuilder/AppIcon.icns"

echo "==> Building ${BIN_NAME} (release)"
# Build only the app product — the TapgoTests target isn't part of the
# .app bundle and uses `@testable import TapgoCore`, which SwiftPM
# rejects in a release build (only enabled for debug/testing).
swift build -c release --product TapgoAICoding

if [[ ! -f "$BIN_SRC" ]]; then
  echo "ERROR: built binary not found at $BIN_SRC" >&2
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
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_SRC" "$MACOS_DIR/${BIN_NAME}"
chmod +x "$MACOS_DIR/${BIN_NAME}"

cp "$PLIST_SRC" "$CONTENTS_DIR/Info.plist"
cp "$PKGINFO_SRC" "$CONTENTS_DIR/PkgInfo"

if [[ -f "$ICNS_SRC" ]]; then
  cp "$ICNS_SRC" "${RESOURCES_DIR}/AppIcon.icns"
  echo "  embedded icon: AppIcon.icns"
fi

# Ad-hoc codesign — no developer account needed.
if command -v codesign >/dev/null 2>&1; then
  echo "==> Ad-hoc codesigning"
  codesign --force --deep --sign - \
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
