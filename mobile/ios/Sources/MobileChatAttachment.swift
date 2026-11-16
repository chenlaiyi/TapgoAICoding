import Foundation

/// Numeric/string accessors for untyped wire JSON shared by mobile decoders.
enum MobileWireValue {
    /// Reads an integral JSON number or numeric string.
    /// - Parameter value: decoded `JSONSerialization` value.
    /// - Returns: the integer value, or nil when the value is absent or non-numeric.
    static func int(_ value: Any?) -> Int? {
        switch value {
        case let value as Int: return value
        case let value as NSNumber: return value.intValue
        case let value as Double: return Int(value)
        case let value as String: return Int(value)
        default: return nil
        }
    }

    /// Reads a JSON string.
    /// - Parameter value: decoded `JSONSerialization` value.
    /// - Returns: the string value, or nil when absent or not a string.
    static func string(_ value: Any?) -> String? {
        value as? String
    }
}

/// Host admission limits for image prompts.
struct MobileImageLimits: Equatable {
    let maxImageBytes: Int
    let maxImagesPerMessage: Int
    let maxMessageImageBytes: Int
    let maxImagePixels: Int
    let maxImageDimension: Int

    /// Limits used when this Host does not report its attachment projection.
    static let fallback = MobileImageLimits(
        maxImageBytes: 50 * 1_024 * 1_024,
        maxImagesPerMessage: 20,
        maxMessageImageBytes: 200 * 1_024 * 1_024,
        maxImagePixels: 64_000_000,
        maxImageDimension: 65_535
    )

    /// Decodes the `imageLimits` projection value.
    /// - Parameter wire: projection value containing every limit.
    /// - Returns: decoded limits, or nil when a required limit is missing or invalid.
    init?(wire: [String: Any]) {
        guard let maxImageBytes = MobileWireValue.int(wire["maxImageBytes"]), maxImageBytes > 0,
              let maxImagesPerMessage = MobileWireValue.int(wire["maxImagesPerMessage"]), maxImagesPerMessage > 0,
              let maxMessageImageBytes = MobileWireValue.int(wire["maxMessageImageBytes"]), maxMessageImageBytes > 0,
              let maxImagePixels = MobileWireValue.int(wire["maxImagePixels"]), maxImagePixels > 0,
              let maxImageDimension = MobileWireValue.int(wire["maxImageDimension"]), maxImageDimension > 0 else {
            return nil
        }
        self.init(maxImageBytes: maxImageBytes, maxImagesPerMessage: maxImagesPerMessage,
                  maxMessageImageBytes: maxMessageImageBytes, maxImagePixels: maxImagePixels,
                  maxImageDimension: maxImageDimension)
    }

    init(maxImageBytes: Int, maxImagesPerMessage: Int, maxMessageImageBytes: Int,
         maxImagePixels: Int, maxImageDimension: Int) {
        self.maxImageBytes = maxImageBytes
        self.maxImagesPerMessage = maxImagesPerMessage
        self.maxMessageImageBytes = maxMessageImageBytes
        self.maxImagePixels = maxImagePixels
        self.maxImageDimension = maxImageDimension
    }
}

/// Durable image reference supplied by the Host.
struct MobileImageRef: Equatable {
    let attachmentID: String
    let mediaType: String
    let bytes: Int
    let width: Int
    let height: Int
    let name: String?

    /// Ratio used for placeholder layout; falls back when dimensions are absent.
    var aspectRatio: Double {
        guard width > 0, height > 0 else { return 4.0 / 3.0 }
        return Double(width) / Double(height)
    }

    /// Decodes one `image` content block attachment.
    /// - Parameter wire: attachment object from a session event.
    /// - Returns: decoded reference, or nil when identity or media type is missing.
    init?(wire: [String: Any]) {
        guard let attachmentID = MobileWireValue.string(wire["attachmentId"]), !attachmentID.isEmpty,
              let mediaType = MobileWireValue.string(wire["mediaType"]), !mediaType.isEmpty else { return nil }
        self.attachmentID = attachmentID
        self.mediaType = mediaType
        self.bytes = MobileWireValue.int(wire["bytes"]) ?? 0
        self.width = MobileWireValue.int(wire["width"]) ?? 0
        self.height = MobileWireValue.int(wire["height"]) ?? 0
        self.name = MobileWireValue.string(wire["name"])
    }

    /// Wire value accepted by `session/attachment`.
    var wire: [String: Any] {
        var value: [String: Any] = [
            "attachmentId": attachmentID,
            "mediaType": mediaType,
            "bytes": bytes,
            "width": width,
            "height": height,
        ]
        if let name { value["name"] = name }
        return value
    }
}

/// Durable file reference supplied by the Host.
struct MobileFileRef: Equatable {
    let attachmentID: String
    let name: String
    let bytes: Int

    /// Decodes one `file` content block attachment.
    /// - Parameter wire: attachment object from a session event.
    /// - Returns: decoded reference, or nil when identity is missing.
    init?(wire: [String: Any]) {
        guard let attachmentID = MobileWireValue.string(wire["attachmentId"]), !attachmentID.isEmpty else { return nil }
        self.attachmentID = attachmentID
        self.name = MobileWireValue.string(wire["name"]) ?? "文件"
        self.bytes = MobileWireValue.int(wire["bytes"]) ?? 0
    }
}

/// One attachment rendered inside a transcript message.
enum MobileMessageAttachment: Equatable {
    case image(MobileImageRef)
    case file(MobileFileRef)

    /// Stable key for cache and diffing.
    var identity: String {
        switch self {
        case .image(let image): return "image:\(image.attachmentID)"
        case .file(let file): return "file:\(file.attachmentID)"
        }
    }

    /// Image reference when this attachment is an image.
    var image: MobileImageRef? {
        if case .image(let image) = self { return image }
        return nil
    }

    /// File reference when this attachment is a file.
    var file: MobileFileRef? {
        if case .file(let file) = self { return file }
        return nil
    }
}

/// Text, reasoning, and attachments decoded from one message's content blocks.
struct MobileMessageContent: Equatable {
    let text: String
    let reasoning: String
    let attachments: [MobileMessageAttachment]

    /// Decodes the content blocks of one user or assistant message.
    /// - Parameter blocks: `content` array from a session message.
    /// - Returns: joined text, joined reasoning, and recognized attachments.
    static func parse(blocks: [[String: Any]]) -> MobileMessageContent {
        var text: [String] = []
        var reasoning: [String] = []
        var attachments: [MobileMessageAttachment] = []
        for block in blocks {
            switch MobileWireValue.string(block["type"]) {
            case "text":
                if let value = MobileWireValue.string(block["text"]) { text.append(value) }
            case "reasoning":
                if let value = MobileWireValue.string(block["text"]) { reasoning.append(value) }
            case "image":
                if let wire = block["attachment"] as? [String: Any], let reference = MobileImageRef(wire: wire) {
                    attachments.append(.image(reference))
                }
            case "file":
                if let wire = block["attachment"] as? [String: Any], let reference = MobileFileRef(wire: wire) {
                    attachments.append(.file(reference))
                }
            default:
                continue
            }
        }
        return MobileMessageContent(text: text.joined(separator: "\n\n"),
                                    reasoning: reasoning.joined(separator: "\n\n"),
                                    attachments: attachments)
    }
}
