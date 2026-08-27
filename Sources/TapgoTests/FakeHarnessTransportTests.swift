import Foundation
import TapgoCore

// MARK: - Per-section wrappers (called by TestMain dispatch)

@MainActor
func runFakeHarnessTransportStartSendExit(_ t: TestRunner) {
    t.section("FakeHarnessTransport: start + send + exit")
    let fake = FakeHarnessTransport()
    t.expect(!fake.isRunning, "starts not running")
    do { try fake.start() } catch {
        t.expect(false, "start should not throw on a fresh fake: \(error)")
        return
    }
    t.expect(fake.isRunning, "isRunning after start")
    t.expectEqual(fake.startCount, 1, "startCount = 1")

    var notifications: [JSONValue] = []
    fake.onNotification = { n in notifications.append(n) }

    do {
        try fake.send(frame: .object(["id": .int(7), "method": .string("ping")]))
    } catch {
        t.expect(false, "send should not throw on running fake: \(error)")
    }
    t.expectEqual(fake.sentFrames.count, 1, "sentFrames records the frame")

    fake.sendNotification(method: "turn/started")
    fake.sendServerRequest(id: 99, method: "execApproval")
    t.expectEqual(notifications.count, 2, "onNotification fired twice")

    fake.respond(id: 7, result: .string("ok"))
    fake.respondError(id: 8, code: -32601, message: "Method not found")
    t.expectEqual(notifications.count, 4, "respond + respondError also fire onNotification")

    var closeCodes: [Int32] = []
    fake.onClose = { code in closeCodes.append(code) }
    fake.simulateExit(code: 137)
    t.expect(!fake.isRunning, "isRunning flips false after exit")
    t.expectEqual(closeCodes, [137], "onClose fired with the exit code")
}

@MainActor
func runFakeHarnessTransportSendAfterExitThrows(_ t: TestRunner) {
    t.section("FakeHarnessTransport: send after exit throws")
    let fake = FakeHarnessTransport()
    try? fake.start()
    fake.simulateExit(code: 1)
    do {
        try fake.send(frame: .object(["id": .int(1), "method": .string("x")]))
        t.expect(false, "send after exit must throw")
    } catch HarnessTransportError.notRunning {
        t.expect(true, "send after exit throws .notRunning")
    } catch {
        t.expect(false, "unexpected error: \(error)")
    }
}

@MainActor
func runFakeHarnessTransportStartFailureIsOneShot(_ t: TestRunner) {
    t.section("FakeHarnessTransport: simulateStartFailure is one-shot")
    let fake = FakeHarnessTransport()
    fake.pendingStartError = HarnessTransportError.notRunning
    do {
        try fake.start()
        t.expect(false, "start should throw when pendingStartError is set")
    } catch HarnessTransportError.notRunning {
        t.expect(true, "threw the staged error")
    } catch {
        t.expect(false, "unexpected error: \(error)")
    }
    t.expect(!fake.isRunning, "did not transition to running")
    t.expectEqual(fake.startCount, 0, "startCount unchanged on failure")
    do {
        try fake.start()
        t.expect(fake.isRunning, "second start succeeds (one-shot error consumed)")
        t.expectEqual(fake.startCount, 1, "startCount incremented on success")
    } catch {
        t.expect(false, "second start threw: \(error)")
    }
}

@MainActor
func runFakeHarnessTransportExitIsIdempotent(_ t: TestRunner) {
    t.section("FakeHarnessTransport: exit is idempotent")
    let fake = FakeHarnessTransport()
    try? fake.start()
    var closeCount = 0
    fake.onClose = { _ in closeCount += 1 }
    fake.simulateExit(code: 1)
    fake.simulateExit(code: 1)
    t.expectEqual(closeCount, 1, "simulateExit is a no-op when already dead")
}

@MainActor
func runFakeHarnessTransportStopAlone(_ t: TestRunner) {
    t.section("FakeHarnessTransport: stop() does not fire onClose by itself")
    let fake = FakeHarnessTransport()
    try? fake.start()
    var closeCodes: [Int32] = []
    fake.onClose = { code in closeCodes.append(code) }
    fake.stop()
    t.expectEqual(closeCodes, [], "stop() alone does NOT fire onClose")
    t.expect(fake.isRunning, "stop() alone leaves isRunning true (mirrors LocalHarnessTransport)")
}
