import Foundation
import TapgoCore

// MARK: - Helpers

/// Tight backoff for the restart tests (50ms base, 200ms cap) so the
/// suite finishes in a couple of seconds.
private let fastSupervisorConfig = HarnessSupervisor.Config(
    maxAutoRestarts: 2,
    restartBackoffLowerBound: 0.05,
    restartBackoffUpperBound: 0.2
)

// MARK: - Per-section wrappers (called by TestMain dispatch)

@MainActor
func runHarnessSupervisorStartTransitions(_ t: TestRunner) async {
    t.section("HarnessSupervisor: start transitions to .running")
    let fake = FakeHarnessTransport()
    let sup = HarnessSupervisor(transport: fake, config: fastSupervisorConfig)
    t.expectEqual(sup.state, HarnessSupervisor.State.stopped, "starts in .stopped")
    do {
        try sup.start()
        t.expect(sup.isRunning, "isRunning true after start")
        if case .running = sup.state { t.expect(true, "state is .running") }
        else { t.expect(false, "state should be .running, got \(sup.state)") }
        t.expectEqual(sup.restartCount, 0, "no restarts on a clean start")
    } catch {
        t.expect(false, "start threw: \(error)")
    }
    sup.stop()
}

@MainActor
func runHarnessSupervisorStopCancels(_ t: TestRunner) async {
    t.section("HarnessSupervisor: stop cancels pending restart")
    let fake = FakeHarnessTransport()
    let sup = HarnessSupervisor(transport: fake, config: fastSupervisorConfig)
    var gaveUp: [String] = []
    sup.onGiveUp = { reason in gaveUp.append(reason) }
    try? sup.start()
    fake.simulateExit(code: 1)
    if case .restarting = sup.state { t.expect(true, "state is .restarting after exit") }
    else { t.expect(false, "state should be .restarting, got \(sup.state)") }
    sup.stop()
    let deadline = Date().addingTimeInterval(0.5)
    while Date() < deadline {
        try? await Task.sleep(nanoseconds: 20_000_000)
        if case .stopped = sup.state { break }
    }
    if case .stopped = sup.state { t.expect(true, "state is .stopped after stop()") }
    else { t.expect(false, "state should be .stopped, got \(sup.state)") }
    t.expectEqual(gaveUp, [], "stop() must not fire onGiveUp")
    t.expect(!fake.isRunning, "transport not running after stop()")
}

@MainActor
func runHarnessSupervisorCleanExit(_ t: TestRunner) async {
    t.section("HarnessSupervisor: clean exit (code 0) does not restart")
    let fake = FakeHarnessTransport()
    let sup = HarnessSupervisor(transport: fake, config: fastSupervisorConfig)
    var unexpected: [Int32] = []
    sup.onUnexpectedExit = { code in unexpected.append(code) }
    try? sup.start()
    fake.simulateExit(code: 0)
    let d3 = Date().addingTimeInterval(0.3)
    while Date() < d3 { try? await Task.sleep(nanoseconds: 20_000_000) }
    if case .stopped = sup.state { t.expect(true, "clean exit → .stopped") }
    else { t.expect(false, "clean exit should leave .stopped, got \(sup.state)") }
    t.expectEqual(sup.restartCount, 0, "no restarts on clean exit")
    t.expectEqual(unexpected, [], "clean exit does not fire onUnexpectedExit")
    t.expectEqual(fake.startCount, 1, "transport started once, never restarted")
}

