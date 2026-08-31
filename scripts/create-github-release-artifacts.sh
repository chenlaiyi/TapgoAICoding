#!/usr/bin/env bash
# Build a signed Sparkle update archive and refresh appcast.xml for a GitHub
# Release. The EdDSA private key stays in the login Keychain; only the public
# key and generated signature are written to the repository/artifacts.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' AppBuilder/Info.plist)"
TAG="v${VERSION}"
APP="$ROOT/Tapgo AICoding.app"
DIST="$ROOT/AppBuilder/dist/$TAG"
ARCHIVE="Tapgo-AICoding-${VERSION}.zip"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
DOWNLOAD_PREFIX="https://github.com/chenlaiyi/TapgoAICoding/releases/download/$TAG/"

if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
  echo "ERROR: Sparkle tools are missing; run swift package resolve first." >&2
  exit 2
fi

"$ROOT/scripts/build-app.sh"

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [[ "$BUILT_VERSION" != "$VERSION" ]]; then
  echo "ERROR: built version $BUILT_VERSION does not match source $VERSION." >&2
  exit 3
fi

mkdir -p "$DIST"
WORK="$(mktemp -d -t tapgo-sparkle-release.XXXXXX)"
trap 'mavis-trash "$WORK" >/dev/null 2>&1 || true' EXIT

ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/$ARCHIVE"
if [[ -f "$ROOT/appcast.xml" ]]; then
  cp "$ROOT/appcast.xml" "$WORK/appcast.xml"
fi

NOTES_SOURCE="${1:-$ROOT/AppBuilder/release-notes-$VERSION.md}"
if [[ ! -f "$NOTES_SOURCE" ]]; then
  echo "ERROR: release notes not found at $NOTES_SOURCE" >&2
  exit 4
fi
cp "$NOTES_SOURCE" "$WORK/${ARCHIVE%.zip}.md"

"$SPARKLE_BIN/generate_appcast" \
  --account com.tapgo.aicoding \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --link "https://github.com/chenlaiyi/TapgoAICoding/releases/tag/$TAG" \
  --embed-release-notes \
  --maximum-versions 3 \
  -o "$WORK/appcast.xml" \
  "$WORK"

cp "$WORK/$ARCHIVE" "$DIST/$ARCHIVE"
cp "$WORK/appcast.xml" "$ROOT/appcast.xml"
cp "$WORK/appcast.xml" "$DIST/appcast.xml"
cp "$NOTES_SOURCE" "$DIST/release-notes.md"
(
  cd "$DIST"
  shasum -a 256 "$ARCHIVE" appcast.xml > SHA256SUMS.txt
)

echo "Release artifacts ready:"
echo "  $DIST/$ARCHIVE"
echo "  $DIST/appcast.xml"
echo "  $DIST/SHA256SUMS.txt"
