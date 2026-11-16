import Foundation

/// Bounds long code blocks while keeping the full source available for copying.
enum MobileCodePreview {
    /// Lines shown before a block collapses.
    static let lineLimit = 40

    /// Source lines currently shown for one block.
    /// - Parameters:
    ///   - value: full code block.
    ///   - expanded: whether the reader expanded the block.
    ///   - limit: lines shown while collapsed.
    /// - Returns: the whole block when it fits or is expanded, otherwise its first `limit` lines.
    static func visible(_ value: String, expanded: Bool, limit: Int = lineLimit) -> String {
        guard !expanded, limit > 0 else { return value }
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > limit else { return value }
        return lines.prefix(limit).joined(separator: "\n")
    }

    /// Whether the block offers an expand control.
    /// - Parameters:
    ///   - value: full code block.
    ///   - limit: lines shown while collapsed.
    /// - Returns: true when the block exceeds the collapsed limit.
    static func isCollapsible(_ value: String, limit: Int = lineLimit) -> Bool {
        guard limit > 0 else { return false }
        return value.split(separator: "\n", omittingEmptySubsequences: false).count > limit
    }

    /// Number of source lines.
    /// - Parameter value: full code block.
    /// - Returns: the line count shown in the expand control.
    static func lineCount(_ value: String) -> Int {
        value.split(separator: "\n", omittingEmptySubsequences: false).count
    }
}
