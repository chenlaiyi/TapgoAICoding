import Foundation

/// One direct child of a workspace directory.
struct MobileDirectoryEntry: Decodable, Equatable, Identifiable {
    let name: String
    let type: String
    let size: Int?

    var id: String { name }
    var isDirectory: Bool { type == "directory" }
    /// Whether the entry is a regular file the preview can try to read.
    var isFile: Bool { type == "file" }
}

/// Direct children of one workspace directory.
struct MobileDirectoryListing: Decodable, Equatable {
    let path: String
    let entries: [MobileDirectoryEntry]
    let truncated: Bool
}

/// Reader-facing message for a Host workspace-file refusal.
enum MobileWorkspaceError: LocalizedError, Equatable {
    case refused(String)

    var errorDescription: String? {
        switch self { case .refused(let message): return message }
    }

    /// Maps a Host code to a message the file browser can show.
    /// - Parameters:
    ///   - code: Host error code, if any.
    ///   - fallback: Host message used for unknown codes.
    /// - Returns: a localized explanation.
    static func message(code: String?, fallback: String?) -> String {
        switch code {
        case "workspace-file/not-found": return "文件或目录不存在"
        case "workspace-file/not-directory": return "这不是一个目录"
        case "workspace-file/outside-workspace": return "该路径不在工作区内"
        case "workspace-file/too-large": return "文件过大，无法读取"
        case "workspace-file/not-text": return "该文件不是文本"
        case "workspace-file/not-regular-file": return "该路径不是普通文件"
        case "gateway/lookup-not-found": return "会话不存在，无法定位工作区"
        case "workspace-file/watch-unsupported": return "当前 Host 不支持文件监听"
        default: return fallback ?? "读取失败，请重试"
        }
    }
}

/// Workspace path joining and presentation rules for the file browser.
enum MobileFileBrowser {
    /// Joins a child name to the parent's workspace-relative path.
    /// - Parameters:
    ///   - name: entry name inside the parent.
    ///   - directory: parent path, empty at the workspace root.
    /// - Returns: the child's workspace-relative path.
    static func child(_ name: String, of directory: String) -> String {
        directory.isEmpty ? name : "\(directory)/\(name)"
    }

    /// Parent path of one workspace-relative path.
    /// - Parameter path: workspace-relative path.
    /// - Returns: the parent path, empty at the root.
    static func parent(of path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }

    /// Display path for a breadcrumb or title.
    /// - Parameter path: workspace-relative path.
    /// - Returns: `/` for the root, otherwise the path.
    static func display(_ path: String) -> String {
        path.isEmpty ? "/" : path
    }

    /// VoiceOver label for one directory entry.
    /// - Parameter entry: entry from a listing.
    /// - Returns: name, kind, and size when the Host reports one.
    static func accessibilityLabel(for entry: MobileDirectoryEntry) -> String {
        var parts = [entry.name]
        if entry.isDirectory {
            parts.append("文件夹")
        } else if entry.isFile {
            parts.append("文件")
        } else {
            parts.append("其他条目")
        }
        if let size = entry.size { parts.append(MobileFileSize.format(size)) }
        return parts.joined(separator: "，")
    }

    /// Filters one listing by a case-insensitive name substring.
    /// - Parameters:
    ///   - entries: entries from one listing.
    ///   - search: name substring; surrounding whitespace is ignored.
    /// - Returns: matching entries in their original order.
    static func filtered(_ entries: [MobileDirectoryEntry], search: String) -> [MobileDirectoryEntry] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(needle) }
    }

    /// Presentation order: directories first, then file names in the reader's collation.
    /// - Parameter entries: entries from one listing.
    /// - Returns: the sorted entries.
    static func sorted(_ entries: [MobileDirectoryEntry]) -> [MobileDirectoryEntry] {
        entries.sorted { left, right in
            if left.isDirectory != right.isDirectory { return left.isDirectory }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }
}
