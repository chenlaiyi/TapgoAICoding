import Foundation

/// Renders a `Turn` as plain markdown so the user can copy/export a
/// conversation (Codex supports copy/export). Terse but faithful:
/// assistant text passes through, commands/executions become fenced
/// code blocks, file changes and errors are labelled.
public enum TurnMarkdown {
    public static func render(_ turn: Turn) -> String {
        var blocks: [String] = []
        for item in turn.items {
            switch item {
            case .userMessage(_, let text):
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { blocks.append("**用户**: \(t)") }
            case .assistantMessage(_, let text) where !item.isAppGeneratedProgress:
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { blocks.append(t) }
            case .assistantMessage:
                break
            case .reasoning(_, let text):
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { blocks.append("> 思考: \(t)") }
            case .reasoningSummary(_, let text):
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { blocks.append("> 摘要: \(t)") }
            case .toolCall(let tc):
                blocks.append("`\(tc.name)` \(tc.arguments)")
                if let r = tc.result, !r.isEmpty {
                    blocks.append("  → \(r)")
                }
            case .commandExecution(let ce):
                var out = "```sh\n$ \(ce.command)\n"
                if !ce.stdout.isEmpty { out += ce.stdout }
                if !ce.stderr.isEmpty { out += ce.stderr }
                if let code = ce.exitCode { out += "\n# exit \(code)" }
                out += "\n```"
                blocks.append(out)
            case .fileChange(let fc):
                blocks.append("**\(fc.kind.rawValue)**: \(fc.path)")
            case .approval(let ar):
                blocks.append("**审批**: \(ar.kind.rawValue)")
            case .error(_, let m):
                blocks.append("**错误**: \(m)")
            }
        }
        return blocks.joined(separator: "\n\n")
    }
}
