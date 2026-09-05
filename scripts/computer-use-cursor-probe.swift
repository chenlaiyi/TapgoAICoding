import AppKit
let pt = CGEvent(source: nil)!.location
// Window titles are redacted for SSH-launched probes without Screen Recording.
// Owner PID, layer and bounds remain available; bind to the Helper identity.
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []).filter {
    guard ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 25,
          let pid = ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
          NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.tapgo.aicoding.computer-use-helper",
          let raw = $0[kCGWindowBounds as String] as? [String: Any],
          let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary) else { return false }
    return bounds.width == 92 && bounds.height == 92
}
let data = try! JSONSerialization.data(withJSONObject: ["cursor": [pt.x, pt.y], "overlays": windows.map {
    ["bounds": $0[kCGWindowBounds as String] ?? [:], "layer": $0[kCGWindowLayer as String] ?? -1]
}], options: .sortedKeys)
print(String(data: data, encoding: .utf8)!)
