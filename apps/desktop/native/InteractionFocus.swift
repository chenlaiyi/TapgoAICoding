import AppKit
import ApplicationServices
import Darwin
import Foundation

private func focusAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

private func focusWindowID(_ element: AXUIElement) -> CGWindowID? {
    guard let library = dlopen(nil, RTLD_LAZY) else { return nil }
    defer { dlclose(library) }
    guard let symbol = dlsym(library, "_AXUIElementGetWindow") else { return nil }
    typealias ReadWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    let read = unsafeBitCast(symbol, to: ReadWindow.self)
    var identifier: CGWindowID = 0
    guard read(element, &identifier) == .success, identifier > 0 else { return nil }
    return identifier
}

private func focusRect(_ element: AXUIElement) -> CGRect? {
    guard let position = focusAttribute(element, kAXPositionAttribute),
          let size = focusAttribute(element, kAXSizeAttribute),
          CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var origin = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
          AXValueGetValue(size as! AXValue, .cgSize, &dimensions), dimensions.width > 0, dimensions.height > 0 else { return nil }
    return CGRect(origin: origin, size: dimensions)
}

// A compositor surface covering the three native window buttons is not an independent window.
func isWindowControlSurface(_ bounds: CGRect, controls: [CGRect]) -> Bool {
    guard controls.count == 3 else { return false }
    let cluster = controls.reduce(CGRect.null) { $0.union($1) }
    let padding = controls.map { max($0.width, $0.height) }.max() ?? 0
    guard padding > 0, cluster.insetBy(dx: -padding, dy: -padding).contains(bounds) else { return false }
    return controls.allSatisfy { bounds.contains(CGPoint(x: $0.midX, y: $0.midY)) }
}

private func windowControls(_ window: AXUIElement) -> [CGRect] {
    [kAXCloseButtonAttribute, kAXMinimizeButtonAttribute, kAXZoomButtonAttribute].compactMap { name in
        guard let value = focusAttribute(window, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return focusRect(value as! AXUIElement)
    }
}

private func displayForWindow(_ window: CGRect, displays: [CGRect]) -> Int? {
    displays.indices.filter { !window.intersection(displays[$0]).isNull }.max {
        let left = window.intersection(displays[$0]); let right = window.intersection(displays[$1])
        return left.width * left.height < right.width * right.height
    }
}

func inspectNativeFocus(pid: Int32, requested: CGWindowID?, timeoutMs: Double) -> [String: Any] {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, Float(timeoutMs / 1000))
    let axWindows = focusAttribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    let mapped = axWindows.compactMap { window -> (CGWindowID, AXUIElement)? in
        guard let identifier = focusWindowID(window) else { return nil }; return (identifier, window)
    }
    let focusedValue = focusAttribute(app, kAXFocusedWindowAttribute)
    let focused = focusedValue.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? focusWindowID($0 as! AXUIElement) : nil }
    let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let visible = rows.compactMap { row -> (CGWindowID, CGRect)? in
        guard row[kCGWindowOwnerPID as String] as? Int32 == pid,
              row[kCGWindowLayer as String] as? Int == 0,
              let identifier = row[kCGWindowNumber as String] as? CGWindowID,
              let value = row[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: value as CFDictionary), bounds.width > 0, bounds.height > 0 else { return nil }
        return (identifier, bounds)
    }
    var ignored: [CGWindowID] = []
    for (identifier, bounds) in visible {
        if mapped.contains(where: { $0.0 == identifier }) { continue }
        if mapped.contains(where: { isWindowControlSurface(bounds, controls: windowControls($0.1)) }) { ignored.append(identifier) }
    }
    let eligible = visible.filter { row in mapped.contains { $0.0 == row.0 } }.map { $0.0 }
    let resolved = requested ?? (eligible.count == 1 ? eligible.first : nil)
    var reason = "target_unresolved"
    var verified = false
    var front: CGWindowID?
    if let resolved, let target = mapped.first(where: { $0.0 == resolved }), let targetBounds = visible.first(where: { $0.0 == resolved })?.1 {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var identifiers = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &identifiers, &count)
        let displays = identifiers.prefix(Int(count)).map { CGDisplayBounds($0) }
        let targetDisplay = displayForWindow(targetBounds, displays: displays)
        front = visible.first { !ignored.contains($0.0) && displayForWindow($0.1, displays: displays) == targetDisplay }?.0
        let sheets = focusAttribute(target.1, "AXSheets") as? [AXUIElement] ?? []
        let modal = !sheets.isEmpty
        if modal { reason = "modal_sheet_present" }
        else if frontPid() != pid { reason = "application_not_frontmost" }
        else if focused != resolved { reason = "different_focused_window" }
        else if front != resolved { reason = "different_front_window" }
        else if ignored.isEmpty { reason = "no_control_surface_to_correct" }
        else { reason = "verified_ax_window"; verified = true }
    }
    return ["type": "focus", "pid": pid,
            "requested_window_id": requested.map { $0 as Any } ?? NSNull(),
            "resolved_window_id": resolved.map { $0 as Any } ?? NSNull(),
            "focused_window_id": focused.map { $0 as Any } ?? NSNull(),
            "front_window_id": front.map { $0 as Any } ?? NSNull(),
            "eligible_window_ids": eligible, "ignored_control_window_ids": ignored,
            "unmapped_window_ids": visible.map { $0.0 }.filter { !eligible.contains($0) && !ignored.contains($0) },
            "verified": verified, "reason": reason]
}

func checkWindowControlSurface() {
    let buttons = [CGRect(x: 10, y: 10, width: 14, height: 14), CGRect(x: 30, y: 10, width: 14, height: 14), CGRect(x: 50, y: 10, width: 14, height: 14)]
    precondition(isWindowControlSurface(CGRect(x: 6, y: 7, width: 66, height: 20), controls: buttons))
    precondition(!isWindowControlSurface(CGRect(x: 0, y: 0, width: 300, height: 200), controls: buttons))
    precondition(!isWindowControlSurface(CGRect(x: 6, y: 7, width: 66, height: 20), controls: []))
}
