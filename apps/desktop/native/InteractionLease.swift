// Content-free desktop-state restoration for one explicitly foreground SDK drag.
import AppKit
import ApplicationServices
import Foundation

struct Point: Codable { let x: Double; let y: Double }
struct Snapshot: Codable { let pid: Int32; let pointer: Point }
struct Begin: Decodable { let driverPid: Int32; let timeoutMs: Double; let pollMs: Double; let leaseMs: Double }
struct Request: Decodable { let command: String; let begin: Begin?; let restore: Bool? }

func emit(_ value: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
          let line = String(data: data, encoding: .utf8) else { exit(2) }
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}
func point() -> CGPoint? { CGEvent(source: nil)?.location }
func frontPid() -> Int32? { NSWorkspace.shared.frontmostApplication?.processIdentifier }
func buttonHeld() -> Bool {
    [CGMouseButton.left, .right, .center].contains { CGEventSource.buttonState(.combinedSessionState, button: $0) }
}
func windowPid(at point: CGPoint, excluding driverPid: Int32) -> Int32? {
    guard let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
    return windowPid(in: rows, at: point, excluding: [getpid(), driverPid])
}
func windowPid(in rows: [[String: Any]], at point: CGPoint, excluding ignoredPids: Set<Int32>) -> Int32? {
    for row in rows {
        guard (row[kCGWindowLayer as String] as? Int) == 0,
              let bounds = row[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.contains(point),
              let pid = row[kCGWindowOwnerPID as String] as? Int32,
              !ignoredPids.contains(pid) else { continue }
        return pid
    }
    return nil
}
func dragImagePresent() -> Bool {
    guard let rows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return true }
    return rows.contains { ($0[kCGWindowLayer as String] as? Int) == 101 }
}
func skipReason(interference: Bool, monitor: Bool, released: Bool, held: Bool, dragImage: Bool, originalAlive: Bool, focusAllowed: Bool) -> String? {
    if !monitor { return "monitor_lost" }
    if interference { return "outside_input_or_activation" }
    if !originalAlive { return "original_application_ended" }
    if !released || held || dragImage { return "gesture_not_settled" }
    if !focusAllowed { return "foreground_changed" }
    return nil
}

final class Lease {
    let config: Begin
    let application: NSRunningApplication
    let originalPoint: CGPoint
    let originalWindow: AXUIElement?
    var tap: CFMachPort?
    var timer: Timer?
    var activations: [Int32] = []
    var externalSources: Set<Int64> = []
    var outsideInput = false
    var sourcePid: Int32?
    var destinationPid: Int32?
    var releasePoint: CGPoint?
    var finishing = false
    var focusRequested = false
    var deadline = Double.infinity
    var observer: NSObjectProtocol?

    init?(_ config: Begin) {
        guard config.driverPid > 0, config.timeoutMs > 0, config.pollMs > 0, config.leaseMs > 0,
              let app = NSWorkspace.shared.frontmostApplication, !app.isTerminated,
              let position = point(), !buttonHeld() else { return nil }
        self.config = config; application = app; originalPoint = position
        var focused: CFTypeRef?
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            originalWindow = (focused as! AXUIElement)
        } else { originalWindow = nil }
    }
    func start() -> Bool {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .keyDown, .keyUp, .flagsChanged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        // AX authorization already permits this tap; no permission request is made.
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let lease = Unmanaged<Lease>.fromOpaque(context).takeUnretainedValue()
            lease.observe(type, event)
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.activations.append(app.processIdentifier) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: config.pollMs / 1000, repeats: true) { [weak self] _ in self?.tick() }
        DispatchQueue.main.asyncAfter(deadline: .now() + config.leaseMs / 1000) { [weak self] in
            guard let self else { return }; self.finishResult("expired", focus: false, pointer: false)
        }
        return true
    }
    func observe(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { outsideInput = true }
        let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
        if pid == Int64(getpid()) { return }
        if pid != Int64(config.driverPid) {
            outsideInput = true; externalSources.insert(pid)
        }
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown { sourcePid = windowPid(at: event.location, excluding: config.driverPid) }
        if type == .leftMouseUp || type == .rightMouseUp || type == .otherMouseUp {
            destinationPid = windowPid(at: event.location, excluding: config.driverPid); releasePoint = event.location
        }
    }
    func finish(_ restore: Bool) {
        if !restore { finishResult("not_requested", focus: false, pointer: false) }
        finishing = true; deadline = ProcessInfo.processInfo.systemUptime + config.timeoutMs / 1000
        tick()
    }
    func tick() {
        guard finishing else { return }
        let allowed = Set([application.processIdentifier, config.driverPid, getpid()] + [sourcePid, destinationPid].compactMap { $0 })
        let current = frontPid()
        let unexpectedActivation = activations.contains { !allowed.contains($0) }
        let reason = skipReason(interference: outsideInput || unexpectedActivation,
            monitor: tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false,
            released: releasePoint != nil, held: buttonHeld(), dragImage: dragImagePresent(),
            originalAlive: !application.isTerminated, focusAllowed: current.map { allowed.contains($0) } ?? false)
        if let reason {
            if reason == "gesture_not_settled" && ProcessInfo.processInfo.systemUptime < deadline { return }
            finishResult(reason, focus: false, pointer: false)
        }
        guard let releasePoint, let currentPoint = point(), hypot(currentPoint.x - releasePoint.x, currentPoint.y - releasePoint.y) <= 1 else {
            finishResult("pointer_changed", focus: false, pointer: false)
        }
        if current != application.processIdentifier {
            if focusRequested {
                if ProcessInfo.processInfo.systemUptime >= deadline { finishResult("focus_restore_failed", focus: false, pointer: false) }
                return
            }
            focusRequested = true
            if let window = originalWindow {
                let axApp = AXUIElementCreateApplication(application.processIdentifier)
                AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, window)
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            }
            if !application.activate(options: [.activateIgnoringOtherApps]) { finishResult("focus_restore_failed", focus: false, pointer: false) }
            return
        }
        // Check again after activation has settled; outside input always wins.
        guard !outsideInput, !buttonHeld(), frontPid() == application.processIdentifier else {
            finishResult("outside_input_or_activation", focus: true, pointer: false)
        }
        let error = CGWarpMouseCursorPosition(originalPoint)
        let actual = point()
        let restored = error == .success && actual.map { hypot($0.x - originalPoint.x, $0.y - originalPoint.y) <= 1 } == true
        finishResult(restored ? "restored" : "pointer_restore_failed", focus: true, pointer: restored)
    }
    func finishResult(_ status: String, focus: Bool, pointer: Bool) -> Never {
        timer?.invalidate()
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        let after = point()
        emit(["type": "finished", "status": status, "focus_restored": focus, "pointer_restored": pointer,
              "before_pid": application.processIdentifier, "before_pointer": ["x": originalPoint.x, "y": originalPoint.y],
              "after_pid": frontPid().map { $0 as Any } ?? NSNull(),
              "after_pointer": after.map { ["x": $0.x, "y": $0.y] as Any } ?? NSNull(),
              "outside_input": outsideInput, "external_source_pids": externalSources.sorted(),
              "driver_pid": config.driverPid, "source_pid": sourcePid.map { $0 as Any } ?? NSNull(),
              "destination_pid": destinationPid.map { $0 as Any } ?? NSNull(),
              "activated_pids": activations, "focus_requested": focusRequested])
        exit(0)
    }
}

