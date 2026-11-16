import Foundation

/// Bounds the live reply preview so an extremely long unterminated answer stays cheap to render.
enum MobileStreamPreview {
    /// Longest tail kept for the live preview.
    static let maxCharacters = 8_000

    /// The newest tail of an unterminated answer, prefixed by an ellipsis when shortened.
    /// - Parameters:
    ///   - text: full text of the live attempt.
    ///   - limit: maximum characters kept.
    /// - Returns: the whole text when it fits, otherwise `…` plus its newest `limit` characters.
    static func bounded(_ text: String, limit: Int = maxCharacters) -> String {
        guard limit > 0, text.count > limit else { return text }
        return "…" + text.suffix(limit)
    }

    /// Live text with an unfinished trailing pipe table held back until its block closes.
    /// - Parameters:
    ///   - text: full text of the live attempt.
    ///   - limit: maximum characters kept, applied first.
    /// - Returns: the preview without a table that is still being written.
    static func stableTail(_ text: String, limit: Int = maxCharacters) -> String {
        let tail = bounded(text, limit: limit)
        let lines = tail.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return tail }
        var end = lines.count
        var trailingEmpty = 0
        while end > 0, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            end -= 1
            trailingEmpty += 1
        }
        // A blank separator line closes the table's block, so the table is safe to show.
        guard trailingEmpty < 2 else { return tail }
        var start = end
        while start > 0, lines[start - 1].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
            start -= 1
        }
        guard start < end else { return tail }
        // Pipe lines inside an open code fence are code, not a table.
        let fences = lines[..<start].filter {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("```")
        }.count
        guard fences % 2 == 0 else { return tail }
        let kept = lines[..<start].joined(separator: "\n")
        if kept.isEmpty { return "" }
        return kept + (kept.hasSuffix("\n") ? "" : "\n")
    }

    /// Whether the live preview was shortened.
    /// - Parameters:
    ///   - text: full text of the live attempt.
    ///   - limit: maximum characters kept.
    /// - Returns: true when `bounded` would drop earlier characters.
    static func isTruncated(_ text: String, limit: Int = maxCharacters) -> Bool {
        limit > 0 && text.count > limit
    }
}
