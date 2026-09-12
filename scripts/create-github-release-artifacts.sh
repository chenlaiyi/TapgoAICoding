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

# v0.5.255: 仓库归属不再硬编码 —— 优先 TAPGO_REPO_SLUG,否则从 git remote
# (upstream 优先,其次 origin)推断。fork 用户发布到自己仓库时无需改脚本。
# shellcheck source=scripts/tapgo-repo-slug.sh
source "$ROOT/scripts/tapgo-repo-slug.sh"
REPO_SLUG="$(tapgo_repo_slug || true)"
if [[ -z "$REPO_SLUG" ]]; then
  echo "ERROR: 无法解析仓库归属。请设置 TAPGO_REPO_SLUG=owner/repo 后重试。" >&2
  echo "       当前 git remotes:" >&2
  git remote -v | sed 's/^/         /' >&2
  exit 8
fi
echo "==> Target repo: ${REPO_SLUG}"
DOWNLOAD_PREFIX="https://github.com/${REPO_SLUG}/releases/download/$TAG/"

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

# A signed binary can still crash at Bundle.module if the SwiftPM resource
# bundle was omitted from the archive. Validate the exact distributable, not
# merely the source build directory, before signing or publishing it.
APP_BUNDLE_NAME="$(basename "$APP")"
CORE_RESOURCE_PREFIXES=(
  "${APP_BUNDLE_NAME}/Contents/Resources/TapgoAICoding_TapgoCore.bundle/PhoneRemote"
  "${APP_BUNDLE_NAME}/Contents/Resources/computer-use-helper/Tapgo Computer Use.app/Contents/Resources/TapgoAICoding_TapgoCore.bundle/PhoneRemote"
)
ARCHIVE_ENTRIES="$WORK/archive-entries.txt"
unzip -Z1 "$WORK/$ARCHIVE" > "$ARCHIVE_ENTRIES"
for CORE_RESOURCE_PREFIX in "${CORE_RESOURCE_PREFIXES[@]}"; do
  for RESOURCE_FILE in index.html app.css app.js app-icon.png; do
    if ! grep -Fxq "${CORE_RESOURCE_PREFIX}/${RESOURCE_FILE}" "$ARCHIVE_ENTRIES"; then
      echo "ERROR: release archive missing phone remote resource: ${CORE_RESOURCE_PREFIX}/${RESOURCE_FILE}" >&2
      exit 5
    fi
  done
done
echo "==> Verified release archive contains phone remote resources"
if [[ -f "$ROOT/appcast.xml" ]]; then
  cp "$ROOT/appcast.xml" "$WORK/appcast.xml"
fi

NOTES_SOURCE="${1:-$ROOT/AppBuilder/release-notes-$VERSION.md}"
if [[ ! -f "$NOTES_SOURCE" ]]; then
  echo "ERROR: release notes not found at $NOTES_SOURCE" >&2
  exit 4
fi
cp "$NOTES_SOURCE" "$WORK/${ARCHIVE%.zip}.md"

if [[ -n "${SPARKLE_KEY_FILE:-}" ]]; then
  KEY_FILE_OPT=(--ed-key-file "$SPARKLE_KEY_FILE")
else
  KEY_FILE_OPT=()
fi

"$SPARKLE_BIN/generate_appcast" \
  --account com.tapgo.aicoding \
  ${KEY_FILE_OPT[@]+"${KEY_FILE_OPT[@]}"} \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --link "https://github.com/${REPO_SLUG}/releases/tag/$TAG" \
  --embed-release-notes \
  --maximum-versions 3 \
  -o "$WORK/appcast.xml" \
  "$WORK"

cp "$WORK/$ARCHIVE" "$DIST/$ARCHIVE"
if [[ "${TAPGO_CANARY:-0}" == "1" ]]; then
  cp "$WORK/appcast.xml" "$DIST/appcast.xml"
  echo "==> CANARY: appcast staged at $DIST/appcast.xml (not published yet)"
else
  cp "$WORK/appcast.xml" "$ROOT/appcast.xml"
  cp "$WORK/appcast.xml" "$DIST/appcast.xml"
fi
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
    if [[ "${TAPGO_CANARY:-0}" == "1" ]]; then
      echo "==> Creating DRAFT GitHub Release $TAG for canary."
      gh release create "$TAG" "$DIST/$ARCHIVE" \
        --draft \
        --title "$TAG" \
        --notes-file "$NOTES_SOURCE"
    else
      echo "==> Creating GitHub Release $TAG with signed zip."
      gh release create "$TAG" "$DIST/$ARCHIVE" \
        --title "$TAG" \
        --notes-file "$NOTES_SOURCE"
    fi
  fi
fi

# ---------- 7. Commit refreshed appcast.xml (skipped in canary mode) ----------
if [[ "${TAPGO_CANARY:-0}" == "1" ]]; then
  echo "==> CANARY: appcast publication deferred until canary promotion."
else
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
fi

echo
echo "==> Done. Release: https://github.com/${REPO_SLUG}/releases/tag/$TAG"
