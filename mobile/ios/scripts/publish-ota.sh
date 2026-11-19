#!/usr/bin/env bash
# Export an ad-hoc IPA and publish it as an OTA manifest plus install page.
# Run on the macOS build host with the Apple Distribution private key installed.
set -euo pipefail

ARCHIVE="${OTA_ARCHIVE:-/tmp/Tapgo-OTA.xcarchive}"
OUT="${OTA_OUT:-/tmp/tapgo-ota}"
BASE_URL="${OTA_BASE_URL:-}"
TEAM_ID="${OTA_TEAM_ID:-KF2CE24685}"
BUNDLE_ID="${OTA_BUNDLE_ID:-com.devtools.terminalSimple}"
APP_TITLE="${OTA_APP_TITLE:-点点够终端}"
VERSION=""
BUILD=""
IPA=""
SKIP_EXPORT=0

usage() {
  cat <<'USAGE'
Usage: publish-ota.sh --base-url https://host/path [options]

  --archive PATH      Xcode archive (default /tmp/Tapgo-OTA.xcarchive)
  --out DIR           published directory (default /tmp/tapgo-ota)
  --base-url URL      public HTTPS URL serving that directory (required)
  --ipa PATH          publish this IPA instead of exporting (with --skip-export)
  --version VERSION   expected marketing version; checked against the IPA
  --build BUILD       expected build number; checked against the IPA
  --skip-export       do not run xcodebuild -exportArchive
  --team-id ID        Apple team id (default KF2CE24685)
  --bundle-id ID      bundle identifier (default com.devtools.terminalSimple)
  -h, --help          show this help

Environment: OTA_ARCHIVE, OTA_OUT, OTA_BASE_URL, OTA_TEAM_ID, OTA_BUNDLE_ID, OTA_APP_TITLE.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --archive) ARCHIVE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --base-url) BASE_URL="$2"; shift 2 ;;
    --ipa) IPA="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --build) BUILD="$2"; shift 2 ;;
    --skip-export) SKIP_EXPORT=1; shift ;;
    --team-id) TEAM_ID="$2"; shift 2 ;;
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$BASE_URL" ] || { echo "error: --base-url is required" >&2; exit 2; }
BASE_URL="${BASE_URL%/}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ "$SKIP_EXPORT" -eq 0 ]; then
  [ -d "$ARCHIVE" ] || { echo "error: archive not found: $ARCHIVE" >&2; exit 1; }
  EXPORT_DIR="$WORK/export"
  OPTIONS="$WORK/ExportOptions.plist"
  mkdir -p "$EXPORT_DIR"
  cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>ad-hoc</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>compileBitcode</key><false/>
  <key>stripSwiftSymbols</key><true/>
  <key>destination</key><string>export</string>
</dict></plist>
PLIST
  echo "==> exporting ad-hoc IPA"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$OPTIONS" \
    -allowProvisioningUpdates
  IPA="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' -print -quit)"
fi

[ -n "$IPA" ] && [ -f "$IPA" ] || { echo "error: IPA not found" >&2; exit 1; }

echo "==> inspecting $IPA"
unzip -p "$IPA" 'Payload/*.app/Info.plist' > "$WORK/Info.plist"
IPA_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$WORK/Info.plist")"
IPA_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$WORK/Info.plist")"
[ -n "$VERSION" ] || VERSION="$IPA_VERSION"
[ -n "$BUILD" ] || BUILD="$IPA_BUILD"
[ "$VERSION" = "$IPA_VERSION" ] || { echo "error: IPA version $IPA_VERSION does not match --version $VERSION" >&2; exit 1; }
[ "$BUILD" = "$IPA_BUILD" ] || { echo "error: IPA build $IPA_BUILD does not match --build $BUILD" >&2; exit 1; }

