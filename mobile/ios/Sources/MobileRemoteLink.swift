import Foundation

/// iOS ↔ Mac 长链接 JSON-RPC over TCP 协议层 (v1)。
///
/// 设计原则: 纯 Foundation, 不依赖 Network/SwiftUI, 便于 iOS 与 Mac
/// 端共用同一份帧定义, 方便 SwiftPM 单元测试覆盖。
///
/// 协议要点:
/// - 单连接 TCP, JSON 行分隔 (`\n`); 服务端先 respond, 客户端可任意时刻 push
/// - 每帧 JSON: `{"id":"<uuid>", "method":"<m>", "params":{...}, "result":{...}|"error":{...}}`
/// - 心跳: `{"method":"hello", "params":{"version":1, "deviceId":"..."}}` 每 10s
/// - 服务端推送: `{"method":"<m>", "params":{...}}` (无 id, 客户端不回)
/// - 错误: `{"error":{"code":-1, "message":"..."}}`
public enum MobileRemoteLink {

    public static let protocolVersion = 1
    /// Bonjour service type。Mac 端 `_tapgo-pair._tcp` 域监听此服务。
    public static let bonjourServiceType = "_tapgo-pair._tcp"
    /// 默认端口。与 MobilePairing.defaultPort 对齐。
    public static let defaultPort = 8723

    // MARK: - Frame types

    public struct Frame: Equatable, Codable {
        public let id: String?
        public let method: String?
        public let params: Params?
        public let result: Params?
        public let error: RPCError?

        enum CodingKeys: String, CodingKey {
            case id, method, params, result, error
        }

        public init(id: String? = nil,
                    method: String? = nil,
                    params: Params? = nil,
                    result: Params? = nil,
                    error: RPCError? = nil) {
            self.id = id
            self.method = method
            self.params = params
            self.result = result
            self.error = error
        }

        public var isRequest: Bool { id != nil && method != nil }
        public var isResponse: Bool { id != nil && (result != nil || error != nil) }
        public var isPush: Bool { id == nil && method != nil }
    }

    /// Params 是任意 JSON 对象的桥接类型。encode 时输出 JSON object, decode 时从 JSON object 还原。
    public struct Params: Equatable, Codable {
        public var raw: [String: AnyJSON]

        public init(_ raw: [String: AnyJSON] = [:]) { self.raw = raw }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: DynamicKey.self)
            var out: [String: AnyJSON] = [:]
            for k in c.allKeys {
                if let v = try? c.decode(AnyJSON.self, forKey: k) {
                    out[k.stringValue] = v
                }
            }
            self.raw = out
        }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: DynamicKey.self)
            for (k, v) in raw {
                let key = DynamicKey(stringValue: k)!
                try c.encode(v, forKey: key)
            }
        }

        public subscript(key: String) -> AnyJSON? { raw[key] }

        public mutating func set(_ key: String, _ value: AnyJSON) {
            raw[key] = value
        }
    }

    /// JSON 值: String / Int / Double / Bool / null / array / object。
    public enum AnyJSON: Equatable, Codable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case null
        case array([AnyJSON])
        case object([String: AnyJSON])

        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null; return }
            if let v = try? c.decode(Bool.self) { self = .bool(v); return }
            if let v = try? c.decode(Int.self) { self = .int(v); return }
            if let v = try? c.decode(Double.self) { self = .double(v); return }
            if let v = try? c.decode(String.self) { self = .string(v); return }
            if let v = try? c.decode([AnyJSON].self) { self = .array(v); return }
            if let v = try? c.decode([String: AnyJSON].self) { self = .object(v); return }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "AnyJSON cannot decode")
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .string(let v): try c.encode(v)
            case .int(let v):    try c.encode(v)
            case .double(let v): try c.encode(v)
            case .bool(let v):   try c.encode(v)
            case .null:          try c.encodeNil()
            case .array(let v):  try c.encode(v)
            case .object(let v): try c.encode(v)
            }
        }

        public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
        public var intValue: Int? { if case .int(let i) = self { return i }; return nil }
        public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
        public var objectValue: [String: AnyJSON]? { if case .object(let o) = self { return o }; return nil }
        public var arrayValue: [AnyJSON]? { if case .array(let a) = self { return a }; return nil }
        public subscript(key: String) -> AnyJSON? {
            if case .object(let o) = self { return o[key] }
            return nil
        }
    }

    public struct RPCError: Equatable, Codable {
        public let code: Int
        public let message: String
        public init(code: Int, message: String) {
            self.code = code; self.message = message
        }
    }

    /// 标准方法名常量, 减少字符串拼写错误。
    public enum Method {
        public static let hello = "hello"
        public static let heartbeat = "heartbeat"
        public static let listSessions = "listSessions"
        public static let switchProject = "switchProject"
        public static let sendMessage = "sendMessage"
        public static let pushSessionUpdate = "sessionUpdate"
        public static let pushMessage = "message"
    }

    // MARK: - 帧编解码

    /// 把 Frame 序列化成单行 JSON (不带尾部换行, 调用方负责加 `\n`)。
    public static func encode(_ frame: Frame) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        return try enc.encode(frame)
    }

    /// 从一行 JSON Data 反序列化。失败抛错。
    public static func decode(_ data: Data) throws -> Frame {
        try JSONDecoder().decode(Frame.self, from: data)
    }

    // MARK: - 高层构造器

    public static func makeRequest(id: String = UUID().uuidString,
                                    method: String,
                                    params: Params = Params()) -> Frame {
        Frame(id: id, method: method, params: params)
    }

    public static func makeResult(id: String, result: Params) -> Frame {
        Frame(id: id, method: nil, params: nil, result: result, error: nil)
    }

    public static func makeError(id: String, code: Int, message: String) -> Frame {
        Frame(id: id, method: nil, params: nil, result: nil,
              error: RPCError(code: code, message: message))
    }

    public static func makePush(method: String, params: Params) -> Frame {
        Frame(id: nil, method: method, params: params)
    }

    public static func makeHello(deviceId: String) -> Frame {
        var p = Params()
        p.set("version", .int(protocolVersion))
        p.set("deviceId", .string(deviceId))
        return makePush(method: Method.hello, params: p)
    }

    public static func makeHeartbeat() -> Frame {
        makePush(method: Method.heartbeat, params: Params())
    }
}

/// 任意 string key, 用于 Params 的 dynamic coding。
struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