final class InteractionRuntime {
    private var lease: Lease?

    func receive(_ request: Request) {
        if request.command == "begin", lease == nil, let config = request.begin {
            guard let value = Lease(config), value.start() else { emit(["type": "unavailable"]); exit(0) }
            lease = value; emit(["type": "ready"])
        } else if request.command == "finish", let value = lease, let restore = request.restore { value.finish(restore) }
        else { exit(2) }
    }

    func run() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        DispatchQueue.global().async {
            while let line = readLine() {
                guard line.utf8.count <= 4096, let data = line.data(using: .utf8),
                      let request = try? JSONDecoder().decode(Request.self, from: data) else { exit(2) }
                DispatchQueue.main.async { self.receive(request) }
            }
            exit(0)
        }
        NSApplication.shared.run()
    }
}

@main
struct InteractionMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            let bounds: [String: Any] = ["X": 0, "Y": 0, "Width": 100, "Height": 100]
            let windows: [[String: Any]] = [42, 43, 77].map { pid in
                [kCGWindowLayer as String: 0, kCGWindowBounds as String: bounds, kCGWindowOwnerPID as String: Int32(pid)]
            }
            precondition(windowPid(in: windows, at: CGPoint(x: 50, y: 50), excluding: [42, 43]) == 77)
            precondition(windowPid(in: windows, at: CGPoint(x: 150, y: 50), excluding: [42, 43]) == nil)
            precondition(skipReason(interference: false, monitor: true, released: true, held: false, dragImage: false, originalAlive: true, focusAllowed: true) == nil)
            precondition(skipReason(interference: true, monitor: true, released: true, held: false, dragImage: false, originalAlive: true, focusAllowed: true) == "outside_input_or_activation")
            precondition(skipReason(interference: false, monitor: false, released: true, held: false, dragImage: false, originalAlive: true, focusAllowed: true) == "monitor_lost")
            precondition(skipReason(interference: false, monitor: true, released: false, held: false, dragImage: false, originalAlive: true, focusAllowed: true) == "gesture_not_settled")
            precondition(skipReason(interference: false, monitor: true, released: true, held: true, dragImage: false, originalAlive: true, focusAllowed: true) == "gesture_not_settled")
            precondition(skipReason(interference: false, monitor: true, released: true, held: false, dragImage: true, originalAlive: true, focusAllowed: true) == "gesture_not_settled")
            precondition(skipReason(interference: false, monitor: true, released: true, held: false, dragImage: false, originalAlive: false, focusAllowed: true) == "original_application_ended")
            precondition(skipReason(interference: false, monitor: true, released: true, held: false, dragImage: false, originalAlive: true, focusAllowed: false) == "foreground_changed")
            print("Interaction lease decision checks passed"); exit(0)
        }
        InteractionRuntime().run()
    }
}
