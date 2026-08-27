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

/// Deterministic transport used for lifecycle edge cases that the general
/// FakeHarnessTransport intentionally does not model (repeated spawn failures
/// and an onClose callback delivered synchronously by stop()).
@MainActor
private final class ScriptedSupervisorTransport: HarnessTransport {
    var onNotification: ((JSONValue) -> Void)?
    var onClose: ((Int32) -> Void)?

    private(set) var isRunning = false
    private(set) var startAttempts = 0
    private(set) var successfulStarts = 0
    var failingStartAttempts: Set<Int> = []
    var closeCodeOnStop: Int32?

    func start() throws {
        startAttempts += 1
        if failingStartAttempts.contains(startAttempts) {
            isRunning = false
            throw HarnessTransportError.notRunning
        }
        successfulStarts += 1
        isRunning = true
    }

    func stop() {
        isRunning = false
        if let closeCodeOnStop {
            onClose?(closeCodeOnStop)
        }
    }

    func send(frame: JSONValue) throws {
        guard isRunning else { throw HarnessTransportError.notRunning }
    }

    func simulateExit(code: Int32) {
        guard isRunning else { return }
        isRunning = false
        onClose?(code)
    }
}

@MainActor
private func waitForSupervisor(
    timeout: TimeInterval = 1.0,
    until predicate: @escaping @MainActor () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if predicate() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return predicate()
}

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
    t.expectEqual(fake.startCount, 1, "cancelled backoff never starts a replacement")

    // stop() must publish .stopped before transport.stop(), because real
    // transports may synchronously deliver either a zero or signal exit.
    for code: Int32 in [0, -15] {
        let stoppingTransport = ScriptedSupervisorTransport()
        stoppingTransport.closeCodeOnStop = code
        let stoppingSupervisor = HarnessSupervisor(
            transport: stoppingTransport,
            config: fastSupervisorConfig
        )
        var unexpected: [Int32] = []
        var restarts = 0
        var stopGiveUps = 0
        stoppingSupervisor.onUnexpectedExit = { unexpected.append($0) }
        stoppingSupervisor.onRestart = { restarts += 1 }
        stoppingSupervisor.onGiveUp = { _ in stopGiveUps += 1 }
        try? stoppingSupervisor.start()

        stoppingSupervisor.stop()
        try? await Task.sleep(nanoseconds: 150_000_000)

        t.expectEqual(unexpected, [], "explicit stop code \(code) is expected")
        t.expectEqual(restarts, 0, "explicit stop code \(code) never restarts")
        t.expectEqual(stopGiveUps, 0, "explicit stop code \(code) never gives up")
        t.expectEqual(stoppingTransport.startAttempts, 1, "explicit stop code \(code) starts once")
        t.expectEqual(stoppingSupervisor.state, .stopped, "explicit stop code \(code) stays stopped")
    }
}

@MainActor
func runHarnessSupervisorRunningExitCodes(_ t: TestRunner) async {
    t.section("HarnessSupervisor: code 0 and signal exits restart while running")

    for code: Int32 in [0, -9] {
        let fake = ScriptedSupervisorTransport()
        let sup = HarnessSupervisor(transport: fake, config: fastSupervisorConfig)
        var unexpected: [Int32] = []
        var restarts = 0
        sup.onUnexpectedExit = { unexpected.append($0) }
        sup.onRestart = { restarts += 1 }
        try? sup.start()

        fake.simulateExit(code: code)
        t.expectEqual(unexpected, [code], "running exit code \(code) is reported immediately")
        let restarted = await waitForSupervisor {
            restarts == 1 && fake.successfulStarts == 2
        }

        t.expect(restarted, "running exit code \(code) reaches replacement start")
        t.expectEqual(sup.restartCount, 1, "running exit code \(code) consumes one retry")
        t.expectEqual(fake.startAttempts, 2, "running exit code \(code) starts replacement once")
        t.expectEqual(sup.state, .running, "running exit code \(code) returns to running")
        sup.stop()
    }
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
    t.section("HarnessSupervisor: restart start failures consume retry budget")
    let fake = ScriptedSupervisorTransport()
    fake.failingStartAttempts = [2, 3]
    let twoRetries = HarnessSupervisor.Config(
        maxAutoRestarts: 2,
        restartBackoffLowerBound: 0.02,
        restartBackoffUpperBound: 0.02
    )
    let sup = HarnessSupervisor(transport: fake, config: twoRetries)
    var gaveUps: [String] = []
    var unexpected: [Int32] = []
    var restarts = 0
    sup.onGiveUp = { reason in gaveUps.append(reason) }
    sup.onUnexpectedExit = { unexpected.append($0) }
    sup.onRestart = { restarts += 1 }
    try? sup.start()
    fake.simulateExit(code: 0)

    let gaveUp = await waitForSupervisor {
        gaveUps.count == 1 && fake.startAttempts == 3
    }
    // Wait beyond another backoff interval to catch accidental duplicate
    // terminal callbacks/tasks.
    try? await Task.sleep(nanoseconds: 100_000_000)

    t.expect(gaveUp, "two failed replacement starts reach give-up")
    t.expectEqual(fake.startAttempts, 3, "initial start plus exactly two restart attempts")
    t.expectEqual(fake.successfulStarts, 1, "both replacement starts failed")
    t.expectEqual(sup.restartCount, 2, "both failed starts consume retry budget")
    t.expectEqual(unexpected, [0, -1, -1], "zero exit and both spawn failures are unexpected")
    t.expectEqual(restarts, 0, "onRestart is not fired for failed starts")
    t.expectEqual(gaveUps.count, 1, "onGiveUp fired exactly once")
    t.expect(gaveUps.first?.contains("已重试 2 次") == true, "give-up reason reports exhausted budget")
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
