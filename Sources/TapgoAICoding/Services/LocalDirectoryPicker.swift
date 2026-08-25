import AppKit
import Foundation
import TapgoCore

/// NSOpenPanel-based local directory picker. Resolves a real
/// security-scoped bookmark on macOS so the path keeps working
/// across launches and (later) sandboxed builds.
///
/// The bookmark is stored on the `Project` so a re-pick in the
/// settings view can be safely re-validated; an empty bookmark
/// is fine for un-sandboxed builds (the build we ship today).
enum LocalDirectoryPicker {
    enum PickerError: LocalizedError {
        case userCancelled
        case notADirectory(URL)
        case bookmarkResolutionFailed(URL)
        var errorDescription: String? {
            switch self {
            case .userCancelled: return "已取消"
            case .notADirectory(let url): return "不是目录: \(url.path)"
            case .bookmarkResolutionFailed(let url): return "无法解析 bookmark: \(url.path)"
            }
        }
    }

    /// Synchronously prompt the user to pick a directory. Returns
    /// the resolved URL + the security-scoped bookmark data.
    static func pickDirectory() throws -> (url: URL, bookmark: Data?) {
        let panel = NSOpenPanel()
        panel.title = "选择项目目录"
        panel.message = "选择一个本地目录作为项目工作区"
        panel.prompt = "选定"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = false
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            throw PickerError.userCancelled
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw PickerError.notADirectory(url)
        }
        let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return (url, bookmark)
    }

    /// Re-resolve a stored bookmark; returns nil if the path is no
    /// longer accessible (e.g. volume ejected or permission revoked).
    /// `isStale` is set when macOS considers the bookmark obsolete
    /// (e.g. the user moved the folder); the caller should re-pick
    /// in that case.
    static func resolveBookmark(_ data: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        let opts: URL.BookmarkResolutionOptions = [.withSecurityScope]
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: opts,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        return (url, isStale)
    }
}
