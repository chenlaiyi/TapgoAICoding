import Foundation
import TapgoCore

/// Persistent JSON-RPC client for the openai codex app-server harness.
///
/// This class is the *high-level* wrapper. It owns the JSON-RPC
/// request/response correlation and the run lifecycle
/// (initialize → thread/start → turn/start → turn/completed). The
/// actual byte stream lives in a `HarnessTransport` — either a
/// `LocalHarnessTransport` (run the harness on this Mac) or a
/// `RemoteSSHHarnessTransport` (run it on a remote host over SSH).
///
/// One `HarnessTransport` is created per thread that needs a run.
/// Threads bound to a remote project get a `RemoteSSHHarnessTransport`;
/// threads bound to a local project (or no project) get a
/// `LocalHarnessTransport`. Switching transport is what gives us a
/// single source of truth — the model sees the same stdout/stderr
/// the user sees in the chat, because the harness is *actually*
/// running on the remote host.
///
/// All on-disk state for the local transport lives under the
/// isolated `~/Library/Application Support/Tapgo AICoding/codex/`
/// directory; we never touch `~/.codex/`. The remote transport
/// lives in a user-chosen directory on the remote host (default
/// `~/.tapgo-aicoding/remote/`) and contains only non-sensitive
/// config — the API key is delivered at runtime through the SSH
/// subprocess's stdin.
@MainActor
final class CodexHarnessClient {
    enum RunState: Equatable {
        case idle
        case running(threadId: String?)
        case finished
        case failed(String)
    }

    let transport: HarnessTransport
    /// v0.4.1: wraps `transport` with auto-restart on unexpected exit
    /// and owns the monotonic JSON-RPC id allocator.
    let supervisor: HarnessSupervisor
    /// v0.4.1: tracks pending server-initiated approval requests and
    /// auto-declines them after `ApprovalTimeoutTracker.defaultDeadline`
    /// so a missed approval can't wedge the harness forever.
    private var approvalTimeouts = ApprovalTimeoutTracker()
    private var approvalTimeoutTasks: [String: Task<Void, Never>] = [:]
    private var approvalRequests: [String: ApprovalRequest] = [:]
    private let approvalDeadline: TimeInterval

    private(set) var state: RunState = .idle
    private var pending: [Int: (Result<JSONValue, Error>) -> Void] = [:]
    private var eventHandler: (@MainActor (ExecEvent) -> Void)?

    private(set) var activeThreadId: String?
    private var activeTurnId: String?
    private var turnContinuation: CheckedContinuation<RunState, Never>?
    /// Set as soon as the user presses stop, including during initialize /
    /// thread start when no turn id exists yet.
    private var cancelRequested = false

    init(
        transport: HarnessTransport,
        supervisorConfig: HarnessSupervisor.Config = HarnessSupervisor.Config(),
        approvalDeadline: TimeInterval = ApprovalTimeoutTracker.defaultDeadline
    ) {
        self.transport = transport
        self.supervisor = HarnessSupervisor(transport: transport, config: supervisorConfig)
        self.approvalDeadline = approvalDeadline
        transport.onNotification = { [weak self] frame in
            self?.handleFrame(frame)
        }
        // Note: do NOT install `transport.onClose` here — `HarnessSupervisor`
        // already owns it. The supervisor calls `onRestart` / `onGiveUp`
        // after deciding what to do with the exit.
        supervisor.onRestart = { [weak self] in
            self?.supervisorRestarted()
        }
        supervisor.onGiveUp = { [weak self] reason in
            self?.supervisorGaveUp(reason: reason)
        }
        // A restarted process cannot contain the in-flight turn or pending RPCs
        // from the process that exited. Fail the current run immediately; the
        // SessionStore can then close this per-thread runner and safely retry.
        supervisor.onUnexpectedExit = { [weak self] code in
            self?.serverStopped(code: code)
        }
        // v0.4.1: when an approval hits its 60s deadline, auto-decline
        // by replying with the JSON-RPC `decline` result. The harness
        // unblocks immediately and the user sees a brief "approval
        // timed out" message in the trajectory.
        approvalTimeouts.onExpire = { [weak self] rpcIdString in
            guard let self,
                  let request = self.approvalRequests.removeValue(forKey: rpcIdString),
                  let frame = request.rpcResponseFrame(approve: false) else { return }
            self.approvalTimeoutTasks.removeValue(forKey: rpcIdString)
            do {
                try self.transport.send(frame: frame)
                self.eventHandler?(.approvalExpired(request))
                TapgoConfig.log("[harness] auto-declined approval id=\(rpcIdString) after timeout")
            } catch {
                TapgoConfig.log("[harness] failed to send auto-decline: \(error.localizedDescription)")
            }
        }
    }

