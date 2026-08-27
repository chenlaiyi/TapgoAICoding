import Foundation

/// Auto-restarting wrapper around any `HarnessTransport`.
///
/// ## Why this exists
/// v0.4.0 taught us that the `codex app-server` can exit unexpectedly
/// for reasons we don't control (model-side OOM, network timeout on the
/// upstream LLM, internal panics). Until now the only handler was
/// `onClose` in `CodexHarnessClient`, which surfaced the crash to the
/// user and left the harness dead until they manually restarted the app.
///
/// v0.4.1 makes the client **automatically recover** from these crashes:
///
///   - On unexpected exit (non-zero code), the supervisor restarts the
///     transport with exponential backoff (1s → 2s → 4s, capped).
///   - It bumps a `generation` counter and bumps the `idAllocator` so
///     old server-side ids from the dead process can never be reused
///     against the new one.
///   - After a successful restart, it fires `onRestart` so the client
///     can re-run the JSON-RPC `initialize` handshake. Without the
///     re-init the harness rejects every request with "Not initialized".
///   - After `maxAutoRestarts` failed restarts, it fires `onGiveUp`
///     and refuses to try again, so we never end up in a tight loop.
///
/// ## What the supervisor does NOT own
/// - It does not own the JSON-RPC `pending` map; that stays in
///   `CodexHarnessClient` because `send(frame:)` and frame routing
///   are already there and we want this layer to be small.
/// - It does not own approval timeouts; see `ApprovalTimeoutTracker`.
/// - It does not own idempotent-request retries; the client decides
///   per call whether to call `isIdempotent(_:)` and replay.
@MainActor
public final class HarnessSupervisor {

    public struct Config {
        /// How many auto-restarts to attempt after the first unexpected
        /// exit. Total restart budget is `maxAutoRestarts + 1` (one
        /// initial run + N retries).
        public var maxAutoRestarts: Int = 2
        /// Exponential backoff bounds. The `i`-th restart waits
        /// `lowerBound * 2^(i-1)` seconds, capped at `upperBound`.
        public var restartBackoffLowerBound: TimeInterval = 1.0
        public var restartBackoffUpperBound: TimeInterval = 8.0
        /// Method names we treat as safe to retry on transient failure.
        /// The JSON-RPC spec is stricter than this (GET-like methods),
        /// but in practice the harness only emits these.
        public var idempotentMethods: Set<String> = [
            "initialize", "thread/list", "model/list",
        ]
        public init(
            maxAutoRestarts: Int = 2,
            restartBackoffLowerBound: TimeInterval = 1.0,
            restartBackoffUpperBound: TimeInterval = 8.0,
            idempotentMethods: Set<String> = [
                "initialize", "thread/list", "model/list",
            ]
        ) {
            self.maxAutoRestarts = maxAutoRestarts
            self.restartBackoffLowerBound = restartBackoffLowerBound
            self.restartBackoffUpperBound = restartBackoffUpperBound
            self.idempotentMethods = idempotentMethods
        }
    }

    public enum State: Equatable {
        case stopped
        case running
        case restarting(attempt: Int, backoffSeconds: TimeInterval)
        case givingUp(reason: String)
    }

    public let transport: HarnessTransport
    public let config: Config

    public private(set) var state: State = .stopped
    public private(set) var restartCount = 0
    public private(set) var idAllocator = HarnessIdAllocator()
    public private(set) var idempotentAttempts: [String: Int] = [:]

    /// Fired after a successful auto-restart. The owner MUST re-run the
    /// JSON-RPC `initialize` handshake in this callback before sending
    /// any other request, or the harness will reject them.
    public var onRestart: (@MainActor () -> Void)?

    /// Fired when the supervisor has exhausted its restart budget. The
    /// owner should fail any in-flight turn with `reason`.
    public var onGiveUp: (@MainActor (String) -> Void)?

    /// Fired on every unexpected exit (even when auto-restart will
    /// succeed). Useful for telemetry / "harness recovered" UI toasts.
    public var onUnexpectedExit: (@MainActor (Int32) -> Void)?

    private var restartTask: Task<Void, Never>?
    private var generation: Int = 0

