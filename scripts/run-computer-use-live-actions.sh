#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
helper=${1:?Pass the signed Helper executable path}
swift_compiler=(xcrun swiftc)
if xcrun -sdk macosx26.5 --show-sdk-path >/dev/null 2>&1; then swift_compiler=(xcrun -sdk macosx26.5 swiftc); fi
python3 - <<'PY'
import subprocess, os, signal, time
for line in subprocess.check_output(['ps','-axo','pid=,command='],text=True).splitlines():
    parts=line.strip().split(None,1)
    if len(parts)==2 and parts[1].split(' -psn_')[0] in ('/tmp/Tapgo CU Fixture.app/Contents/MacOS/Fixture','/private/tmp/Tapgo CU Fixture.app/Contents/MacOS/Fixture'):
        os.kill(int(parts[0]),signal.SIGTERM)
time.sleep(.2)
PY
mkdir -p '/tmp/Tapgo CU Fixture.app/Contents/MacOS'
"${swift_compiler[@]}" scripts/computer-use-fixture.swift -o '/tmp/Tapgo CU Fixture.app/Contents/MacOS/Fixture'
python3 - <<'PY'
import plistlib
with open('/tmp/Tapgo CU Fixture.app/Contents/Info.plist','wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='com.tapgo.cu-test-fixture',CFBundleExecutable='Fixture',CFBundleName='Tapgo CU Fixture',CFBundlePackageType='APPL'),f)
PY
"${swift_compiler[@]}" scripts/computer-use-cursor-probe.swift -o /tmp/tapgo-cursor-probe
open '/tmp/Tapgo CU Fixture.app'
python3 scripts/computer-use-live-actions.py "$helper" /tmp/tapgo-cursor-probe
