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

    private(set) var state: RunState = .idle
    private var nextRequestId = 1
    private var pending: [Int: (Result<JSONValue, Error>) -> Void] = [:]
    private var eventHandler: (@MainActor (ExecEvent) -> Void)?

    private(set) var activeThreadId: String?
    private var activeTurnId: String?
    private var turnContinuation: CheckedContinuation<RunState, Never>?

    init(transport: HarnessTransport) {
        self.transport = transport
        transport.onNotification = { [weak self] frame in
            self?.handleFrame(frame)
        }
        transport.onClose = { [weak self] code in
            self?.serverStopped(code: code)
        }
    }

    /// True when the underlying transport is alive and ready to
    /// accept JSON-RPC frames.
    var isAvailable: Bool {
        transport.isRunning
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
        onEvent: @escaping @MainActor (ExecEvent) -> Void
    ) async -> RunState {
        if case .running = state {
            return .failed("已有任务在执行")
        }
        do {
            try transport.start()

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
            try? transport.send(frame: .object([
                "method": .string("initialized"),
                "params": .object([:]),
            ]))
            // Small settle so the harness finishes processing the
            // `initialized` notification before thread/start (mirrors the
            // reference integration test).
            try? await Task.sleep(nanoseconds: 400_000_000)

            let threadId: String
            if let resumeThreadId {
                threadId = resumeThreadId
                _ = try await request(method: "thread/resume", params: [
                    "threadId": .string(threadId),
                ])
            } else {
                var startParams: [String: JSONValue] = [
                    "model": .string(TapgoConfig.modelName),
                    "modelProvider": .string(TapgoConfig.modelProvider),
                    "approvalPolicy": .string(TapgoConfig.approvalPolicy.rawValue),
                    "sandbox": .string(TapgoConfig.sandboxMode.rawValue),
                    "serviceName": .string(TapgoConfig.serviceName),
                ]
                if let cwd, !cwd.isEmpty {
                    startParams["cwd"] = .string(cwd)
                }
                if let effort = TapgoConfig.reasoningEffort {
                    startParams["effort"] = .string(effort)
                }
                if let baseInstructions, !baseInstructions.isEmpty {
                    startParams["baseInstructions"] = .string(baseInstructions)
                }
                let resp = try await request(method: "thread/start", params: startParams)
                guard let id = resp.objectValue?["thread"]?.objectValue?["id"]?.stringValue else {
                    throw HarnessError.invalidResponse("thread/start 未返回 thread.id")
                }
                threadId = id
            }
            activeThreadId = threadId
            activeThreadIdSnapshot = threadId
            eventHandler = onEvent
            state = .running(threadId: threadId)

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
            let resp = try await request(method: "turn/start", params: [
                "threadId": .string(threadId),
                "input": .array(input),
            ])
            activeTurnId = resp.objectValue?["turn"]?.objectValue?["id"]?.stringValue

            return await withCheckedContinuation { (cont: CheckedContinuation<RunState, Never>) in
                turnContinuation = cont
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .failed(message)
            return state
        }
    }

    /// Cancel the active turn. Sends `turn/interrupt` to the harness.
    func cancel() {
        guard let threadId = activeThreadId, let turnId = activeTurnId else { return }
        Task {
            _ = try? await request(method: "turn/interrupt", params: [
                "threadId": .string(threadId),
                "turnId": .string(turnId),
            ])
        }
    }

    /// Resolve a pending approval. Sends a fire-and-forget notification
    /// to the harness (no response is expected). `decision` mirrors the
    /// harness's `approve` / `decline` values.
    func respondToApproval(_ request: ApprovalRequest, approve: Bool) {
        let kind: String
        switch request.kind {
        case .commandExecution: kind = "commandExecution"
        case .fileChange:       kind = "fileChange"
        case .toolCall:         kind = "toolCall"
        }
        let method = "item/\(kind)/requestApproval/response"
        let frame = JSONValue.object([
            "method": .string(method),
            "params": .object([
                "id": .string(request.id),
                "request_id": .string(request.id),
                "decision": .string(approve ? "approve" : "decline"),
            ]),
        ])
        do {
            try transport.send(frame: frame)
        } catch {
            TapgoConfig.log("[harness] respondToApproval failed: \(error.localizedDescription)")
        }
    }

    /// Tear down the underlying transport. Call before quit.
    func shutdown() {
        transport.stop()
        state = .idle
    }

    // MARK: - JSON-RPC transport

    private func request(method: String, params: [String: JSONValue]) async throws -> JSONValue {
        let id = nextRequestId
        nextRequestId += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            do {
                try transport.send(frame: .object([
                    "id": .int(id),
                    "method": .string(method),
                    "params": .object(params),
                ]))
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    private func handleFrame(_ value: JSONValue) {
        guard let object = value.objectValue else { return }
        TapgoConfig.log("← \(value.toJSONString().prefix(800))")
        if let id = object["id"]?.intOrBoolAsInt, let cont = pending.removeValue(forKey: id) {
            if let error = object["error"]?.objectValue {
                let message = error["message"]?.stringValue ?? "未知错误"
                let code = error["code"]?.intOrBoolAsInt ?? -32000
                cont(.failure(HarnessError.rpc(code: code, message: message)))
            } else {
                cont(.success(object["result"] ?? .null))
            }
            return
        }
        guard let method = object["method"]?.stringValue,
              let params = object["params"]?.objectValue
        else { return }
        handleNotification(method: method, params: params)
    }

    private func handleNotification(method: String, params: [String: JSONValue]) {
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
        if let event = ExecEventParser.parse(method: method, params: params) {
            eventHandler?(event)
        }
    }

    private func serverStopped(code: Int32) {
        let pendingError = HarnessError.processExit(Int(code))
        let pendingContinuations = pending.values
        pending.removeAll()
        for cont in pendingContinuations {
            cont(.failure(pendingError))
        }
        if case .running = state {
            finish(.failed("Harness 进程退出 (code \(code))"))
        } else {
            state = .idle
        }
    }

    private func finish(_ final: RunState) {
        state = final
        activeTurnId = nil
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

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message): return message
        case .rpc(_, let message): return "Harness RPC 错误: \(message)"
        case .processExit(let code): return "Harness 进程意外退出 (\(code))"
        }
    }
}
