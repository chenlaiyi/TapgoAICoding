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
    /// `/model <query>` — switch the active provider/model. The query
    /// matches `displayName`, `apiModel`, `modelID`, or `providerName`
    /// case-insensitively. Ambiguous matches are reported back so the
    /// composer can show a hint; only an exact match switches.
    case model(String)
    /// `/init` — open a fresh thread in the active project preloaded
    /// with a "draft an AGENTS.md" prompt so the user can iterate with
    /// Codex and then write the result to the project root.
    case initProject
    /// `/compact` — fold older turns in the active thread into a short
    /// summary so the harness-side context window regains room while
    /// keeping the user's anchor message intact. Implementation lives
    /// in `SessionStore.compactActiveThread`.
    case compact
    /// `/review [scope]` — open a draft thread that asks Codex to audit
    /// the working tree (default scope = `working`; `staged`, `main`, or
    /// any git ref accepted). Implementation lives in
    /// `SessionStore.startReviewThread(scope:)`.
    case review(String)

    public static func parse(_ input: String) -> Self? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "/new" { return .newTask }
        if text == "/clear" { return .clear }
        if text == "/init" { return .initProject }
        if text == "/compact" { return .compact }
        if text == "/review" { return .review("") }
        if let rest = text.strippingLocalCommandPrefix("review") {
            return .review(rest)
        }
        if let rest = text.strippingLocalCommandPrefix("model") {
            return .model(rest)
        }
        guard text.hasPrefix("/goal") else { return nil }
        let rest = text.dropFirst(5)
        guard rest.isEmpty || rest.first?.isWhitespace == true else { return nil }
        return .goal(rest.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private extension String {
    /// Returns the trimmed payload after `/<cmd>` when the input is exactly
    /// `/<cmd>` or `/<cmd> <rest>` (one or more whitespace separators).
    /// Returns nil when the input is `/<cmd>…` with no separator or when
    /// the prefix doesn't match — this keeps `/modelA` / `/modeling`
    /// /`请解释 /model` falling through to the model as ordinary text.
    func strippingLocalCommandPrefix(_ cmd: String) -> String? {
        let token = "/" + cmd
        guard self == token else {
            guard self.hasPrefix(token) else { return nil }
            let next = self.index(self.startIndex, offsetBy: token.count)
            guard next < self.endIndex,
                  self[next].isWhitespace else { return nil }
            let trimmed = self[next...].trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil // bare "/<cmd>" with no payload falls through to the model
    }
}
