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

# ---------- 6. Upload to GitHub Release ----------
# Without this step the appcast <enclosure url> points to a 404 — installed
# clients can't fetch the zip. Idempotent: if the release already exists
# for this tag we only upload the zip and replace the release notes.
if ! command -v gh >/dev/null 2>&1; then
  echo "WARN: gh CLI not installed; skipping GitHub Release upload." >&2
  echo "      Install with: brew install gh" >&2
  echo "      Then run: gh release create \"$TAG\" \"$DIST/$ARCHIVE\" \\" >&2
  echo "                 --title \"$TAG\" --notes-file \"$NOTES_SOURCE\"" >&2
else
  if gh release view "$TAG" >/dev/null 2>&1; then
    echo "==> Release $TAG already exists; uploading zip + refreshing notes."
    gh release upload "$TAG" "$DIST/$ARCHIVE" --clobber >/dev/null
    gh release edit "$TAG" --notes-file "$NOTES_SOURCE" >/dev/null
  else
    echo "==> Creating GitHub Release $TAG with signed zip."
    gh release create "$TAG" "$DIST/$ARCHIVE" \
      --title "$TAG" \
      --notes-file "$NOTES_SOURCE"
  fi
fi

# ---------- 7. Commit refreshed appcast.xml ----------
# The new appcast.xml in repo root is what raw.githubusercontent.com serves —
# installed Sparkle clients poll that URL. Commit + push so the next poll
# sees the new <item>.
if [[ -f "$ROOT/appcast.xml" ]] && git diff --quiet -- appcast.xml; then
  echo "==> appcast.xml unchanged; nothing to commit."
elif [[ -f "$ROOT/appcast.xml" ]]; then
  git add appcast.xml
  if git diff --cached --quiet; then
    echo "==> appcast.xml has no staged diff; skipping commit."
  else
    git commit -m "chore(release): refresh appcast.xml for ${TAG}"
    if git push origin HEAD:main >/dev/null 2>&1; then
      echo "==> appcast.xml pushed; installed clients will detect ${TAG} on next poll."
    else
      echo "WARN: appcast.xml push failed; run: git push origin HEAD:main" >&2
    fi
  fi
fi

echo
echo "==> Done. Release: https://github.com/chenlaiyi/TapgoAICoding/releases/tag/$TAG"
