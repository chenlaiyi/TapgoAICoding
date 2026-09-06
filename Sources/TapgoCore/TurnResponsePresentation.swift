import Foundation

/// One decision shared by desktop, copy and phone. Nothing is removed from history.
public struct TurnResponsePresentation {
    public let messages: [TurnItem]
    public let work: [TurnItem]
    public let notices: [TurnItem]
    public let users: [TurnItem]

    public init(_ turn: Turn) {
        let items = turn.items.filter {
            !$0.isAppGeneratedProgress && !$0.isPlanSnapshot && !$0.isTurnDiffSnapshot && !$0.isWorktreeStatsSnapshot
        }
        let assistants = items.filter {
            if case .assistantMessage(_, let text) = $0 { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return false
        }
        let explicitFinals = assistants.filter { turn.assistantPhases[$0.id] == "final_answer" }
        // Legacy providers omit phase. Only the terminal response AFTER work is
        // promoted; an interrupted pre-tool commentary is never called a result.
        let legacyFinal: TurnItem? = {
            guard turn.status == .completed, explicitFinals.isEmpty,
                  let candidate = assistants.last,
                  turn.assistantPhases[candidate.id] != "commentary",
                  let index = items.lastIndex(where: { $0.id == candidate.id }) else { return nil }
            let laterWork = items.suffix(from: index + 1).contains {
                switch $0 { case .toolCall, .commandExecution, .reasoning, .reasoningSummary: return true; default: return false }
            }
            return laterWork ? nil : candidate
        }()
        messages = explicitFinals.isEmpty ? legacyFinal.map { [$0] } ?? [] : explicitFinals
        let finalIDs = Set(messages.map(\.id))
        users = items.filter { if case .userMessage = $0 { return true }; return false }
        notices = items.filter {
            switch $0 { case .approval, .error: return true; default: return false }
        }
        work = items.filter {
            switch $0 {
            case .userMessage, .approval, .error, .fileChange: return false
            case .assistantMessage: return !finalIDs.contains($0.id)
            default: return true
            }
        }
    }
    public var answerText: String {
        messages.compactMap { if case .assistantMessage(_, let text) = $0 { return text }; return nil }.joined(separator: "\n\n")
    }
}
