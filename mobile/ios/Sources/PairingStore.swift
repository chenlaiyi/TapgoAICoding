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

    /// 长链接客户端。配对完成后由 markConnected(true) 自动 start(),
    /// 连接成功后通过 onConnectionChange 回调翻转 state.connected。
    let link = PairingLink()
    private var linkStarted = false

    /// 默认走 Keychain（与 Apple Secure Enclave 设备绑定，更安全）。
    /// Keychain 在某些环境（如未签名模拟器 + 严格 entitlement）写入会失败，
    /// 失败时退到 UserDefaults，保证开发期可用。
    init(storage: SecureStorage = PairingKeychain(),
         fallback: SecureStorage? = UserDefaultsStorage()) {
        // 先探测 Keychain 是否可用（写入+读回一条空数据）。
        var chosen: SecureStorage = storage
        if let fb = fallback {
            let probe = PairingKeychainProbeKey(service: "com.devtools.terminalSimple.probe")
            if probe.writeAndRead() == false {
                chosen = fb
            }
        }
        self.storage = chosen
        if let mac = try? chosen.load() {
            self.state = .paired(mac, connected: false)
            // init 后立刻尝试启动长链接 (Bonjour 发现 → TCP → JSON-RPC)。
            // markConnected(true) 会被 onConnectionChange 回调反向触发,
            // 这里主动调一次启动浏览器。
            link.expectedDeviceId = mac.deviceId
            link.onConnectionChange = { [weak self] live in
                self?.markConnected(live)
            }
            linkStarted = true
            link.start()
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
            if connected, !linkStarted {
                linkStarted = true
                link.expectedDeviceId = mac.deviceId
                link.onConnectionChange = { [weak self] live in
                    self?.markConnected(live)
                }
                link.start()
            }
        }
    }

    /// App 后台切换 / 主动停止时调用, 释放 NWBrowser + NWConnection。
    func stopLink() {
        link.stop()
        linkStarted = false
        if case .paired(let mac, _) = state {
            state = .paired(mac, connected: false)
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
