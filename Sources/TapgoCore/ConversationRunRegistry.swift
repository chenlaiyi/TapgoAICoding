/// Tracks active conversation runs without coupling their lifecycle to the
/// currently selected conversation.
///
/// Stop requests suppress automatic queue draining for only the requested
/// conversation. A later successful start begins a fresh lifecycle and clears
/// any stale suppression for that conversation.
public struct ConversationRunRegistry {
    public private(set) var runningThreadIds: Set<String>

    private var autoDrainSuppressedThreadIds: Set<String>

    public init() {
        runningThreadIds = []
        autoDrainSuppressedThreadIds = []
    }

    public var count: Int {
        runningThreadIds.count
    }

    public func isRunning(_ threadId: String) -> Bool {
        runningThreadIds.contains(threadId)
    }

    /// Starts a fresh run for `threadId`.
    ///
    /// Returns `false` when that conversation already has a run in progress.
    /// A successful start clears suppression left by an earlier lifecycle.
    @discardableResult
    public mutating func markStarted(_ threadId: String) -> Bool {
        let inserted = runningThreadIds.insert(threadId).inserted
        guard inserted else { return false }

        autoDrainSuppressedThreadIds.remove(threadId)
        return true
    }

    /// Records an explicit stop for one running conversation.
    ///
    /// The run remains registered until `markFinished(_:)` confirms its
    /// completion. Unknown or already-finished conversations are unchanged.
    @discardableResult
    public mutating func requestStop(_ threadId: String) -> Bool {
        guard runningThreadIds.contains(threadId) else { return false }

        autoDrainSuppressedThreadIds.insert(threadId)
        return true
    }

    /// Re-enables automatic queue draining for `threadId`.
    public mutating func allowAutoDrain(_ threadId: String) {
        autoDrainSuppressedThreadIds.remove(threadId)
    }

    /// Finishes the active run for `threadId`.
    ///
    /// Returns `nil` when the conversation was not running. Otherwise returns
    /// whether its queue should be drained automatically. Finishing one
    /// conversation never changes another conversation's lifecycle.
    public mutating func markFinished(_ threadId: String) -> Bool? {
        guard runningThreadIds.remove(threadId) != nil else { return nil }

        let shouldAutoDrain = !autoDrainSuppressedThreadIds.contains(threadId)
        autoDrainSuppressedThreadIds.remove(threadId)
        return shouldAutoDrain
    }
}
