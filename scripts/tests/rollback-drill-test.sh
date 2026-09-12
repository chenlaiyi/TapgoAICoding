#!/usr/bin/env bash
# Regression tests for scripts/rollback-drill.sh using a synthetic release zip.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$ROOT/scripts/rollback-drill.sh"
HEALTH="$ROOT/scripts/health-check.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-rollback-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; ORIGIN="$TMP/origin.git"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name Test
echo base > "$REPO/base.txt"
git -C "$REPO" add -A; git -C "$REPO" commit -qm base
git -C "$REPO" tag -a v0.5.1 -m v0.5.1
git -C "$REPO" init -q --bare "$ORIGIN"
git -C "$REPO" remote add origin "$ORIGIN"
git -C "$REPO" push -q -u origin main --tags

make_app() {
  local app="$1"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks/Sparkle.framework" \
    "$app/Contents/Resources/computer-use-helper/Tapgo Computer Use.app/Contents/MacOS" \
    "$app/Contents/Resources/TapgoAICoding_TapgoCore.bundle/PhoneRemote"
  cp /bin/echo "$app/Contents/MacOS/TapgoAICoding"; chmod +x "$app/Contents/MacOS/TapgoAICoding"
  cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>0.5.1</string></dict></plist>
PLIST
  for f in index.html app.css app.js app-icon.png; do echo x > "$app/Contents/Resources/TapgoAICoding_TapgoCore.bundle/PhoneRemote/$f"; done
}
APP="$TMP/Tapgo AICoding.app"; make_app "$APP"
ZIP="$TMP/release.zip"; ditto -c -k --keepParent "$APP" "$ZIP"

HISTORY="$TMP/history.jsonl"
HEALTH_SKIP_CODESIGN=1 EVOLVE_ROLLBACK_REPO_ROOT="$REPO" "$TOOL" --tag v0.5.1 --archive "$ZIP" --health-script "$HEALTH" --history "$HISTORY" --no-download >/dev/null
grep -q '"passed": true' "$HISTORY" || { echo "FAIL pass history" >&2; exit 1; }

rm "$APP/Contents/Resources/TapgoAICoding_TapgoCore.bundle/PhoneRemote/index.html"
ditto -c -k --keepParent "$APP" "$TMP/bad.zip"
set +e
HEALTH_SKIP_CODESIGN=1 EVOLVE_ROLLBACK_REPO_ROOT="$REPO" "$TOOL" --tag v0.5.1 --archive "$TMP/bad.zip" --health-script "$HEALTH" --history "$HISTORY" --no-download >/dev/null 2>&1
RC=$?
set -e
[[ "$RC" -eq 1 ]] || { echo "FAIL bad archive rc=$RC" >&2; exit 1; }
grep -q '"passed": false' "$HISTORY" || { echo "FAIL fail history" >&2; exit 1; }

set +e
EVOLVE_ROLLBACK_REPO_ROOT="$REPO" "$TOOL" --tag v0.5.1 --no-download --history "$HISTORY" >/dev/null 2>&1
RC=$?
set -e
[[ "$RC" -eq 1 ]] || { echo "FAIL missing archive rc=$RC" >&2; exit 1; }

echo "rollback-drill tests: 5 passed, 0 failed"
