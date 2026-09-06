import Foundation

/// Both the send button and keyboard submission must intercept local commands.
public enum ComposerLocalCommand: Equatable {
    case goal(String)
    case newTask

    public static func parse(_ input: String) -> Self? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "/new" { return .newTask }
        guard text.hasPrefix("/goal") else { return nil }
        let rest = text.dropFirst(5)
        guard rest.isEmpty || rest.first?.isWhitespace == true else { return nil }
        return .goal(rest.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
