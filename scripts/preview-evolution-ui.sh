#!/usr/bin/env bash
# Offscreen render of the self-evolution UI components (progress/metrics/diff).
# Runs as a plain executable — no second app launch, no session restart.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:-/tmp/tapgo-evolution-ui.png}"
SDK="${TAPGO_SDK:-macosx26.5}"

xcrun -sdk "$SDK" swift build --target TapgoCore >/dev/null
BIN="$(xcrun -sdk "$SDK" swift build --show-bin-path)"
BIN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tapgo-evolution-ui.XXXXXX")"
trap 'rm -rf "$BIN_DIR"' EXIT
BIN_PATH="$BIN_DIR/TapgoEvolutionUIPreview"

xcrun -sdk "$SDK" swiftc -parse-as-library -I "$BIN/Modules" \
  scripts/ui/EvolutionPreview.swift \
  Sources/TapgoAICoding/Views/EvolutionViews.swift \
  Sources/TapgoAICoding/Resources/DSHTheme.swift \
  "$BIN"/TapgoCore.build/*.o \
  -o "$BIN_PATH"

TAPGO_EVOLUTION_SNAPSHOT_OUT="$OUT" "$BIN_PATH"

[[ -f "$OUT" ]] || { echo "ERROR: snapshot not written: $OUT" >&2; exit 3; }
WIDTH="$(sips -g pixelWidth "$OUT" | awk '/pixelWidth/{print $2}')"
HEIGHT="$(sips -g pixelHeight "$OUT" | awk '/pixelHeight/{print $2}')"
SIZE="$(stat -f%z "$OUT")"
echo "EVOLUTION UI VERIFY OK ${WIDTH}x${HEIGHT} bytes=${SIZE} path=${OUT}"
[[ "$WIDTH" == "1800" && "$HEIGHT" == "1960" ]] || { echo "ERROR: unexpected render size ${WIDTH}x${HEIGHT}" >&2; exit 4; }
[[ "$SIZE" -gt 10000 ]] || { echo "ERROR: snapshot looks blank (${SIZE} bytes)" >&2; exit 5; }
