import Foundation

/// Monotonically-increasing JSON-RPC request id allocator that **never
/// reuses** an id, even after the original request has been responded
/// to, timed out, or cancelled.
///
/// ## Why this exists
/// v0.4.0 introduced fail-closed approval handling where the server
/// keeps a top-level `id` alive until we reply with `accept`/`decline`.
/// If a buggy / hostile server (or a confused client) ever re-uses a
/// stale id, our JSON-RPC correlation would silently route the new
/// response into a callback that no longer exists — and the pending
/// request would hang forever.
///
/// To prevent that, the allocator:
///
///   1. Allocates ids strictly greater than any id ever issued.
///   2. Records every id it has ever issued in `issuedIds`.
///   3. On `release(id:)`, marks the id as dead — future `allocate()`
///      calls must skip past it.
///   4. On `claim(id:)`, asserts the id has never been issued before;
///      used by code paths that receive a server-supplied id (e.g.
///      server-initiated approval requests) so the client can never
///      accidentally pick the same number for an outbound request.
///
/// Pure logic — no actor isolation, no I/O. The caller (`CodexHarnessClient`
/// / `HarnessSupervisor`) wraps it in `@MainActor`.
public struct HarnessIdAllocator {

    /// The highest id we have ever issued. The next `allocate()` returns
    /// `lastIssued + 1`.
    public private(set) var lastIssued: Int = 0

    /// Every id that has ever been allocated and not yet released.
    /// Useful for asserting "no live request" in tests.
    public private(set) var live: Set<Int> = []

    /// Every id that has ever been issued (across its entire lifetime),
    /// even after `release(id:)`. The allocator will **never** return
    /// one of these again.
    public private(set) var issued: Set<Int> = []

    public init() {}

    /// Allocate a fresh id. The returned id is strictly greater than
    /// every id previously returned by `allocate()` for this allocator
    /// instance. O(1).
    public mutating func allocate() -> Int {
        lastIssued += 1
        live.insert(lastIssued)
        issued.insert(lastIssued)
        return lastIssued
    }

    /// Release an id. Safe to call multiple times. After release the id
    /// is still recorded in `issued` (so we never reuse it) but is no
    /// longer in `live`.
    public mutating func release(_ id: Int) {
        live.remove(id)
    }

    /// Reserve a server-supplied id so the allocator can guarantee no
    /// outbound request collides with it. Throws if the id has already
    /// been issued by us (i.e. another outbound request is using it).
    public mutating func claim(_ id: Int) throws {
        guard !issued.contains(id) else {
            throw HarnessIdError.collision(id)
        }
        // Server ids can be anything; bump `lastIssued` so the next
        // `allocate()` cannot pick a number at or below this id.
        if id > lastIssued { lastIssued = id }
        issued.insert(id)
        // NOTE: server ids are NOT tracked in `live` — they belong to
        // the harness, not to our outbound request map.
    }

    /// True when no outbound ids are currently in flight.
    public var isEmpty: Bool { live.isEmpty }

    /// Reset the allocator. Used by tests and by the supervisor after a
    /// process restart so dead-server ids from the previous instance do
    /// not bleed into the new one.
    public mutating func reset() {
        lastIssued = 0
        live.removeAll()
        issued.removeAll()
    }
}

public enum HarnessIdError: LocalizedError, Equatable {
    case collision(Int)

    public var errorDescription: String? {
        switch self {
        case .collision(let id):
            return "JSON-RPC id \(id) 已被本端发出过；不能再次分配"
        }
    }
}