    /// Re-run the JSON-RPC `initialize` handshake after a supervisor
    /// auto-restart. Without this the new process rejects every request
    /// with "Not initialized".
    private func supervisorRestarted() {
        // Transport loss already settles the old run through
        // `onUnexpectedExit`. Never initialize a replacement process for a
        // turn whose continuation has been failed and is being torn down.
        guard case .running = state else { return }
        TapgoConfig.log("[harness] supervisor auto-restarted; re-initializing")
        Task { @MainActor in
            do {
                _ = try await self.request(method: "initialize", params: [
                    "clientInfo": .object([
                        "name": .string(TapgoConfig.clientInfoName),
                        "title": .string(TapgoConfig.clientInfoTitle),
                        "version": .string(TapgoConfig.clientInfoVersion),
                    ]),
                ])
                try? self.transport.send(frame: .object([
                    "method": .string("initialized"),
                    "params": .object([:]),
                ]))
            } catch {
                TapgoConfig.log("[harness] post-restart initialize failed: \(error.localizedDescription)")
                self.serverStopped(code: -1)
            }
        }
    }

    /// Called when the supervisor has exhausted its restart budget.
    /// Fail any in-flight turn with the reason so the UI can show it.
    private func supervisorGaveUp(reason: String) {
        TapgoConfig.log("[harness] supervisor gave up: \(reason)")
        if case .running = state {
            eventHandler?(.turnCompleted(status: "failed", errorMessage: reason, usage: nil))
            finish(.failed(reason))
        }
    }

    /// True when the underlying transport is alive and ready to
    /// accept JSON-RPC frames. Reads through the supervisor so a
    /// restart-in-progress correctly shows up as "not available".
    var isAvailable: Bool {
        supervisor.isRunning
    }

    /// Read-only snapshot accessor for the SessionStore so it can persist
    /// the harness-side thread id on the local `TapgoCore.Thread`.
    private(set) var activeThreadIdSnapshot: String?

    // MARK: - Run lifecycle

