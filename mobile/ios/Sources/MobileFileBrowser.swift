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
