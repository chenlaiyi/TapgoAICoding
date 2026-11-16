import Foundation

/// A ping that was written but never answered, so the socket is treated as gone.
enum MobileSocketHeartbeatFailure: Error {
    case pongTimedOut
}

/// Resumes one ping exactly once, from the pong callback or from the deadline.
private final class PongWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: Result<Void, Error>?
    private var waiter: CheckedContinuation<Void, Error>?

    /// Waits for the pong that answers the ping, failing when it does not arrive in time.
    /// - Parameter timeout: Deadline for the pong after the ping was written.
    func wait(timeout: Duration) async throws {
        let deadline = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.resolve(MobileSocketHeartbeatFailure.pongTimedOut)
        }
        defer { deadline.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            if let outcome {
                lock.unlock()
                continuation.resume(with: outcome)
                return
            }
            waiter = continuation
            lock.unlock()
        }
    }

    /// Records the pong result; later calls are ignored.
    /// - Parameter error: The ping error reported by the socket, or `nil` after a pong.
    func resolve(_ error: Error?) {
        let result: Result<Void, Error> = error.map { .failure($0) } ?? .success(())
        lock.lock()
        guard outcome == nil else {
            lock.unlock()
            return
        }
        outcome = result
        let waiter = waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume(with: result)
    }
}

/// Keeps a foreground remote stream alive and detects a socket that accepts pings without answering them.
@MainActor
final class MobileSocketHeartbeat {
    private let interval: Duration
    private let pongTimeout: Duration
    private var task: Task<Void, Never>?

    /// Creates the heartbeat used by foreground conversations and confirmation streams.
    /// - Parameters:
    ///   - interval: Delay between pings.
    ///   - pongTimeout: How long one ping may stay unanswered before the connection counts as dead.
    init(interval: Duration = .seconds(20), pongTimeout: Duration = .seconds(15)) {
        self.interval = interval
        self.pongTimeout = pongTimeout
    }

    func start(socket: URLSessionWebSocketTask, onFailure: @escaping @MainActor () -> Void) {
        stop()
        task = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                    try Task.checkCancellation()
                    let waiter = PongWaiter()
                    socket.sendPing { waiter.resolve($0) }
                    try await waiter.wait(timeout: pongTimeout)
                } catch {
                    if !Task.isCancelled { onFailure() }
                    return
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
