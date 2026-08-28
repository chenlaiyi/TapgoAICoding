import Foundation
import Combine

/// iOS 端配对状态机 (与 Mac 端 `MobilePairing.swift` 字段对齐)。
///
/// 本文件落地 iOS 端缺失的 `PairingStore`, 让 `PairingView.swift` / `TapgoTerminalApp.swift`
/// 能编译; 协议定义见 `mobile/CONFIG.md` 与 `Sources/TapgoCore/MobilePairing.swift`。
///
/// Keychain / Bonjour 长链接 / 真实扫码都在后续版本补; v0.5.5 先做手动输入闭环。
@MainActor
final class PairingStore: ObservableObject {

    @Published private(set) var state: MobilePairing.State = .unpaired
    @Published private(set) var lastError: String? = nil

    /// Keychain 抽象, 方便单测注入内存实现。
    protocol SecureStorage {
        func save(mac: MobilePairing.PairedMac) throws
        func load() throws -> MobilePairing.PairedMac?
        func clear() throws
    }

    /// 默认 UserDefaults 实现 (v0.5.5), 真实 Keychain 在 v0.5.6 接 SecureEnclave。
    final class UserDefaultsStorage: SecureStorage {
        private let defaults: UserDefaults
        private let key = "tapgo.pair.lastPairedMac"
        init(defaults: UserDefaults = .standard) { self.defaults = defaults }
        func save(mac: MobilePairing.PairedMac) throws {
            let data = try JSONEncoder().encode(mac)
            defaults.set(data, forKey: key)
        }
        func load() throws -> MobilePairing.PairedMac? {
            guard let data = defaults.data(forKey: key) else { return nil }
            return try JSONDecoder().decode(MobilePairing.PairedMac.self, from: data)
        }
        func clear() throws { defaults.removeObject(forKey: key) }
    }

    private let storage: SecureStorage

    init(storage: SecureStorage = UserDefaultsStorage()) {
        self.storage = storage
        if let mac = try? storage.load() {
            self.state = .paired(mac, connected: false)
        }
    }

    /// 处理从 `tapgo-pair://...` URL 触发的配对 (iOS 扫码/Universal Link)。
    func handleIncomingURL(_ url: URL) {
        guard let payload = MobilePairing.parseIncomingURL(url) else {
            lastError = "无法识别的配对链接"
            return
        }
        completePairing(payload: payload)
    }

    enum AcceptResult {
        case success
        case failure(String)
    }

    /// 手动输入 6 位码。比对当前期望值由 Mac 端主动通过 Bonjour 推送;
    /// v0.5.5 暂时信任输入即视为成功, 真实校验在下个版本补。
    func acceptManualCode(_ raw: String, completion: @escaping (AcceptResult) -> Void) {
        let code = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard MobilePairing.isValidCode(code) else {
            completion(.failure("请输入 6 位字符集内的配对码"))
            return
        }
        // 手动输入没有 host/port, 用本地占位; Bonjour 发现后会覆盖。
        let mac = MobilePairing.PairedMac(deviceId: "manual-input",
                                          hostname: "未连接",
                                          host: "127.0.0.1",
                                          port: 0,
                                          pairedAt: Date())
        state = .paired(mac, connected: false)
        try? storage.save(mac: mac)
        lastError = nil
        completion(.success)
    }

    func markConnected(_ connected: Bool) {
        if case .paired(let mac, _) = state {
            state = .paired(mac, connected: connected)
        }
    }

    func unpair() {
        state = .unpaired
        try? storage.clear()
    }

    private func completePairing(payload: MobilePairing.IncomingPayload) {
        let mac = payload.toPairedMac()
        state = .paired(mac, connected: false)
        try? storage.save(mac: mac)
        lastError = nil
    }
}
