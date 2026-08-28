import Foundation

/// Copies user-submitted images out of clipboard/temp locations into an
/// app-owned directory suitable for persisted conversation thumbnails.
public enum UserImageAttachmentStore {
    public static func persist(
        _ sources: [URL],
        baseDirectory: URL,
        threadId: String,
        turnId: String,
        fileManager: FileManager = .default
    ) -> [String] {
        guard !sources.isEmpty else { return [] }
        let directory = baseDirectory
            .appendingPathComponent(safeComponent(threadId), isDirectory: true)
            .appendingPathComponent(safeComponent(turnId), isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch {
            return sources.map(\.path)
        }

        return sources.map { source in
            let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
            let destination = directory.appendingPathComponent("image-\(UUID().uuidString).\(ext)")
            do {
                try fileManager.copyItem(at: source, to: destination)
                try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                return destination.path
            } catch {
                // Keep the image visible for this launch even if persistence
                // fails; callers can still send the original source to Harness.
                return source.path
            }
        }
    }

    @discardableResult
    public static func removeAll(
        baseDirectory: URL,
        threadId: String,
        fileManager: FileManager = .default
    ) -> Bool {
        let directory = baseDirectory.appendingPathComponent(safeComponent(threadId), isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return true }
        do {
            try fileManager.removeItem(at: directory)
            return true
        } catch {
            return false
        }
    }

    private static func safeComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let result = String(mapped)
        return result.isEmpty ? UUID().uuidString : result
    }
}
