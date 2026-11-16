import Foundation

/// One workspace file loaded for native preview.
struct MobileWorkspaceFile: Equatable {
    let path: String
    let name: String
    let data: Data
    var byteCount: Int { data.count }
}

/// Why a workspace file could not be prepared for preview.
enum MobileFilePreviewError: LocalizedError, Equatable {
    case unavailable
    case refused(String)
    case tooLarge(Int)
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Host 未返回文件内容"
        case .refused(let message): return message
        case .tooLarge(let bytes): return "文件过大（\(MobileFileSize.format(bytes))），请下载到电脑查看"
        case .writeFailed: return "无法写入临时文件"
        }
    }
}

/// Short human-readable byte size.
enum MobileFileSize {
    /// Formats a byte count for captions.
    /// - Parameter bytes: number of bytes.
    /// - Returns: a localized file-size string.
    static func format(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// Decodes the multipart form the Host uses for RPC results carrying bytes.
enum MobileMultipart {
    /// Splits one multipart body into named parts.
    /// - Parameters:
    ///   - data: response body.
    ///   - contentType: response Content-Type carrying the boundary.
    /// - Returns: part name to raw bytes.
    /// - Throws: `MobileFilePreviewError.unavailable` when the boundary or framing is malformed.
    static func parse(data: Data, contentType: String) throws -> [String: Data] {
        guard let boundary = boundary(from: contentType), !boundary.isEmpty else {
            throw MobileFilePreviewError.unavailable
        }
        let delimiter = Data("--\(boundary)".utf8)
        let headerSeparator = Data("\r\n\r\n".utf8)
        let framing = Data("\r\n".utf8)
        var parts: [String: Data] = [:]
        var remaining = data
        while let delimiterRange = remaining.range(of: delimiter) {
            remaining = remaining[delimiterRange.upperBound...]
            if remaining.starts(with: Data("--".utf8)) { break }
            if remaining.starts(with: framing) { remaining = remaining.dropFirst(2) }
            guard let headerRange = remaining.range(of: headerSeparator) else { break }
            let headers = String(decoding: remaining[..<headerRange.lowerBound], as: UTF8.self)
            let bodyStart = headerRange.upperBound
            guard let next = remaining.range(of: delimiter, options: [], in: bodyStart..<remaining.endIndex) else { break }
            var body = remaining[bodyStart..<next.lowerBound]
            if body.count >= 2, body.suffix(2) == framing { body = body.dropLast(2) }
            if let name = partName(in: headers) { parts[name] = Data(body) }
            remaining = remaining[next.lowerBound...]
        }
        guard !parts.isEmpty else { throw MobileFilePreviewError.unavailable }
        return parts
    }

    private static func boundary(from contentType: String) -> String? {
        guard let range = contentType.range(of: "boundary=") else { return nil }
        let rest = contentType[range.upperBound...]
        if rest.hasPrefix("\"") {
            let inner = rest.dropFirst()
            let value = inner.prefix { $0 != "\"" }
            return value.isEmpty ? nil : String(value)
        }
        let value = rest.prefix { $0 != ";" && $0 != " " }
        return value.isEmpty ? nil : String(value)
    }

    private static func partName(in headers: String) -> String? {
        for line in headers.split(separator: "\r\n") where line.lowercased().contains("content-disposition") {
            guard let range = line.range(of: "name=\"") else { continue }
            let rest = line[range.upperBound...]
            let value = rest.prefix { $0 != "\"" }
            return value.isEmpty ? nil : String(value)
        }
        return nil
    }
}
