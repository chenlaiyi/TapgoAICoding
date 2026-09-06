#!/usr/bin/env bash
# Build a standalone native fixture with shipping components; no real sessions or network.
set -euo pipefail
TASK_UI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_UI_ROOT"
xcrun -sdk macosx26.5 swift build --target TapgoCore
TASK_UI_BIN="$(xcrun -sdk macosx26.5 swift build --show-bin-path)"
TASK_UI_APP='/tmp/Tapgo Task UI Preview.app'
mkdir -p "$TASK_UI_APP/Contents/MacOS"
xcrun -sdk macosx26.5 swiftc -parse-as-library -I "$TASK_UI_BIN/Modules" \
  scripts/ui/TaskInteractionPreview.swift Sources/TapgoAICoding/Views/TaskInteractionViews.swift \
  Sources/TapgoAICoding/Resources/DSHTheme.swift "$TASK_UI_BIN"/TapgoCore.build/*.o \
  -o "$TASK_UI_APP/Contents/MacOS/TapgoTaskUIPreview"
python3 - <<'PY'
from pathlib import Path
import plistlib
Path('/tmp/Tapgo Task UI Preview.app/Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier':'com.tapgo.task-ui-preview', 'CFBundleName':'Tapgo Task UI Preview',
    'CFBundleExecutable':'TapgoTaskUIPreview', 'CFBundlePackageType':'APPL', 'NSHighResolutionCapable':True
}))
PY
codesign --force --sign - "$TASK_UI_APP"
printf '%s\n' "$TASK_UI_APP"
