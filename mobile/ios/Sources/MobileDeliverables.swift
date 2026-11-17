import Foundation

/// One file a turn delivered or linked in its reply.
struct MobileDeliverable: Identifiable, Equatable {
    let path: String

    var id: String { path }
    var name: String { MobileFilePreviewName.name(forPath: path) }
    var isImage: Bool {
        ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif"].contains(
            (path as NSString).pathExtension.lowercased())
    }
    var subtitle: String {
        let parent = (path as NSString).deletingLastPathComponent
        return (parent as NSString).lastPathComponent
    }
}

/// Collects delivered files and local file links from one reply.
enum MobileDeliverables {
    /// Extensions treated as openable local files in Markdown links.
    static let fileExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "pdf", "md", "txt",
        "json", "csv", "zip", "mp4", "mov", "swift", "ts", "log", "html", "xml", "yaml", "yml",
    ]

    /// Deduplicated deliverables in presentation order.
    /// - Parameter paths: presented file paths.
    /// - Returns: distinct, trimmed entries.
    static func list(_ paths: [String]) -> [MobileDeliverable] {
        var seen = Set<String>()
        return paths.compactMap { path in
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return MobileDeliverable(path: trimmed)
        }
    }

    /// Local file targets in Markdown links.
    /// - Parameter text: assistant reply Markdown.
    /// - Returns: absolute paths or workspace-relative paths, in link order.
    static func linkedFiles(in text: String) -> [String] {
        let pattern = #"\[[^\]]*\]\(([^)\s]+)\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let targetRange = Range(match.range(at: 1), in: text) else { return nil }
            let target = String(text[targetRange])
            if target.hasPrefix("file://") { return URL(string: target)?.path }
            if target.contains("://") { return nil }
            guard fileExtensions.contains((target as NSString).pathExtension.lowercased()) else { return nil }
            return target.hasPrefix("./") ? String(target.dropFirst(2)) : target
        }
    }

    /// Merges delivered paths with local file links, keeping first appearance order.
    /// - Parameters:
    ///   - deliverables: paths from `deliverables/presented`.
    ///   - text: the reply Markdown.
    /// - Returns: distinct files ready for the attachment card.
    static func merged(deliverables: [String], text: String) -> [MobileDeliverable] {
        list(deliverables + linkedFiles(in: text))
    }
}