    /// Start (or reattach to) a turn on a thread. Returns when the
    /// turn completes. Streams events through `onEvent`.
    func run(
        prompt: String,
        resumeThreadId: String?,
        cwd: String?,
        images: [URL],
        baseInstructions: String? = nil,
        resumeBaseInstructions: String? = nil,
        onEvent: @escaping @MainActor (ExecEvent) -> Void
    ) async -> RunState {
        if case .running = state {
            return .failed("已有任务在执行")
        }
        cancelRequested = false
        defer { cancelRequested = false }
        do {
            try supervisor.start()

            // Attach the event handler *before* the handshake / thread call so
            // we never drop the harness's `thread/started` notification (which
            // carries the thread id we must persist as `harnessThreadId` for
            // `thread/resume` on the next turn). The harness may emit it as soon
            // as `thread/start`/`thread/resume` is acked, before the app-side
            // `eventHandler` assignment below was previously reached.
            eventHandler = onEvent

            // The codex app-server requires the JSON-RPC `initialize`
            // handshake before any other request — otherwise it replies
            // with "Not initialized". Do it once per transport, then
            // send the `initialized` notification and let the harness
            // settle before the first real request.
            _ = try await request(method: "initialize", params: [
                "clientInfo": .object([
                    "name": .string(TapgoConfig.clientInfoName),
                    "title": .string(TapgoConfig.clientInfoTitle),
                    "version": .string(TapgoConfig.clientInfoVersion),
                ]),
            ])
            try throwIfCancelled()
            try? transport.send(frame: .object([
                "method": .string("initialized"),
                "params": .object([:]),
            ]))
            // Small settle so the harness finishes processing the
            // `initialized` notification before thread/start (mirrors the
            // reference integration test).
            try? await Task.sleep(nanoseconds: 400_000_000)
            try throwIfCancelled()

            let threadId: String
            if let resumeThreadId {
                do {
                    var params = threadRuntimeParams(
                        cwd: cwd,
                        baseInstructions: resumeBaseInstructions,
                        includeServiceName: false,
                        clearBaseInstructionsWhenNil: true
                    )
                    params["threadId"] = .string(resumeThreadId)
                    let response = try await request(method: "thread/resume", params: params)
                    threadId = response.objectValue?["thread"]?.objectValue?["id"]?.stringValue
                        ?? resumeThreadId
                } catch let error as HarnessError where error.isMissingRollout {
                    // App-server may prune an old rollout while the native app
                    // still has its local transcript. Start a replacement
                    // thread with the bounded recovery baseInstructions built
                    // by SessionStore instead of dropping the user's context.
                    TapgoConfig.log("[harness] rollout unavailable; recovering with thread/start")
                    threadId = try await startThread(cwd: cwd, baseInstructions: baseInstructions)
                }
            } else {
                threadId = try await startThread(cwd: cwd, baseInstructions: baseInstructions)
            }
            activeThreadId = threadId
            activeThreadIdSnapshot = threadId
            eventHandler = onEvent
            state = .running(threadId: threadId)
            try throwIfCancelled()

            // Build user input — text first, then any local images.
            var input: [JSONValue] = []
            if !prompt.isEmpty {
                input.append(.object([
                    "type": .string("text"),
                    "text": .string(prompt),
                ]))
            }
            for img in images {
                input.append(.object([
                    "type": .string("localImage"),
                    "path": .string(img.path),
                ]))
            }
            if input.isEmpty {
                throw HarnessError.invalidResponse("没有可发送的输入内容")
            }
            var turnParams: [String: JSONValue] = [
                "threadId": .string(threadId),
                "input": .array(input),
            ]
            if let effort = TapgoConfig.reasoningEffort {
                turnParams["effort"] = .string(effort)
            }
            // v0.4.1: sweep expired approval timers at the start of every
            // turn so we never carry over a deadline from the previous
            // turn (the harness process is gone anyway after restart).
            approvalTimeouts.sweep()
            let resp = try await request(method: "turn/start", params: turnParams)
            activeTurnId = resp.objectValue?["turn"]?.objectValue?["id"]?.stringValue
            try throwIfCancelled()

            return await withCheckedContinuation { (cont: CheckedContinuation<RunState, Never>) in
                // app-server may emit turn/completed in the same stdout chunk
                // immediately after the turn/start response. In that case
                // finish() ran before this continuation existed; return the
                // already-terminal state instead of waiting forever.
                if case .running = state {
                    turnContinuation = cont
                } else {
                    cont.resume(returning: state)
                }
            }
        } catch {
            if cancelRequested || (error as? HarnessError)?.isCancellation == true {
                eventHandler?(.turnCompleted(status: "interrupted", errorMessage: nil, usage: nil))
                state = .finished
                activeTurnId = nil
                eventHandler = nil
                return state
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .failed(message)
            activeTurnId = nil
            eventHandler = nil
            return state
        }
    }

    /// Cancel the active turn. Sends `turn/interrupt` to the harness.
    func cancel() {
        guard !cancelRequested else { return }
        cancelRequested = true
        guard let threadId = activeThreadId, let turnId = activeTurnId else {
            abortHandshakeForCancellation()
            return
        }
        Task {
            do {
                _ = try await request(method: "turn/interrupt", params: [
                    "threadId": .string(threadId),
                    "turnId": .string(turnId),
                ])
            } catch {
                // If interrupt itself cannot reach app-server, fail closed and
                // terminate the transport instead of leaving a hidden turn live.
                transport.stop()
                if case .running = state {
                    eventHandler?(.turnCompleted(status: "interrupted", errorMessage: nil, usage: nil))
                    finish(.finished)
                }
            }
        }
    }

    /// Add new user input to the active turn without interrupting it.
    /// Codex app-server rejects the request if the turn changed between the
    /// queue-row click and delivery, allowing the caller to keep that message
    /// queued as a normal follow-up instead of losing it.
    @discardableResult
    func steer(text: String, images: [URL]) async throws -> String {
        guard case .running = state,
              let threadId = activeThreadId,
              let turnId = activeTurnId else {
            throw HarnessError.invalidResponse("当前任务尚未准备好接收调整")
        }
        let params = try TurnSteerPayload.make(
            threadId: threadId,
            expectedTurnId: turnId,
            text: text,
            imagePaths: images.map(\.path)
        )
        let response = try await request(method: "turn/steer", params: params)
        guard let acceptedTurnId = response.objectValue?["turnId"]?.stringValue,
              !acceptedTurnId.isEmpty else {
            throw HarnessError.invalidResponse("调整方向请求未返回任务 ID")
        }
        return acceptedTurnId
    }

    /// Resolve a pending approval. Current app-server versions send approval
    /// as a server-initiated JSON-RPC request, so we must echo the original
    /// top-level id and use `accept` / `decline`.
    @discardableResult
    func respondToApproval(_ request: ApprovalRequest, approve: Bool) -> Bool {
        guard let frame = request.rpcResponseFrame(approve: approve) else {
            TapgoConfig.log("[harness] rejected approval without JSON-RPC request id: \(request.id)")
            return false
        }
        // Disarm the timeout so it doesn't auto-decline a decision the
        // user already made.
        do {
            try transport.send(frame: frame)
            let key = approvalKey(for: request)
            approvalTimeouts.disarm(rpcRequestId: key)
            approvalTimeoutTasks.removeValue(forKey: key)?.cancel()
            approvalRequests.removeValue(forKey: key)
            return true
        } catch {
            TapgoConfig.log("[harness] approval response failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Tear down the underlying transport and wait for the subprocess to exit
    /// before a queued turn starts another app-server.
    func shutdownAndWait() async {
        // supervisor.stop() cancels any pending restart task before
        // signalling the transport to terminate.
        supervisor.stop()
        await transport.stopAndWait()
        cancelAllApprovalTimeouts()
        state = .idle
    }

    private func approvalKey(for request: ApprovalRequest) -> String {
        if let value = request.rpcRequestId?.stringValue { return value }
        if let value = request.rpcRequestId?.intValue { return String(value) }
        return request.id
    }

    private func armApprovalTimeout(for request: ApprovalRequest) {
        let key = approvalKey(for: request)
        approvalTimeoutTasks.removeValue(forKey: key)?.cancel()
        approvalRequests[key] = request
        approvalTimeouts.arm(
            rpcRequestId: key,
            deadline: approvalDeadline
        )
        let nanoseconds = UInt64(max(0, approvalDeadline) * 1_000_000_000)
        approvalTimeoutTasks[key] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.approvalTimeouts.sweep()
        }
    }

    private func cancelAllApprovalTimeouts() {
        for task in approvalTimeoutTasks.values { task.cancel() }
        approvalTimeoutTasks.removeAll()
        approvalRequests.removeAll()
        approvalTimeouts.disarmAll()
    }

    // MARK: - JSON-RPC transport

    private func startThread(cwd: String?, baseInstructions: String?) async throws -> String {
        let params = threadRuntimeParams(
            cwd: cwd,
            baseInstructions: baseInstructions,
            includeServiceName: true,
            clearBaseInstructionsWhenNil: false
        )
        let response = try await request(method: "thread/start", params: params)
        guard let id = response.objectValue?["thread"]?.objectValue?["id"]?.stringValue else {
            throw HarnessError.invalidResponse("thread/start 未返回 thread.id")
        }
        return id
    }

    /// Runtime policy is re-applied on resume so changing the UI from full
    /// Read the current `account/rateLimits` snapshot from the harness.
    /// This is the authoritative source for the composer popover: 5h +
    /// weekly windows, credits balance, and `rateLimitsByLimitId` for
    /// per-tool quotas. The harness also pushes `account/rateLimits/updated`
    /// notifications, which `ExecEventParser` decodes into the same type.
    ///
    /// Must be called *after* `initialize` / `initialized`, otherwise the
    /// harness returns "Not initialized". `run()` establishes the
    /// handshake before any user-visible request fires, so callers can use
    /// this while a turn is idle or running.
    func readRateLimits() async throws -> RateLimitsSnapshot {
        let response = try await request(method: "account/rateLimits/read", params: [:])
        if let snap = RateLimitsSnapshot.fromJSON(response) {
            return snap
        }
        // Older harnesses may wrap the payload under `result` instead of
        // returning the dict directly; accept either shape.
        if let snap = RateLimitsSnapshot.fromJSON(response.objectValue?["result"]) {
            return snap
        }
        // Nothing useful in the response — surface an empty snapshot so the
        // UI can still show "等待服务端响应" without crashing.
        return RateLimitsSnapshot(
            primary: nil,
            secondary: nil,
            credits: nil,
            planType: nil,
            byLimitId: [],
            fetchedAt: Date()
        )
    }

    /// access to read-only (or vice versa) takes effect on the existing
    /// thread. `serviceName` is accepted only by thread/start.
    private func threadRuntimeParams(
        cwd: String?,
        baseInstructions: String?,
        includeServiceName: Bool,
        clearBaseInstructionsWhenNil: Bool
    ) -> [String: JSONValue] {
        var params: [String: JSONValue] = [
            "model": .string(TapgoConfig.modelName),
            "modelProvider": .string(TapgoConfig.modelProvider),
            "approvalPolicy": .string(TapgoConfig.approvalPolicy.rawValue),
            "sandbox": .string(TapgoConfig.sandboxMode.rawValue),
        ]
        if includeServiceName { params["serviceName"] = .string(TapgoConfig.serviceName) }
        if let cwd, !cwd.isEmpty { params["cwd"] = .string(cwd) }
        if let baseInstructions, !baseInstructions.isEmpty {
            params["baseInstructions"] = .string(baseInstructions)
        } else if clearBaseInstructionsWhenNil {
            params["baseInstructions"] = .null
        }
        return params
    }

    private func request(method: String, params: [String: JSONValue]) async throws -> JSONValue {
        let id = supervisor.allocateId()
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let callback = self?.pending.removeValue(forKey: id) else { return }
                self?.supervisor.releaseId(id)
                callback(.failure(HarnessError.timeout(method)))
            }
            do {
                try transport.send(frame: .object([
                    "id": .int(id),
                    "method": .string(method),
                    "params": .object(params),
                ]))
            } catch {
                pending.removeValue(forKey: id)
                supervisor.releaseId(id)
                continuation.resume(throwing: error)
            }
        }
    }

    private func throwIfCancelled() throws {
        if cancelRequested { throw HarnessError.cancelled }
    }

    private func abortHandshakeForCancellation() {
        let callbacks = pending
        pending.removeAll()
        for (id, callback) in callbacks {
            supervisor.releaseId(id)
            callback(.failure(HarnessError.cancelled))
        }
        transport.stop()
    }

    private func handleFrame(_ value: JSONValue) {
        guard let object = value.objectValue else { return }
        TapgoConfig.log("← \(value.toJSONString().prefix(800))")
        // A server request also has a top-level `id`. Route method-bearing
        // frames before client responses so an approval id can never collide
        // with one of our pending request ids.
        if let method = object["method"]?.stringValue {
            let params = object["params"]?.objectValue ?? [:]
            handleNotification(
                method: method,
                params: params,
                rpcRequestId: object["id"]
            )
            return
        }
        if let id = object["id"]?.intOrBoolAsInt, let cont = pending.removeValue(forKey: id) {
            supervisor.releaseId(id)
            if let error = object["error"]?.objectValue {
                let message = error["message"]?.stringValue ?? "未知错误"
                let code = error["code"]?.intOrBoolAsInt ?? -32000
                cont(.failure(HarnessError.rpc(code: code, message: message)))
            } else {
                cont(.success(object["result"] ?? .null))
            }
            return
        }
    }

    private func handleNotification(
        method: String,
        params: [String: JSONValue],
        rpcRequestId: JSONValue?
    ) {
        if method == "turn/completed" {
            let turn = params["turn"]?.objectValue ?? [:]
            let status = turn["status"]?.stringValue ?? "completed"
            let errorMessage: String?
            if status == "failed" {
                let info = turn["error"]?.objectValue
                errorMessage = info?["message"]?.stringValue
                    ?? "任务失败 (status=failed)"
            } else {
                errorMessage = nil
            }
            // Deliver the completion (with token usage) to the UI before
            // we tear down the run below. The `finish(_:)` call clears
            // `eventHandler`, so this must come first.
            let usage = TokenUsage.fromJSON(
                params["usage"] ?? params["total_token_usage"] ?? turn["usage"]
            )
            eventHandler?(.turnCompleted(status: status, errorMessage: errorMessage, usage: usage))

            if status == "failed" {
                finish(.failed(errorMessage ?? "任务失败 (status=failed)"))
            } else {
                finish(.finished)
            }
            return
        }
        if let event = ExecEventParser.parse(
            method: method,
            params: params,
            rpcRequestId: rpcRequestId
        ) {
            // v0.4.1: when an approval arrives, arm a 60s deadline and
            // reserve the server-supplied id so our allocator never
            // hands the same number to an outbound request.
            if case .approvalRequested(let req) = event, let rpcId = req.rpcRequestId {
                // Only numeric server ids share the allocator's integer space.
                // Claiming Int.max for a string id would overflow the next
                // outbound allocation.
                if let numericId = rpcId.intValue {
                    do {
                        try supervisor.reserveServerId(numericId)
                    } catch {
                        TapgoConfig.log("[harness] could not reserve server approval id: \(error.localizedDescription)")
                    }
                }
                armApprovalTimeout(for: req)
            }
            eventHandler?(event)
        } else if let rpcRequestId {
            // Fail closed: an unknown server request must not hang the active
            // turn indefinitely or be treated as implicitly approved.
            try? transport.send(frame: .object([
                "id": rpcRequestId,
                "error": .object([
                    "code": .int(-32601),
                    "message": .string("Tapgo AICoding 不支持服务端请求：\(method)"),
                ]),
            ]))
        }
    }

    private func serverStopped(code: Int32) {
        // Disarm every approval timer — the harness is gone, no point
        // auto-declining requests it can never answer.
        cancelAllApprovalTimeouts()
        let pendingError: HarnessError = cancelRequested
            ? .cancelled
            : .processExit(Int(code))
        let pendingContinuations = pending
        pending.removeAll()
        for (id, cont) in pendingContinuations {
            supervisor.releaseId(id)
            cont(.failure(pendingError))
        }
        if cancelRequested, case .running = state {
            eventHandler?(.turnCompleted(status: "interrupted", errorMessage: nil, usage: nil))
            finish(.finished)
        } else if case .running = state {
            finish(.failed("Harness 进程退出 (code \(code))"))
        } else {
            state = .idle
        }
    }

    private func finish(_ final: RunState) {
        state = final
        activeTurnId = nil
        cancelAllApprovalTimeouts()
        eventHandler = nil
        let cont = turnContinuation
        turnContinuation = nil
        cont?.resume(returning: final)
    }
}

enum HarnessError: LocalizedError {
    case invalidResponse(String)
    case rpc(code: Int, message: String)
    case processExit(Int)
    case timeout(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message): return message
        case .rpc(_, let message): return "Harness RPC 错误: \(message)"
        case .processExit(let code): return "Harness 进程意外退出 (\(code))"
        case .timeout(let method): return "Harness RPC 超时：\(method)"
        case .cancelled: return "任务已取消"
        }
    }

    var isMissingRollout: Bool {
        guard case .rpc(_, let message) = self else { return false }
        let normalized = message.lowercased()
        return normalized.contains("no rollout found")
            || (normalized.contains("thread") && normalized.contains("not found"))
    }

    var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }
}
