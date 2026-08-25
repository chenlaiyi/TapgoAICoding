#!/usr/bin/env bash
# Generate AppIcon.icns from a Swift-drawn 1024x1024 PNG.
#
# What this does:
#   1. Calls scripts/generate-icon.swift to produce a 1024x1024 source PNG
#   2. Uses `sips` to downscale to all the sizes macOS needs
#   3. Uses `iconutil` to bundle them into a single .icns file
#   4. Cleans up intermediate files
#
# Output: AppBuilder/AppIcon.icns

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT_SCRIPT="${ROOT}/scripts/generate-icon.swift"
ICONSET_DIR="${ROOT}/AppBuilder/AppIcon.iconset"
SOURCE_PNG="${ROOT}/AppBuilder/icon-1024.png"
OUTPUT_ICNS="${ROOT}/AppBuilder/AppIcon.icns"

if ! command -v sips >/dev/null 2>&1; then
  echo "ERROR: 'sips' not found. sips ships with macOS — are you on Linux?" >&2
  exit 1
fi
if ! command -v iconutil >/dev/null 2>&1; then
  echo "ERROR: 'iconutil' not found. iconutil ships with macOS." >&2
  exit 1
fi

# 1. Draw the source PNG
rm -rf "$ICONSET_DIR" "$OUTPUT_ICNS"
mkdir -p "$ICONSET_DIR"
echo "==> Drawing 1024×1024 source PNG"
swift "$SWIFT_SCRIPT" "$SOURCE_PNG"

# 2. Generate all required sizes into a .iconset
#    Naming convention per Apple HIG:  icon_<width>x<height>.png  /  icon_<width>x<height>@2x.png
echo "==> Generating icon sizes"
sips -z 16   16   "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_16x16.png"          >/dev/null
sips -z 32   32   "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_16x16@2x.png"       >/dev/null
sips -z 32   32   "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_32x32.png"          >/dev/null
sips -z 64   64   "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_32x32@2x.png"       >/dev/null
sips -z 128  128  "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_128x128.png"        >/dev/null
sips -z 256  256  "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_128x128@2x.png"     >/dev/null
sips -z 256  256  "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_256x256.png"        >/dev/null
sips -z 512  512  "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_256x256@2x.png"     >/dev/null
sips -z 512  512  "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_512x512.png"        >/dev/null
sips -z 1024 1024 "$SOURCE_PNG" --out "${ICONSET_DIR}/icon_512x512@2x.png"     >/dev/null

# 3. Bundle into .icns
echo "==> Building AppIcon.icns"
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

# 4. Cleanup
rm -rf "$ICONSET_DIR" "$SOURCE_PNG"

echo "==> Wrote $OUTPUT_ICNS ($(du -h "$OUTPUT_ICNS" | cut -f1))"
