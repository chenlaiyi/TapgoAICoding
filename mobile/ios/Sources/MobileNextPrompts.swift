import Foundation

/// Latest completed turn's recommendations; selecting one only edits the local draft.
struct MobileNextPrompts: Equatable {
    private(set) var turn: Int?
    private(set) var prompts: [String] = []
    private(set) var failed = false

    mutating func consume(_ event: [String: Any]) {
        guard let type = event["type"] as? String, let data = event["data"] as? [String: Any] else { return }
        if type == "turn/start", let current = data["turn"] as? Int {
            turn = current
            prompts = []
            failed = false
        } else if type == "session/next-prompts-result", let current = data["turn"] as? Int, current == turn {
            restore(data, running: false)
        }
    }

    mutating func restore(_ value: [String: Any]?, running: Bool) {
        guard !running, let value, let current = value["turn"] as? Int, current >= 0,
              let status = value["status"] as? String, ["idle", "ready", "error"].contains(status),
              let raw = value["prompts"] as? [String], raw.count <= 3 else { return }
        let normalized = raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard normalized.allSatisfy({ !$0.isEmpty }) else { return }
        turn = current
        prompts = status == "ready" ? normalized.reduce(into: []) { result, prompt in
            if !result.contains(prompt) { result.append(prompt) }
        } : []
        failed = status == "error"
    }

    /// First suggestion phrased as an actionable step rather than a question.
    var bestExecutionPrompt: String? {
        bestExecutionPrompt(excluding: nil)
    }

    /// First actionable suggestion that does not echo the last user message.
    /// - Parameter lastUserText: the user's latest sent message.
    /// - Returns: the first acceptable prompt, or nil when every option echoes it.
    func bestExecutionPrompt(excluding lastUserText: String?) -> String? {
        prompts.first { !Self.isQuestion($0) && !Self.isEcho($0, of: lastUserText) }
    }

    /// Whether a suggestion repeats the user's latest message after normalization.
    /// - Parameters:
    ///   - prompt: generated suggestion.
    ///   - lastUserText: the user's latest sent message.
    /// - Returns: true for identical, contained, or high-prefix-overlap text.
    static func isEcho(_ prompt: String, of lastUserText: String?) -> Bool {
        guard let lastUserText else { return false }
        let suggestion = normalized(prompt)
        let previous = normalized(lastUserText)
        guard !suggestion.isEmpty, !previous.isEmpty else { return false }
        if suggestion == previous { return true }
        let shorter = min(suggestion.count, previous.count)
        let longer = max(suggestion.count, previous.count)
        if (suggestion.contains(previous) || previous.contains(suggestion)),
           Double(shorter) / Double(longer) >= 0.6 { return true }
        let sharedPrefix = zip(suggestion, previous).prefix { $0 == $1 }.count
        return Double(sharedPrefix) / Double(shorter) >= 0.8
    }

    private static func normalized(_ text: String) -> String {
        let ignored = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return String(String.UnicodeScalarView(text.lowercased().unicodeScalars.filter { !ignored.contains($0) }))
    }

    /// Whether a suggestion asks the reader something instead of naming an action.
    /// - Parameter prompt: generated suggestion.
    /// - Returns: true for question-shaped prompts.
    static func isQuestion(_ prompt: String) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("?") || trimmed.hasSuffix("？") { return true }
        let starts = ["是否", "如何", "要不要", "为什么", "怎么", "什么", "哪", "能否", "可不可以", "需要我", "要不要我"]
        return starts.contains { trimmed.hasPrefix($0) }
    }

    static func appending(_ prompt: String, to draft: String) -> String {
        draft.isEmpty ? prompt : draft + "\n\n" + prompt
    }
}

/// Prefills each completed turn once; user edits and deliberately cleared drafts survive replay.
struct MobileRecommendationDraft {
    private var handledTurns: Set<Int> = []
    private var selected: String?

    mutating func receiving(_ recommendations: MobileNextPrompts, draft: String,
                            lastUserText: String? = nil) -> String {
        guard let turn = recommendations.turn,
              let first = recommendations.bestExecutionPrompt(excluding: lastUserText),
              handledTurns.insert(turn).inserted else { return draft }
        guard draft.isEmpty else { selected = nil; return draft }
        selected = first
        return first
    }

    mutating func selecting(_ prompt: String, draft: String) -> String {
        let result = draft == selected ? prompt : MobileNextPrompts.appending(prompt, to: draft)
        selected = result == prompt ? prompt : nil
        return result
    }
}
