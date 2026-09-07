import Foundation

/// Both the send button and keyboard submission must intercept local commands.
public enum ComposerLocalCommand: Equatable {
    case goal(String)
    case newTask
    /// `/clear` — wipe the active thread's `turns` in place so the next
    /// message starts from a clean local + harness context. Thread
    /// metadata (id, title, projectId, cwd, goal, pinned) survives;
    /// only the conversation history and the harness thread handle are
    /// reset.
    case clear

    public static func parse(_ input: String) -> Self? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "/new" { return .newTask }
        if text == "/clear" { return .clear }
        guard text.hasPrefix("/goal") else { return nil }
        let rest = text.dropFirst(5)
        guard rest.isEmpty || rest.first?.isWhitespace == true else { return nil }
        return .goal(rest.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
