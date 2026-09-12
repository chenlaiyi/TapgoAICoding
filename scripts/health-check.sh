#!/usr/bin/env bash
# health-check.sh — validate a built .app before it is committed/released.
#
# Usage: ./scripts/health-check.sh "/path/Tapgo AICoding.app" [expected-version]
#
# Checks (fail fast):
#   1. Info.plist version matches expected
#   2. main executable exists and is Mach-O
#   3. Sparkle.framework + embedded computer-use helper exist
#   4. PhoneRemote resource bundle is complete
#   5. code signature verifies (skippable with HEALTH_SKIP_CODESIGN=1 for tests)
set -uo pipefail

APP="${1:-}"
EXPECTED="${2:-}"
[[ -n "$APP" && -d "$APP" ]] || { echo "HEALTH FAIL: app bundle not found: ${APP:-<empty>}" >&2; exit 1; }

CHECKS=0
pass() { CHECKS=$((CHECKS + 1)); }
fail() { echo "HEALTH FAIL: $*" >&2; exit 1; }

PLIST="$APP/Contents/Info.plist"
[[ -f "$PLIST" ]] || fail "missing Info.plist"
GOT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || true)"
[[ -n "$GOT_VERSION" ]] || fail "Info.plist has no CFBundleShortVersionString"
pass
if [[ -n "$EXPECTED" && "$GOT_VERSION" != "$EXPECTED" ]]; then
  fail "version mismatch: built=$GOT_VERSION expected=$EXPECTED"
fi

BIN="$APP/Contents/MacOS/TapgoAICoding"
[[ -x "$BIN" ]] || fail "missing executable: $BIN"
file "$BIN" | grep -q 'Mach-O' || fail "executable is not Mach-O: $BIN"
pass

[[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]] || fail "missing Sparkle.framework"
pass
HELPER="$APP/Contents/Resources/computer-use-helper/Tapgo Computer Use.app"
[[ -d "$HELPER" ]] || fail "missing embedded computer-use helper"
pass

REMOTE_BUNDLE="$APP/Contents/Resources/TapgoAICoding_TapgoCore.bundle/PhoneRemote"
for file in index.html app.css app.js app-icon.png; do
  [[ -f "$REMOTE_BUNDLE/$file" ]] || fail "missing PhoneRemote resource: $file"
done
pass

if [[ "${HEALTH_SKIP_CODESIGN:-}" != "1" ]]; then
  codesign --verify --deep --strict "$APP" >/dev/null 2>&1 || fail "code signature verification failed"
fi
pass

echo "HEALTH OK version=$GOT_VERSION checks=$CHECKS app=$APP"
