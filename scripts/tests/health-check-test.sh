#!/usr/bin/env bash
# Regression tests for scripts/health-check.sh using a synthetic app bundle.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-health-check-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
APP="$TMP/Tapgo AICoding.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks/Sparkle.framework" \
  "$APP/Contents/Resources/computer-use-helper/Tapgo Computer Use.app/Contents/MacOS" \
  "$APP/Contents/Resources/TapgoAICoding_TapgoCore.bundle/PhoneRemote"
cp /bin/echo "$APP/Contents/MacOS/TapgoAICoding"
chmod +x "$APP/Contents/MacOS/TapgoAICoding"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>0.5.9</string>
<key>CFBundleVersion</key><string>0.5.9</string>
</dict></plist>
PLIST
for f in index.html app.css app.js app-icon.png; do echo x > "$APP/Contents/Resources/TapgoAICoding_TapgoCore.bundle/PhoneRemote/$f"; done

HEALTH_SKIP_CODESIGN=1 "$ROOT/scripts/health-check.sh" "$APP" 0.5.9 | grep -q 'HEALTH OK'
set +e
HEALTH_SKIP_CODESIGN=1 "$ROOT/scripts/health-check.sh" "$APP" 0.5.10 >/dev/null 2>&1
RC=$?
set -e
[[ "$RC" -eq 1 ]] || { echo "FAIL wrong version rc=$RC" >&2; exit 1; }

rm "$APP/Contents/Resources/TapgoAICoding_TapgoCore.bundle/PhoneRemote/index.html"
set +e
HEALTH_SKIP_CODESIGN=1 "$ROOT/scripts/health-check.sh" "$APP" 0.5.9 >/dev/null 2>&1
RC=$?
set -e
[[ "$RC" -eq 1 ]] || { echo "FAIL missing resource rc=$RC" >&2; exit 1; }

echo "health-check tests: 3 passed, 0 failed"
