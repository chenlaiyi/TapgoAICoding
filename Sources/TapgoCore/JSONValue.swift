import Foundation

/// A minimal, Sendable JSON value used by the JSON-RPC layer.
/// We intentionally don't bridge to Swift's `Any` so that values can cross
/// actor boundaries safely.
public indirect enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
    public var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    public var intValue: Int? { if case .int(let i) = self { return i } else { return nil } }
    public var boolValue: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }

    /// Defensive accessor for JSON numeric fields whose source might
    /// or might not be a JSON literal `true`/`false`.
    ///
    /// Foundation's `JSONDecoder` decodes any non-zero JSON number as
    /// `true` for `Bool.self` (and `0` as `false`). That means a JSON
    /// `1` arrives here as `.bool(true)` even though it was a number
    /// in the wire payload. Callers that want a numeric exitCode or
    /// id should use this helper so the legacy `1 == true` quirk
    /// doesn't silently zero them out.
    public var intOrBoolAsInt: Int? {
        if case .int(let i) = self { return i }
        if case .bool(let b) = self { return b ? 1 : 0 }
        return nil
    }

    /// Same defensive accessor for double-typed numeric fields.
    public var doubleOrBoolAsDouble: Double? {
        if case .double(let d) = self { return d }
        if case .int(let i) = self { return Double(i) }
        if case .bool(let b) = self { return b ? 1.0 : 0.0 }
        return nil
    }

    /// Render as a compact JSON string. Used by log lines so we
    /// never emit Swift `description` formatting (which can be
    /// expensive for large objects).
    public func toJSONString() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let s = String(data: data, encoding: .utf8) else { return "<unencodable>" }
        return s
    }
}
