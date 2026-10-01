import Foundation

/// Keeps a foreground remote stream alive through proxies that close idle WebSockets.
@MainActor
final class MobileSocketHeartbeat {
    private var task: Task<Void, Never>?

    func start(socket: URLSessionWebSocketTask, onFailure: @escaping @MainActor () -> Void) {
        stop()
        task = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(20))
                    try Task.checkCancellation()
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        socket.sendPing { error in
                            if let error { continuation.resume(throwing: error) }
                            else { continuation.resume() }
                        }
                    }
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