    public init(transport: HarnessTransport, config: Config = Config()) {
        self.transport = transport
        self.config = config
        transport.onClose = { [weak self] code in
            self?.handleExit(code: code)
        }
    }

    // MARK: - Lifecycle

    /// Start the underlying transport and mark the supervisor as
    /// running. Throws if the process can't be spawned.
    public func start() throws {
        generation += 1
        try transport.start()
        state = .running
    }

    /// Stop the transport cleanly. Cancels any in-flight restart task
    /// and prevents a delayed restart from resurrecting the transport.
    public func stop() {
        restartTask?.cancel()
        restartTask = nil
        generation += 1
        transport.stop()
        state = .stopped
    }

    /// Compute the exponential backoff for the `attempt`-th restart.
    /// Public so the owner / tests can assert / log the wait.
    public func backoffSeconds(forAttempt attempt: Int) -> TimeInterval {
        let base = config.restartBackoffLowerBound
        let cap = config.restartBackoffUpperBound
        let raw = base * pow(2.0, Double(max(0, attempt - 1)))
        return min(max(raw, base), cap)
    }

    /// True while the supervisor believes the transport is alive
    /// (state is .running AND the underlying transport reports isRunning).
    public var isRunning: Bool {
        if case .running = state { return transport.isRunning }
        return false
    }

    /// True while a restart is scheduled but not yet completed.
    public var isRestarting: Bool {
        if case .restarting = state { return true }
        return false
    }

    /// True if `method` is in the idempotent whitelist.
    public func isIdempotent(_ method: String) -> Bool {
        config.idempotentMethods.contains(method)
    }

    // MARK: - Id allocator forwarding

    /// Allocate a fresh JSON-RPC id. Never reuses an id, even after
    /// the previous request has been responded to or timed out.
    public func allocateId() -> Int { idAllocator.allocate() }

    /// Release an id. Safe to call multiple times.
    public func releaseId(_ id: Int) { idAllocator.release(id) }

    /// Reserve a server-supplied id so the allocator cannot pick it
    /// for an outbound request. Throws on collision (id already used
    /// by us). Resets the internal generation so the next allocate()
    /// is strictly greater than the server's id.
    public func reserveServerId(_ id: Int) throws { try idAllocator.claim(id) }

    /// True when no outbound ids are currently in flight.
    public var hasNoLiveRequests: Bool { idAllocator.isEmpty }

    // MARK: - Idempotent retry bookkeeping

    /// Record a retry attempt for the given method. Used by the client
    /// when deciding whether to retry on transient failure.
    public func recordIdempotentAttempt(method: String) {
        idempotentAttempts[method, default: 0] += 1
    }

    /// Reset retry counters. Called by the client on a successful
    /// response or when it decides to give up.
    public func resetIdempotentAttempts(method: String) {
        idempotentAttempts[method] = nil
    }

    // MARK: - Private

    private func handleExit(code: Int32) {
        // Code 0 = clean shutdown we initiated ourselves. We must
        // NOT auto-restart or the user can never quit the app.
        // Negative codes are signal kills (e.g. SIGKILL on stop());
        // treat as expected shutdown too.
        let clean = code == 0 || code < 0
        if !clean {
            onUnexpectedExit?(code)
        }
        if state == .stopped { return }
        if clean {
            state = .stopped
            return
        }

        if restartCount >= config.maxAutoRestarts {
            let reason = "Harness 进程意外退出 (\(code))，已重试 \(restartCount) 次后放弃"
            state = .givingUp(reason: reason)
            onGiveUp?(reason)
            return
        }

        restartCount += 1
        let attempt = restartCount
        let backoff = backoffSeconds(forAttempt: attempt)
        state = .restarting(attempt: attempt, backoffSeconds: backoff)
        let myGeneration = generation

        restartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            guard let self else { return }
            if Task.isCancelled { return }
            if self.generation != myGeneration { return }  // stopped mid-backoff
            do {
                try self.transport.start()
                self.state = .running
                self.onRestart?()
            } catch {
                // Restart itself failed — recurse with a synthetic
                // "exit code" so the budget ticks down.
                self.handleExit(code: -1)
            }
        }
    }
}
