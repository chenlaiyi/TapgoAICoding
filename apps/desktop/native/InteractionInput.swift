import ApplicationServices
import Foundation
import Darwin

struct InputProcessIdentity: Equatable {
    let seconds: UInt64
    let microseconds: UInt64
    init?(_ pid: Int32) {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        seconds = info.pbi_start_tvsec; microseconds = info.pbi_start_tvusec
    }
}

// Only the leased worker's events can be fenced; external input always passes.
struct InputFence {
    let enabled: Bool
    var stopped = false
    var pressed: Set<UInt32> = []
    var externalPressed: Set<UInt32> = []
    var blocked = 0
    var delivered = 0
    var releaseSeen = false

    mutating func driver(_ type: CGEventType, button: UInt32?) -> Bool {
        if type == .leftMouseUp || type == .rightMouseUp || type == .otherMouseUp { releaseSeen = true }
        if stopped { blocked += 1; return false }
        delivered += 1
        if let button {
            if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown { pressed.insert(button) }
            if type == .leftMouseUp || type == .rightMouseUp || type == .otherMouseUp { pressed.remove(button) }
        }
        return true
    }

    mutating func external(_ type: CGEventType, button: UInt32?) {
        if let button {
            if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
                externalPressed.insert(button)
                pressed.remove(button)
            }
            if type == .leftMouseUp || type == .rightMouseUp || type == .otherMouseUp {
                externalPressed.remove(button)
                pressed.remove(button)
            }
        }
        if enabled { stopped = true }
    }

    mutating func cancel() { if enabled { stopped = true } }
    var releasable: Set<UInt32> { pressed.subtracting(externalPressed) }
}

func inputButton(_ type: CGEventType, _ event: CGEvent) -> UInt32? {
    switch type {
    case .leftMouseDown, .leftMouseUp, .leftMouseDragged: return 0
    case .rightMouseDown, .rightMouseUp, .rightMouseDragged: return 1
    case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
        return UInt32(clamping: event.getIntegerValueField(.mouseEventButtonNumber))
    default: return nil
    }
}

func checkInputFence() {
    var fence = InputFence(enabled: true)
    precondition(fence.driver(.leftMouseDown, button: 0))
    fence.external(.mouseMoved, button: nil)
    precondition(fence.stopped && fence.releasable == [0])
    precondition(!fence.driver(.leftMouseDragged, button: 0))
    precondition(!fence.driver(.leftMouseUp, button: 0) && fence.releaseSeen)
    fence.external(.leftMouseDown, button: 0)
    precondition(fence.releasable.isEmpty)
    fence.external(.leftMouseUp, button: 0)
    precondition(fence.pressed.isEmpty)
    var observer = InputFence(enabled: false)
    observer.external(.mouseMoved, button: nil)
    precondition(observer.driver(.leftMouseDown, button: 0) && !observer.stopped)
}