unzip -p "$IPA" 'Payload/*.app/embedded.mobileprovision' > "$WORK/profile.mobileprovision"
security cms -D -i "$WORK/profile.mobileprovision" > "$WORK/profile.plist" 2>/dev/null
if ! /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices:0' "$WORK/profile.plist" >/dev/null 2>&1 \
  && ! /usr/libexec/PlistBuddy -c 'Print :ProvisionsAllDevices' "$WORK/profile.plist" >/dev/null 2>&1; then
  echo "warning: profile has no provisioned devices; OTA install will fail on a normal device" >&2
fi
PROFILE_EXPIRY="$(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "$WORK/profile.plist" 2>/dev/null || true)"
PROFILE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$WORK/profile.plist" 2>/dev/null || true)"
GET_TASK_ALLOW="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' "$WORK/profile.plist" 2>/dev/null || true)"
PROFILE_KIND="ad-hoc"
if /usr/libexec/PlistBuddy -c 'Print :ProvisionsAllDevices' "$WORK/profile.plist" >/dev/null 2>&1; then
  PROFILE_KIND="enterprise"
elif [ "$GET_TASK_ALLOW" = "true" ]; then
  PROFILE_KIND="development"
fi
if [ "$PROFILE_KIND" = "development" ]; then
  echo "warning: IPA uses a development profile; iOS may reject OTA installation. Export ad-hoc before publishing." >&2
fi

mkdir -p "$OUT"
DEST="Tapgo-${VERSION}-${BUILD}.ipa"
cp "$IPA" "$OUT/$DEST"
cp "$IPA" "$OUT/Tapgo.ipa"

MANIFEST_URL="$BASE_URL/manifest.plist"
IPA_URL="$BASE_URL/Tapgo.ipa"
ENCODED_MANIFEST_URL="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$MANIFEST_URL")"

cat > "$OUT/manifest.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>items</key>
  <array><dict>
    <key>assets</key>
    <array><dict>
      <key>kind</key><string>software-package</string>
      <key>url</key><string>${IPA_URL}</string>
    </dict></array>
    <key>metadata</key>
    <dict>
      <key>bundle-identifier</key><string>${BUNDLE_ID}</string>
      <key>bundle-version</key><string>${BUILD}</string>
      <key>kind</key><string>software</string>
      <key>title</key><string>${APP_TITLE}</string>
    </dict>
  </dict></array>
</dict></plist>
PLIST

cat > "$OUT/index.html" <<HTML
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${APP_TITLE} ${VERSION}</title>
<style>body{font-family:-apple-system,sans-serif;max-width:420px;margin:15vh auto;padding:0 24px;text-align:center;color:#111}a.btn{display:block;padding:16px;border-radius:14px;background:#0a84ff;color:#fff;text-decoration:none;font-size:18px;font-weight:600}small{color:#666;display:block;margin-top:20px;line-height:1.6}code{color:#333}</style>
</head>
<body>
<h1>${APP_TITLE} ${VERSION}</h1>
<p>构建 ${BUILD}</p>
<a class="btn" href="itms-services://?action=download-manifest&amp;url=${ENCODED_MANIFEST_URL}">安装到 iPhone</a>
<small>必须用 Safari 打开；安装前请确认设备已加入描述文件。<br>描述文件类型：${PROFILE_KIND} · 到期：${PROFILE_EXPIRY}</small>
</body>
</html>
HTML

chmod 644 "$OUT/$DEST" "$OUT/Tapgo.ipa" "$OUT/manifest.plist" "$OUT/index.html"

echo "==> published ${VERSION} (${BUILD}) to $OUT"
echo "page:     $BASE_URL/"
echo "manifest: $MANIFEST_URL"
echo "ipa:      $IPA_URL"
echo "profile:  ${PROFILE_KIND} (${PROFILE_NAME})"
echo "devices:  $(/usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$WORK/profile.plist" 2>/dev/null | grep -c '^    ' || true) provisioned"
echo "expires:  ${PROFILE_EXPIRY:-unknown}"

if [[ "$BASE_URL" == https://* ]]; then
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$MANIFEST_URL" || true)"
  if [ "$code" = "200" ]; then
    echo "verify:   manifest returned 200"
  else
    echo "warning: manifest returned $code; is the public server serving $OUT?" >&2
  fi
fi
