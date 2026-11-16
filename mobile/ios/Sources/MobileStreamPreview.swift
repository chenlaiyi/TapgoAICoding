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

    /// Whether the live preview was shortened.
    /// - Parameters:
    ///   - text: full text of the live attempt.
    ///   - limit: maximum characters kept.
    /// - Returns: true when `bounded` would drop earlier characters.
    static func isTruncated(_ text: String, limit: Int = maxCharacters) -> Bool {
        limit > 0 && text.count > limit
    }
}