@MainActor
func runHarnessSupervisorRestartAfterBackoff(_ t: TestRunner) async {
    t.section("HarnessSupervisor: unexpected exit fires onRestart after backoff")
    let fake = FakeHarnessTransport()
    let sup = HarnessSupervisor(transport: fake, config: fastSupervisorConfig)
    var restarts = 0
    var unexpected: [Int32] = []
    sup.onRestart = { restarts += 1 }
    sup.onUnexpectedExit = { code in unexpected.append(code) }
    try? sup.start()
    fake.simulateExit(code: 134)
    t.expectEqual(unexpected, [134], "onUnexpectedExit fired immediately")
    let deadline = Date().addingTimeInterval(1.0)
    while Date() < deadline && restarts == 0 {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    t.expectEqual(restarts, 1, "onRestart fired once after backoff")
    t.expectEqual(sup.restartCount, 1, "restartCount = 1")
    t.expectEqual(fake.startCount, 2, "transport start() called twice")
    if case .running = sup.state { t.expect(true, "state back to .running") }
    else { t.expect(false, "state should be .running, got \(sup.state)") }
    sup.stop()
}

@MainActor
func runHarnessSupervisorGivesUp(_ t: TestRunner) async {
    t.section("HarnessSupervisor: gives up after maxAutoRestarts")
    let fake = FakeHarnessTransport()
    let oneMore = HarnessSupervisor.Config(
        maxAutoRestarts: 1,
        restartBackoffLowerBound: 0.05,
        restartBackoffUpperBound: 0.1
    )
    let sup = HarnessSupervisor(transport: fake, config: oneMore)
    var gaveUps: [String] = []
    sup.onGiveUp = { reason in gaveUps.append(reason) }
    try? sup.start()
    fake.simulateExit(code: 1)
    let d5a = Date().addingTimeInterval(0.5)
    while Date() < d5a && fake.startCount < 2 {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    t.expectEqual(fake.startCount, 2, "second start attempted")
    fake.simulateExit(code: 2)
    fake.pendingStartError = HarnessTransportError.notRunning
    let d5b = Date().addingTimeInterval(0.5)
    while Date() < d5b && gaveUps.isEmpty {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    t.expectEqual(gaveUps.count, 1, "onGiveUp fired exactly once")
    t.expect(gaveUps.first?.contains("已重试") == true, "give-up reason mentions retry count")
    if case .givingUp = sup.state { t.expect(true, "state is .givingUp") }
    else { t.expect(false, "state should be .givingUp, got \(sup.state)") }
}

@MainActor
func runHarnessSupervisorBackoff(_ t: TestRunner) {
    t.section("HarnessSupervisor: backoff is exponential and capped")
    let fake = FakeHarnessTransport()
    let sup = HarnessSupervisor(transport: fake, config: HarnessSupervisor.Config(
        maxAutoRestarts: 5,
        restartBackoffLowerBound: 1.0,
        restartBackoffUpperBound: 4.0
    ))
    t.expectEqual(sup.backoffSeconds(forAttempt: 1), 1.0, "attempt 1 = 1.0s")
    t.expectEqual(sup.backoffSeconds(forAttempt: 2), 2.0, "attempt 2 = 2.0s")
    t.expectEqual(sup.backoffSeconds(forAttempt: 3), 4.0, "attempt 3 = 4.0s (capped)")
    t.expectEqual(sup.backoffSeconds(forAttempt: 4), 4.0, "attempt 4 = 4.0s (capped)")
    t.expectEqual(sup.backoffSeconds(forAttempt: 10), 4.0, "attempt 10 = 4.0s (capped)")
}

@MainActor
func runHarnessSupervisorIdempotentWhitelist(_ t: TestRunner) {
    t.section("HarnessSupervisor: idempotent whitelist")
    let fake = FakeHarnessTransport()
    let sup = HarnessSupervisor(transport: fake, config: fastSupervisorConfig)
    t.expect(sup.isIdempotent("initialize"), "initialize is idempotent")
    t.expect(sup.isIdempotent("thread/list"), "thread/list is idempotent")
    t.expect(sup.isIdempotent("model/list"), "model/list is idempotent")
    t.expect(!sup.isIdempotent("thread/start"), "thread/start is NOT idempotent")
    t.expect(!sup.isIdempotent("turn/start"), "turn/start is NOT idempotent")
    t.expect(!sup.isIdempotent("turn/interrupt"), "turn/interrupt is NOT idempotent")
}

@MainActor
func runHarnessSupervisorIdAllocator(_ t: TestRunner) {
    t.section("HarnessSupervisor: idAllocator is per-supervisor and resets on restart")
    let fake = FakeHarnessTransport()
    let sup = HarnessSupervisor(transport: fake, config: fastSupervisorConfig)
    let id1 = sup.allocateId()
    let id2 = sup.allocateId()
    t.expect(id2 > id1, "allocateId is strictly increasing (\(id1) < \(id2))")
    sup.releaseId(id1)
    let id3 = sup.allocateId()
    t.expect(id3 != id1, "released id is never reused (id3=\(id3), id1=\(id1))")
    t.expect(id3 > id2, "still strictly increasing after release")
}

@MainActor
func runHarnessSupervisorReserveServerId(_ t: TestRunner) {
    t.section("HarnessSupervisor: reserveServerId prevents collision")
    let fake = FakeHarnessTransport()
    let sup = HarnessSupervisor(transport: fake, config: fastSupervisorConfig)
    let ourId = sup.allocateId()
    do {
        try sup.reserveServerId(ourId)
        t.expect(false, "reserveServerId on our own id should throw")
    } catch HarnessIdError.collision {
        t.expect(true, "collision thrown for server id we already use")
    } catch {
        t.expect(false, "unexpected error: \(error)")
    }
    do {
        try sup.reserveServerId(500)
        let next = sup.allocateId()
        t.expect(next > 500, "next allocate is > 500 (got \(next))")
    } catch {
        t.expect(false, "reserveServerId(500) threw: \(error)")
    }
}

@MainActor
func runHarnessSupervisorRetryBookkeeping(_ t: TestRunner) {
    t.section("HarnessSupervisor: idempotent retry bookkeeping")
    let fake = FakeHarnessTransport()
    let sup = HarnessSupervisor(transport: fake, config: fastSupervisorConfig)
    t.expectEqual(sup.idempotentAttempts["initialize"], nil, "starts empty")
    sup.recordIdempotentAttempt(method: "initialize")
    sup.recordIdempotentAttempt(method: "initialize")
    t.expectEqual(sup.idempotentAttempts["initialize"], 2, "two records")
    sup.resetIdempotentAttempts(method: "initialize")
    t.expectEqual(sup.idempotentAttempts["initialize"], nil, "reset clears")
}
