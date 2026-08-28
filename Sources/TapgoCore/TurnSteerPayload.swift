import Foundation

/// Builds the protocol payload for Codex app-server `turn/steer`.
///
/// Steering adds input to the currently active turn. It is intentionally
/// separate from `turn/interrupt`: callers can adjust direction without
/// cancelling the work that is already in progress.
public enum TurnSteerPayload {
    public enum PayloadError: LocalizedError {
        case missingThreadId
        case missingTurnId
        case emptyInput

        public var errorDescription: String? {
            switch self {
            case .missingThreadId: return "缺少当前会话 ID"
            case .missingTurnId: return "当前任务尚未准备好接收调整"
            case .emptyInput: return "没有可发送的调整内容"
            }
        }
    }

    public static func make(
        threadId: String,
        expectedTurnId: String,
        text: String,
        imagePaths: [String] = []
    ) throws -> [String: JSONValue] {
        let threadId = threadId.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedTurnId = expectedTurnId.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !threadId.isEmpty else { throw PayloadError.missingThreadId }
        guard !expectedTurnId.isEmpty else { throw PayloadError.missingTurnId }

        var input: [JSONValue] = []
        if !text.isEmpty {
            input.append(.object([
                "type": .string("text"),
                "text": .string(text),
            ]))
        }
        for path in imagePaths where !path.isEmpty {
            input.append(.object([
                "type": .string("localImage"),
                "path": .string(path),
            ]))
        }
        guard !input.isEmpty else { throw PayloadError.emptyInput }

        return [
            "threadId": .string(threadId),
            "expectedTurnId": .string(expectedTurnId),
            "input": .array(input),
        ]
    }
}
