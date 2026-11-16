import Foundation

/// Prepares durable image bytes for saving to Photos and for sharing as a file.
enum MobileImageExport {
    /// Extension used when the media type names none.
    static let fallbackExtension = "jpg"

    /// Builds a file name that is safe to write and share.
    /// - Parameters:
    ///   - name: Host display name, which may contain a path or be missing.
    ///   - mediaType: MIME type of the stored image.
    /// - Returns: the sanitized leaf name, with the media type's extension when the name has none.
    static func fileName(name: String?, mediaType: String) -> String {
        let base = sanitized(name) ?? "图片"
        if base.contains(".") { return base }
        return "\(base).\(fileExtension(for: mediaType))"
    }

    /// Writes one image into the share directory under its resolved file name.
    /// - Parameters:
    ///   - data: original image bytes returned by the Host.
    ///   - name: Host display name for the attachment.
    ///   - mediaType: MIME type of the stored image.
    ///   - directory: writable directory that receives the file.
    /// - Returns: the file URL that can be handed to a share sheet.
    static func write(data: Data, name: String?, mediaType: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(fileName(name: name, mediaType: mediaType))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Maps a stored image MIME type to the extension a share sheet expects.
    /// - Parameter mediaType: MIME type reported by the Host.
    /// - Returns: the conventional file extension for that type.
    private static func fileExtension(for mediaType: String) -> String {
        let subtype = mediaType.split(separator: "/").last.map(String.init)?.lowercased() ?? ""
        let base = subtype.split(separator: "+").first.map(String.init) ?? ""
        if base.isEmpty { return fallbackExtension }
        if base == "jpeg" { return "jpg" }
        return base.replacingOccurrences(of: ".", with: "")
    }

    /// Strips path separators, control characters, and leading dots from a Host display name.
    /// - Parameter name: display name reported by the Host, when present.
    /// - Returns: the leaf name, or nil when nothing usable remains.
    private static func sanitized(_ name: String?) -> String? {
        guard let name else { return nil }
        let leaf = name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? name
        let cleaned = leaf.components(separatedBy: .controlCharacters).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return trimmed.isEmpty ? nil : trimmed
    }
}
