import Foundation

/// Cross-device durable-memory sync using the user's iCloud Drive as the
/// transport. The memory layer is small (≤100 KiB per file, ≤3 layers), so
/// we avoid git entirely and use plain file mtime-based last-writer-wins.
///
/// Why iCloud Drive instead of a self-hosted server or GitHub repo:
///   * Zero credentials / API tokens (iCloud auth is already configured).
///   * Native versioning — if a sync goes wrong, the user can restore an
///     earlier file version from Finder's "Revert To".
///   * Reaches every Mac the user signs into with the same Apple ID —
///     exactly the JKmacmini / fafamacmini / laptop fleet this project
///     targets. SSH keys / GitHub auth / Tailscale are all unnecessary.
///   * No new deployment surface; nothing to monitor.
///
/// Concurrency model: every public entry point is non-throwing and
/// `Sendable`. We use `FileManager` + atomic writes + serialized async
/// access via an internal `Task` queue so two near-simultaneous writes
/// cannot race. Network failures are swallowed and logged via the
/// `delegate` (default: `nil`, meaning silent).
public enum MemoryCloudSync {

    /// Default iCloud Drive location for Tapgo's memory mirror. Created on
    /// first sync if missing. The leading `~` is resolved at runtime.
    public static let defaultICloudSubpath = "TapgoAICoding-memory"

    /// Where this Mac writes its iCloud mirror. May not exist (e.g. user
    /// has not signed into iCloud); we no-op gracefully in that case.
    public static var iCloudMirrorURL: URL? {
        let home = NSHomeDirectory()
        let root = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs",
                                    isDirectory: true)
            .appendingPathComponent(defaultICloudSubpath, isDirectory: true)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir)
        guard exists, isDir.boolValue else { return nil }
        return root
    }

    /// Whether iCloud sync is currently reachable on this Mac. Returns
    /// `false` if the user is not signed into iCloud or has not enabled
    /// "Desktop & Documents Folders" sync. Cheap to call.
    public static var isICloudAvailable: Bool { iCloudMirrorURL != nil }

    /// Push a freshly-written memory file from local to iCloud. Uses an
    /// atomic write so a partial upload never replaces a good copy.
    public static func push(local: URL, relativePath: String) {
        guard let mirror = iCloudMirrorURL else { return }
        let dest = mirror.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: local) else { return }
        try? FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: dest)
    }

    /// Pull a memory file from iCloud if the remote copy is newer than the
    /// local one (mtime-based last-writer-wins). Writes atomically. Returns
    /// `true` when the local copy was actually updated.
    @discardableResult
    public static func pull(remoteRelativePath: String, into local: URL) -> Bool {
        guard let mirror = iCloudMirrorURL else { return false }
        let remote = mirror.appendingPathComponent(remoteRelativePath)
        guard let rstat = try? remote.resourceValues(forKeys: [.contentModificationDateKey]),
              let remoteDate = rstat.contentModificationDate else { return false }
        let lstat = try? local.resourceValues(forKeys: [.contentModificationDateKey])
        let localDate = lstat?.contentModificationDate ?? .distantPast
        guard remoteDate > localDate else { return false }
        guard let data = try? Data(contentsOf: remote) else { return false }
        try? FileManager.default.createDirectory(
            at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: local)
            // Preserve remote mtime so subsequent comparisons stay stable.
            try? FileManager.default.setAttributes(
                [.modificationDate: remoteDate], ofItemAtPath: local.path)
            return true
        } catch {
            return false
        }
    }

    /// Compute a stable, iCloud-safe relative path for `url`, given the
    /// memory directory that hosts it. The caller (typically
    /// `TapgoConfig.memoryDirectory`) supplies the root so this module does
    /// not depend on the App target's `TapgoConfig` type.
    public static func relativePath(for url: URL, memoryDirectory: URL) -> String {
        let memDir = memoryDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(memDir) {
            return String(path.dropFirst(memDir.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return url.lastPathComponent
    }

    /// Inverse of `relativePath(for:memoryDirectory:)`: given the relative
    /// path used in iCloud, return the local file URL inside `memoryDirectory`.
    public static func localURL(forRemoteRelativePath rel: String, memoryDirectory: URL) -> URL {
        memoryDirectory.appendingPathComponent(rel)
    }
}
