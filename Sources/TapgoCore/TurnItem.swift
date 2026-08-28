import Foundation

/// A single observable item inside a Turn. Mirrors the items Codex streams
/// back over JSON-RPC notifications (assistant message deltas, reasoning
/// deltas, tool calls, etc.).
public enum TurnItem: Identifiable, Hashable, Codable {
    case userMessage(id: String, text: String)
    case assistantMessage(id: String, text: String)
    case reasoning(id: String, text: String)
    case reasoningSummary(id: String, text: String)
    case toolCall(ToolCall)
    case commandExecution(CommandExecution)
    case fileChange(FileChange)
    case approval(ApprovalRequest)
    case error(id: String, message: String)

    /// Tagged encoding so a `TurnItem` can be round-tripped to disk
    /// and restored verbatim after an app relaunch. The tag string
    /// mirrors the case name; the payload lives in `value` (for the
    /// struct-carrying cases) or inline in `id`/`text`/`message`.
    private enum CodingKeys: String, CodingKey {
        case type, id, text, message, value
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "userMessage":
            self = .userMessage(
                id: try c.decode(String.self, forKey: .id),
                text: try c.decode(String.self, forKey: .text))
        case "assistantMessage":
            self = .assistantMessage(
                id: try c.decode(String.self, forKey: .id),
                text: try c.decode(String.self, forKey: .text))
        case "reasoning":
            self = .reasoning(
                id: try c.decode(String.self, forKey: .id),
                text: try c.decode(String.self, forKey: .text))
        case "reasoningSummary":
            self = .reasoningSummary(
                id: try c.decode(String.self, forKey: .id),
                text: try c.decode(String.self, forKey: .text))
        case "toolCall":
            self = .toolCall(try c.decode(ToolCall.self, forKey: .value))
        case "commandExecution":
            self = .commandExecution(try c.decode(CommandExecution.self, forKey: .value))
        case "fileChange":
            self = .fileChange(try c.decode(FileChange.self, forKey: .value))
        case "approval":
            self = .approval(try c.decode(ApprovalRequest.self, forKey: .value))
        case "error":
            self = .error(
                id: try c.decode(String.self, forKey: .id),
                message: try c.decode(String.self, forKey: .message))
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown TurnItem type \(type)"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .userMessage(let id, let text):
            try c.encode("userMessage", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(text, forKey: .text)
        case .assistantMessage(let id, let text):
            try c.encode("assistantMessage", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(text, forKey: .text)
        case .reasoning(let id, let text):
            try c.encode("reasoning", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(text, forKey: .text)
        case .reasoningSummary(let id, let text):
            try c.encode("reasoningSummary", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(text, forKey: .text)
        case .toolCall(let tc):
            try c.encode("toolCall", forKey: .type)
            try c.encode(tc, forKey: .value)
        case .commandExecution(let ce):
            try c.encode("commandExecution", forKey: .type)
            try c.encode(ce, forKey: .value)
        case .fileChange(let fc):
            try c.encode("fileChange", forKey: .type)
            try c.encode(fc, forKey: .value)
        case .approval(let ar):
            try c.encode("approval", forKey: .type)
            try c.encode(ar, forKey: .value)
        case .error(let id, let message):
            try c.encode("error", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(message, forKey: .message)
        }
    }

    public var id: String {
        switch self {
        case .userMessage(let id, _),
             .assistantMessage(let id, _),
             .reasoning(let id, _),
             .reasoningSummary(let id, _),
             .error(let id, _):
            return id
        case .toolCall(let tc): return tc.id
        case .commandExecution(let ce): return ce.id
        case .fileChange(let fc): return fc.id
        case .approval(let ar): return ar.id
        }
    }

    public var sortKey: String { id }
}

public extension TurnItem {
    /// v0.5.4 briefly persisted fixed assistant messages around commands,
    /// tools, file changes and errors. Their native rows already contain the
    /// same state, so keeping these messages in chat/search/export adds noise.
    var isAppGeneratedProgress: Bool {
        guard case .assistantMessage(let id, _) = self else { return false }
        return id.hasPrefix("app-progress-")
    }

    /// Flattened text used by the in-conversation search. Includes
    /// everything a user might reasonably want to match against when
    /// looking back through a thread: messages, reasoning, command
    /// input + output, tool call name + args + result, file path +
    /// diff, and approval reason. Empty for unknown shapes.
    var searchableText: String {
        switch self {
        case .userMessage(_, let t): return t
        case .assistantMessage(_, let t): return isAppGeneratedProgress ? "" : t
        case .reasoning(_, let t): return t
        case .reasoningSummary(_, let t): return t
        case .error(_, let message): return message
        case .toolCall(let tc):
            var s = tc.name + " " + tc.arguments
            if let r = tc.result, !r.isEmpty { s += " " + r }
            return s
        case .commandExecution(let ce):
            var s = ce.command
            if !ce.stdout.isEmpty { s += "\n" + ce.stdout }
            if !ce.stderr.isEmpty { s += "\n" + ce.stderr }
            return s
        case .fileChange(let fc):
            return fc.path + "\n" + fc.diff
        case .approval(let ar):
            var s = ar.reason
            switch ar.payload {
            case .command(let ce): s += " " + ce.command
            case .fileChange(let fc): s += " " + fc.path
            case .toolCall(let tc): s += " " + tc.name + " " + tc.arguments
            }
            return s
        }
    }
}
