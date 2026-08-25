import Foundation

/// A single conversation thread. Persisted across launches.
///
/// The on-disk shape persists the metadata fields
/// (`id`, `title`, `createdAt`, `updatedAt`, `projectId`, `cwd`,
/// `harnessThreadId`) **and** the `turns` array (with their items),
/// so a thread and its conversation survive an app relaunch. The
/// `harnessThreadId` is what lets us `thread/resume` the harness-side
/// session on the next turn.
public struct Thread: Identifiable, Hashable, Codable {
    public let id: String
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    /// `Project.id`. Threads are always scoped to exactly one
    /// project. Legacy threads (created before the workspace
    /// migration) have `nil` here and render in the "未分类" group.
    public var projectId: String?
    /// Effective cwd passed to codex `thread/start` /
    /// `thread/resume` / `turn/start`. Mirrors the project's
    /// `worktreeRoot` at the time the thread was last used, so a
    /// thread keeps working even if the project is later removed.
    public var cwd: String?
    /// codex-side thread id from `thread/started` — used for
    /// `thread/resume` on subsequent turns.
    public var harnessThreadId: String?
    /// Turns are persisted with the thread so the conversation survives
    /// a relaunch. Each `Turn` carries its own items (assistant text,
    /// tool calls, command output, file changes).
    public var turns: [Turn] = []
    /// User-pinned threads sort to the top of their project group.
    public var isPinned: Bool = false
    /// Optional session goal set via the `/goal` command, shown as a banner
    /// at the top of the conversation.
    public var goal: String?

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, updatedAt
        case projectId, cwd, harnessThreadId, turns, isPinned, goal
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        harnessThreadId = try c.decodeIfPresent(String.self, forKey: .harnessThreadId)
        // v1 files written before turn persistence have no `turns`
        // key — default it to empty instead of failing to decode.
        turns = try c.decodeIfPresent([Turn].self, forKey: .turns) ?? []
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        goal = try c.decodeIfPresent(String.self, forKey: .goal)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(projectId, forKey: .projectId)
        try c.encodeIfPresent(cwd, forKey: .cwd)
        try c.encodeIfPresent(harnessThreadId, forKey: .harnessThreadId)
        try c.encode(turns, forKey: .turns)
        try c.encode(isPinned, forKey: .isPinned)
        try c.encodeIfPresent(goal, forKey: .goal)
    }

    public init(
        id: String,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        projectId: String? = nil,
        cwd: String? = nil,
        harnessThreadId: String? = nil,
        turns: [Turn] = [],
        isPinned: Bool = false,
        goal: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.projectId = projectId
        self.cwd = cwd
        self.harnessThreadId = harnessThreadId
        self.turns = turns
        self.isPinned = isPinned
        self.goal = goal
    }

    public static func newLocal(
        projectId: String? = nil,
        cwd: String? = nil
    ) -> Thread {
        Thread(
            id: "local-" + UUID().uuidString,
            title: "新会话",
            createdAt: Date(),
            updatedAt: Date(),
            projectId: projectId,
            cwd: cwd,
            harnessThreadId: nil,
            turns: []
        )
    }

    /// Sum of token usage across all turns that reported usage.
    public var usageTotal: Int {
        turns.compactMap { $0.usage?.total }.reduce(0, +)
    }

    /// Sum of completed-turn wall-clock durations.
    public var durationTotal: TimeInterval {
        turns.compactMap { $0.duration }.reduce(0, +)
    }

    /// Human-readable total duration (e.g. "1m 05s"), or nil if no turn
    /// has completed.
    public var durationTotalText: String? {
        guard durationTotal > 0 else { return nil }
        return DurationFormatter.string(seconds: durationTotal)
    }

    /// The most recent conversational text for the sidebar preview,
    /// walking turns from newest to oldest. Prefers the latest assistant
    /// reply; falls back to the user's most recent input, prefixed with
    /// "You: " so it's clear who spoke — mirroring Codex's thread list.
    public var latestPreview: String {
        for turn in turns.reversed() {
            for item in turn.items.reversed() {
                switch item {
                case .assistantMessage(_, let text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return text
                    }
                case .userMessage(_, let text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return "You: " + text
                    }
                default:
                    break
                }
            }
            if !turn.userInput.isEmpty {
                return "You: " + turn.userInput
            }
        }
        return ""
    }

    /// Whether a "date banner" should appear before the turn at `index`:
    /// true for the first turn, and whenever its day differs from the
    /// previous turn. Mirrors Codex's day dividers in the conversation.
    public static func showDateBanner(at index: Int, in turns: [Turn]) -> Bool {
        guard index >= 0, index < turns.count else { return false }
        if index == 0 { return true }
        let prev = turns[index - 1]
        return !Calendar.current.isDate(turns[index].startedAt, inSameDayAs: prev.startedAt)
    }

    /// True if this thread still has its default placeholder title
    /// (e.g. "新会话" / "新建会话") and therefore should be auto-titled
    /// from the first user message. We match the prefix used by
    /// `L10n.newThread` rather than hard-coding the string so that
    /// the check survives localization changes.
    public var hasDefaultTitle: Bool {
        title.hasPrefix("新") || title == "新会话" || title == "新建会话" || title.isEmpty
    }

    /// Auto-title derived from the first user message. Truncated to
    /// ~40 chars at a word boundary and stripped of newlines so the
    /// sidebar row stays single-line. The returned string is what we
    /// persist into `title`; the caller should only invoke it for
    /// the very first turn of a fresh thread.
    public static func autoTitle(from firstMessage: String, maxLength: Int = 40) -> String {
        let flattened = firstMessage
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flattened.isEmpty else { return "新会话" }
        if flattened.count <= maxLength { return flattened }
        // Word-boundary cut: back up to the last whitespace inside
        // the budget so we don't slice a word in half.
        let prefix = flattened.prefix(maxLength)
        if let lastSpace = prefix.lastIndex(of: " "),
           flattened.distance(from: prefix.startIndex, to: lastSpace) >= maxLength / 2 {
            return String(flattened[flattened.startIndex..<lastSpace]) + "…"
        }
        return String(prefix) + "…"
    }
}
