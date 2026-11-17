import Foundation

/// Alert copy for the three notification triggers.
enum MobileNotificationText {
    /// Reply preview kept in a completion alert.
    static let previewLimit = 120

    /// One-line reply preview.
    /// - Parameter text: assistant reply.
    /// - Returns: collapsed whitespace, truncated with an ellipsis.
    static func preview(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > previewLimit else { return collapsed }
        return String(collapsed.prefix(previewLimit)) + "…"
    }

    /// Completion alert body.
    /// - Parameters:
    ///   - sessionTitle: conversation name.
    ///   - reply: latest assistant reply.
    /// - Returns: `会话 · 回复摘录`, or `会话 · 回合完成` when empty.
    static func completed(sessionTitle: String, reply: String) -> String {
        let summary = preview(reply)
        return summary.isEmpty ? "\(sessionTitle) · 回合完成" : "\(sessionTitle) · \(summary)"
    }

    /// Failure alert body.
    /// - Parameters:
    ///   - sessionTitle: conversation name.
    ///   - reason: Host turn-end reason.
    /// - Returns: `会话 · 运行出错`.
    static func failed(sessionTitle: String, reason: String?) -> String {
        let detail = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return detail.isEmpty ? "\(sessionTitle) · 运行出错" : "\(sessionTitle) · \(detail)"
    }

    /// Pending approval body.
    /// - Parameters:
    ///   - sessionTitle: conversation name.
    ///   - toolName: tool awaiting approval.
    /// - Returns: `会话 · 等待批准：工具`.
    static func approval(sessionTitle: String, toolName: String) -> String {
        "\(sessionTitle) · 等待批准：\(toolName)"
    }
}
