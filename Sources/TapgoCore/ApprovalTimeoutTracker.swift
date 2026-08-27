import Foundation

/// Deadline tracker for pending approval requests.
///
/// ## Why a separate tracker
/// v0.4.0 introduced 30-second RPC **request** timeouts (client → server
/// direction). Approvals are the opposite direction: server-initiated
/// JSON-RPC requests that block the harness until we respond. Without
/// a deadline, a missed approval (closed UI, dropped callback, user
/// walked away) leaves the harness wedged indefinitely.
///
/// The tracker is intentionally pure-logic and `@Sendable`: no actor
/// isolation, no transport. The owner (`CodexHarnessClient`) owns one
/// tracker instance and feeds it `arm` / `disarm` calls keyed by the
/// approval's `rpcRequestId`.
///
/// The default deadline is 60 seconds — long enough for the user to
/// read a diff or a command, short enough that an unattended Mac
/// doesn't wedge the harness forever. The 30s client→server RPC
/// timeout is unrelated and stays where it is.
public struct ApprovalTimeoutTracker {

    /// Default deadline for a new arm() when none is supplied. Tuned to
    /// be longer than the RPC timeout (30s) so an approval arriving
    /// late in a slow turn isn't immediately declined.
    public static let defaultDeadline: TimeInterval = 60

    /// An armed timer, keyed by the approval's `rpcRequestId`.
    /// We keep the deadline as an absolute `Date` so timers survive
    /// across `await` suspensions without needing a Task.
    public struct Arm: Equatable {
        public let rpcRequestId: String
        public let deadline: Date
    }

    public private(set) var arms: [String: Arm] = [:]

    /// Set by the owner. Invoked once per expired `rpcRequestId`.
    /// The owner should reply `decline` to the harness via
    /// `ApprovalRequest.rpcResponseFrame(approve: false)`.
    public var onExpire: ((String) -> Void)?

    public init() {}

    /// Arm a deadline for the given approval id. If the same id is
    /// already armed, the deadline is reset (a re-prompted approval
    /// starts its clock over).
    @discardableResult
    public mutating func arm(rpcRequestId: String, now: Date = Date(), deadline: TimeInterval = defaultDeadline) -> Arm {
        let arm = Arm(rpcRequestId: rpcRequestId, deadline: now.addingTimeInterval(deadline))
        arms[rpcRequestId] = arm
        return arm
    }

    /// Disarm an existing timer. Safe to call on an unknown id (no-op).
    public mutating func disarm(rpcRequestId: String) {
        arms.removeValue(forKey: rpcRequestId)
    }

    /// Disarm every timer. Used by `stop()` and on harness process exit.
    public mutating func disarmAll() {
        arms.removeAll()
    }

    /// Find all ids whose `deadline` is in the past and fire the
    /// `onExpire` callback for each. Returns the expired ids so the
    /// caller can log / audit them.
    @discardableResult
    public mutating func sweep(now: Date = Date()) -> [String] {
        let expired = arms.values.filter { $0.deadline <= now }.map(\.rpcRequestId)
        for id in expired {
            arms.removeValue(forKey: id)
            onExpire?(id)
        }
        return expired
    }

    /// True if no approvals are currently armed.
    public var isEmpty: Bool { arms.isEmpty }
}
