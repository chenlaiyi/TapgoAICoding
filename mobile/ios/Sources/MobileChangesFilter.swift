import Foundation

/// Category shown by the file-change sheet.
enum MobileChangesCategory: String, CaseIterable, Identifiable {
    case all = "全部"
    case deliverables = "交付物"

    var id: String { rawValue }
}

/// Filters the Host's retained turn comparison by category and path text.
enum MobileChangesFilter {
    /// Applies the selected category and a case-insensitive path filter.
    /// - Parameters:
    ///   - files: files from the turn's change summary.
    ///   - category: all files or only presented deliverables.
    ///   - search: path substring; surrounding whitespace is ignored.
    ///   - deliverables: paths the turn presented as final deliverables.
    /// - Returns: matching files in their original order.
    static func files(_ files: [MobileChangesSummary.File], category: MobileChangesCategory,
                      search: String, deliverables: Set<String>) -> [MobileChangesSummary.File] {
        files.filter { fileMatches($0, category: category, search: search, deliverables: deliverables) }
    }

    /// Whether one changed file passes the selected category and search text.
    /// - Parameters:
    ///   - file: changed file.
    ///   - category: all files or only presented deliverables.
    ///   - search: path substring; surrounding whitespace is ignored.
    ///   - deliverables: paths the turn presented as final deliverables.
    /// - Returns: true when the file belongs in the filtered list.
    static func fileMatches(_ file: MobileChangesSummary.File, category: MobileChangesCategory,
                            search: String, deliverables: Set<String>) -> Bool {
        guard category == .all || matches(file: file, deliverables: deliverables) else { return false }
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return file.path.localizedCaseInsensitiveContains(needle)
            || file.display.localizedCaseInsensitiveContains(needle)
    }

    /// Whether one changed path is in the presented deliverable set.
    /// - Parameters:
    ///   - file: changed file.
    ///   - deliverables: presented paths, which may be absolute.
    /// - Returns: true when the change path matches a deliverable exactly or as its workspace-relative suffix.
    static func matches(file: MobileChangesSummary.File, deliverables: Set<String>) -> Bool {
        if deliverables.contains(file.path) { return true }
        return deliverables.contains { absolute in
            absolute == file.path || absolute.hasSuffix("/" + file.path)
        }
    }
}
