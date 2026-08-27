import Foundation
import TapgoCore

/// In-memory `HarnessTransport` used by unit tests. No real process is
/// spawned, no SSH, no file I/O. Tests can:
///
///   - inspect every JSON-RPC frame the client sent (`sentFrames`)
///   - script responses to push back via `respond(...)` or
///     `sendNotification(...)` / `sendServerRequest(...)`
///   - simulate unexpected process exit via `simulateExit(code:)`
///   - simulate startup failure via `simulateStartFailure(_:)`
///
/// **Why not spawn a real `codex app-server`?**
/// The integration test that does that requires a network-accessible
/// SSH host (203.0.113.10 in `RemoteSSHHarnessTransportIntegrationTests`).
/// For the protocol-level supervisor tests we want millisecond-class
/// feedback, no external dependencies, and a deterministic harness —
/// this fixture gives us all three.
@MainActor
public final class FakeHarnessTransport: HarnessTransport {

    public var onNotification: ((JSONValue) -> Void)?
    public var onClose: ((Int32) -> Void)?

    /// Every JSON-RPC frame the client wrote via `send(frame:)`.
    /// Append-only; tests assert against `sentFrames.last`.
    public private(set) var sentFrames: [JSONValue] = []

    /// True between `start()` and `simulateExit(...)` / `stop()`.
    public private(set) var _isRunning = false
    public var isRunning: Bool { _isRunning }

    /// How many times `start()` was called successfully. Used by the
    /// supervisor tests to assert restart counts.
    public private(set) var startCount = 0

    /// Set to an Error to make the next `start()` throw. Cleared
    /// after one use so tests can stage different failures.
    public var pendingStartError: Error?

    public init() {}

    public func start() throws {
        if let err = pendingStartError {
            pendingStartError = nil
            throw err
        }
        _isRunning = true
        startCount += 1
    }

    public func stop() {
        // `stop()` is supposed to be silent — it should NOT fire
        // onClose unless the process actually exits. In production
        // `LocalHarnessTransport.stop()` terminates the process and
        // the termination handler then fires `onClose(0)`. We mirror
        // that: stop() alone does nothing observable here.
    }

    public func send(frame: JSONValue) throws {
        guard _isRunning else { throw HarnessTransportError.notRunning }
        sentFrames.append(frame)
    }

    // MARK: - Test driver helpers

    /// Fire `onNotification` as if the harness emitted a JSON-RPC
    /// notification frame.
    public func sendNotification(method: String, params: JSONValue = .object([:])) {
        let frame: JSONValue = .object([
            "method": .string(method),
            "params": params,
        ])
        onNotification?(frame)
    }

    /// Fire `onNotification` as if the harness emitted a server-initiated
    /// JSON-RPC request (e.g. `item/commandExecution/requestApproval`).
    /// The `id` is what the client must echo back in its reply.
    public func sendServerRequest(id: Int, method: String, params: JSONValue = .object([:])) {
        let frame: JSONValue = .object([
            "id": .int(id),
            "method": .string(method),
            "params": params,
        ])
        onNotification?(frame)
    }

    /// Send a JSON-RPC response (success). Looks up the pending request
    /// by id and delivers the result.
    public func respond(id: Int, result: JSONValue = .object([:])) {
        let frame: JSONValue = .object([
            "id": .int(id),
            "result": result,
        ])
        onNotification?(frame)
    }

    /// Send a JSON-RPC response (error).
    public func respondError(id: Int, code: Int = -32000, message: String = "boom") {
        let frame: JSONValue = .object([
            "id": .int(id),
            "error": .object([
                "code": .int(code),
                "message": .string(message),
            ]),
        ])
        onNotification?(frame)
    }

    /// Simulate the underlying process exiting with the given code.
    /// Mirrors the real transport's `handleClose` exactly.
    public func simulateExit(code: Int32) {
        guard _isRunning else { return }
        _isRunning = false
        onClose?(code)
    }
}
