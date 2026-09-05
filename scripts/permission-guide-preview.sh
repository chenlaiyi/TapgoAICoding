#!/bin/bash
# Compile the actual guide controller into an isolated, unprivileged UI preview.
# Opens System Settings but never changes permissions or drops the Helper.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
preview=$(mktemp -d /tmp/tapgo-guide-preview.XXXXXX)
app="$preview/Tapgo Guide Preview.app"
mkdir -p "$app/Contents/MacOS"
sed '/^import TapgoCore$/d' "$root/Sources/TapgoAICoding/Services/ComputerUsePermissionGuide.swift" > "$preview/Guide.swift"
cat > "$preview/main.swift" <<'SWIFT'
import AppKit
import ApplicationServices
@MainActor final class PreviewDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let status = ["accessibility": AXIsProcessTrusted(), "screen_recording": CGPreflightScreenCaptureAccess()]
        if let data = try? JSONSerialization.data(withJSONObject: status) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/tapgo-guide-preview-permissions.json"))
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        ComputerUsePermissionGuideController.shared.present(
            permission: .accessibility,
            helperAppURL: URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Tapgo AICoding/computer-use/Tapgo Computer Use.app"),
            completion: { NSApp.terminate(nil) }
        )
    }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = PreviewDelegate()
    app.delegate = delegate
    app.run()
}
SWIFT
xcrun -sdk macosx26.5 swiftc "$root/Sources/TapgoCore/PermissionGuideLayout.swift" "$preview/Guide.swift" "$preview/main.swift" -o "$app/Contents/MacOS/Preview"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Preview</string>
<key>CFBundleIdentifier</key><string>com.tapgo.permission-guide-preview</string>
<key>CFBundleName</key><string>Tapgo Guide Preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
printf '%s\n' "$app"
