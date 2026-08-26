import Foundation

/// A single user→assistant exchange. On-disk shape persists
/// `id`, `userInput`, `status`, `startedAt`, `completedAt`, **and**
/// the `items` (assistant messages, command executions, file changes)
/// so a thread's conversation survives an app relaunch.
public struct Turn: Identifiable, Hashable, Codable {
    public let id: String
    public var userInput: String
    public var status: Status
    public var startedAt: Date
    public var completedAt: Date?
    /// Persisted with the thread so the chat history survives a
    /// relaunch.
    public var items: [TurnItem] = []
    /// Token usage reported by the harness for this turn (nil until the
    /// turn completes and the harness reports usage).
    public var usage: TokenUsage?

    public enum Status: String, Hashable, Codable {
        case pending
        case running
        case awaitingApproval
        case completed
        case failed
        case interrupted
    }

    enum CodingKeys: String, CodingKey {
        case id, userInput, status, startedAt, completedAt, items, usage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        userInput = try c.decode(String.self, forKey: .userInput)
        status = try c.decode(Status.self, forKey: .status)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        // Older thread files persisted turns without `items` — default
        // to empty so we don't fail to decode an existing thread.
        items = try c.decodeIfPresent([TurnItem].self, forKey: .items) ?? []
        usage = try c.decodeIfPresent(TokenUsage.self, forKey: .usage)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userInput, forKey: .userInput)
        try c.encode(status, forKey: .status)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encode(items, forKey: .items)
        try c.encodeIfPresent(usage, forKey: .usage)
    }

    public init(
        id: String,
        userInput: String,
        items: [TurnItem] = [],
        status: Status,
        startedAt: Date,
        completedAt: Date? = nil,
        usage: TokenUsage? = nil
    ) {
        self.id = id
        self.userInput = userInput
        self.items = items
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.usage = usage
    }

    /// Wall-clock duration of the turn, if it completed.
    public var duration: TimeInterval? {
        guard let completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }

    /// Short human-readable duration (e.g. "12s", "1m 03s"), or nil
    /// while the turn is still running.
    public var durationText: String? {
        guard let d = duration, d >= 0 else { return nil }
        return DurationFormatter.string(seconds: d)
    }
}

public extension Turn {
    /// Case-insensitive substring match across the user's input and every
    /// item's `searchableText`. The trimmed-empty query never matches (so
    /// search UI can safely call this with the live TextField value).
    func matches(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return false }
        if userInput.lowercased().contains(q) { return true }
        return items.contains { $0.searchableText.lowercased().contains(q) }
    }
}
