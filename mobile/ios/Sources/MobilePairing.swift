import Foundation

/// Mac ↔ iOS 配对协议 (v1)。
///
/// 设计原则: Core 层只用 Foundation, 不依赖 SwiftUI / Combine, 方便 iOS 与 Mac
/// 端共用同一份字符串 / 状态机定义, 也方便 SwiftPM 单元测试覆盖。
public enum MobilePairing {

    /// 协议版本号。任何字段或帧格式变更必须 bump 这个版本。
    public static let protocolVersion = "1"

    /// URL Scheme。iOS Info.plist 已注册 `tapgo-pair`, 见 `mobile/CONFIG.md`。
    public static let urlScheme = "tapgo-pair"

    /// 配对码字符集: 去除 0/O/1/I/L 等易混淆字符。
    public static let alphabet: [Character] = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    /// 配对码长度。
    public static let codeLength = 6

    /// 配对码默认有效秒数。
    public static let defaultTTL: TimeInterval = 60

    /// 配对码默认本地监听端口。
    public static let defaultPort = 8723

    /// 一个 6 位配对码实例, 附带生成时间和本地端口。
    public struct PairCode: Equatable, Hashable {
        public let value: String
        public let issuedAt: Date
        public let expiresAt: Date
        public let port: Int

        public init(value: String, issuedAt: Date, ttl: TimeInterval, port: Int) {
            self.value = value
            self.issuedAt = issuedAt
            self.expiresAt = issuedAt.addingTimeInterval(ttl)
            self.port = port
        }

        public func isValid(at now: Date = Date()) -> Bool {
            now < expiresAt
        }

        public func remainingSeconds(at now: Date = Date()) -> Int {
            max(0, Int(expiresAt.timeIntervalSince(now).rounded(.up)))
        }
    }

    /// iOS 端扫码/手输成功后写回的配对元数据。
    public struct PairedMac: Codable, Equatable, Hashable {
        public let deviceId: String
        public let hostname: String
        public let host: String
        public let port: Int
        public let pairedAt: Date

        public init(deviceId: String, hostname: String, host: String, port: Int, pairedAt: Date) {
            self.deviceId = deviceId
            self.hostname = hostname
            self.host = host
            self.port = port
            self.pairedAt = pairedAt
        }
    }

    /// 配对会话的对外状态。Mac 与 iOS 端共用一份, 字段保持稳定。
    public enum State: Equatable, Hashable {
        case unpaired
        case paired(PairedMac, connected: Bool)

        public var isPaired: Bool {
            if case .paired = self { return true } else { return false }
        }

        public var mac: PairedMac? {
            if case .paired(let m, _) = self { return m } else { return nil }
        }

        public var connected: Bool {
            if case .paired(_, let c) = self { return c } else { return false }
        }
    }

    /// 生成 6 位配对码。用确定性可重现的方式 (注入 rng) 方便测试。
    public static func generateCode(ttl: TimeInterval = defaultTTL,
                                    port: Int = defaultPort,
                                    now: Date = Date(),
                                    rng: () -> UInt64 = { UInt64.random(in: 0...UInt64.max) }) -> PairCode {
        var raw = UInt64(0)
        repeat { raw = rng() } while raw == 0
        var chars: [Character] = []
        chars.reserveCapacity(codeLength)
        var n = raw
        for _ in 0..<codeLength {
            let idx = Int(n % UInt64(alphabet.count))
            chars.append(alphabet[idx])
            n /= UInt64(alphabet.count)
            if n == 0 { n = raw &+ 0x9E37_79B9_7F4A_7C15 }
        }
        return PairCode(value: String(chars), issuedAt: now, ttl: ttl, port: port)
    }

    /// 校验字符串是否为合法配对码 (字符集 + 长度)。
    public static func isValidCode(_ s: String) -> Bool {
        guard s.count == codeLength else { return false }
        return s.allSatisfy { c in alphabet.contains(c) }
    }

    /// 把 Mac 当前状态打包成 iOS 可消费的 URL。
    public static func pairingURL(macDeviceId: String,
                                  hostname: String,
                                  host: String,
                                  code: PairCode) -> URL? {
        var comps = URLComponents()
        comps.scheme = urlScheme
        comps.host = macDeviceId
        comps.queryItems = [
            URLQueryItem(name: "code", value: code.value),
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "port", value: String(code.port)),
            URLQueryItem(name: "v", value: protocolVersion)
        ]
        // hostname 走 fragment, iOS 端展示用, 不参与匹配
        comps.fragment = hostname
        return comps.url
    }

    /// iOS 端解析 `tapgo-pair://...` URL。
    public static func parseIncomingURL(_ url: URL) -> IncomingPayload? {
        guard url.scheme == urlScheme else { return nil }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let deviceId = comps.host ?? url.host ?? ""
        let items = comps.queryItems ?? []
        var dict: [String: String] = [:]
        for item in items { dict[item.name] = item.value }
        guard let code = dict["code"], let host = dict["host"], let portStr = dict["port"], let port = Int(portStr) else {
            return nil
        }
        guard isValidCode(code) else { return nil }
        let version = dict["v"] ?? "0"
        guard version == protocolVersion else { return nil }
        let hostname = comps.fragment ?? host
        return IncomingPayload(macDeviceId: deviceId,
                               hostname: hostname,
                               host: host,
                               port: port,
                               code: code,
                               version: version)
    }

    public struct IncomingPayload: Equatable, Hashable {
        public let macDeviceId: String
        public let hostname: String
        public let host: String
        public let port: Int
        public let code: String
        public let version: String

        public func toPairedMac(now: Date = Date()) -> PairedMac {
            PairedMac(deviceId: macDeviceId, hostname: hostname, host: host, port: port, pairedAt: now)
        }
    }

    /// 构造 iOS Keychain 写入用的 service+account, Mac 端 UserDefaults 也共用。
    public enum StorageKeys {
        public static let userDefaultsMacDeviceIdKey = "tapgo.pair.macDeviceId"
        public static let userDefaultsLastPairedMacKey = "tapgo.pair.lastPairedMac"
        public static let keychainService = "com.devtools.terminalSimple.pairing"
    }
}

// MARK: - iOS 工程自包含副本
/* 本文件是 Sources/TapgoCore/MobilePairing.swift 的同源拷贝，供独立 iOS 工程
 * (mobile/ios/) 在不通过 SwiftPM 引用 TapgoCore 模块的情况下也能用同一份协议。
 * 一致性由 mobile/ios/Scripts/check-sync.sh 通过 diff 强制保证：
 * 任何一端改动必须同步另一端，否则 build 脚本会拒绝并打印差异。 */
