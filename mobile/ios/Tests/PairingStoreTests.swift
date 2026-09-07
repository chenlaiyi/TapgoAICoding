import Foundation

/// PairingStore 单元测试。本机 `swiftc -emit-executable` 直接跑, 不依赖 iOS SDK。
///
/// 关键覆盖:
/// - `handleIncomingURL` 解析 `tapgo-pair://` URL 后切到 paired 状态
/// - `acceptManualCode` 6 位合法码切到 paired 状态
/// - `unpair` 回到 unpaired
/// - InMemoryStorage 跑遍 SecureStorage round-trip
@main
@MainActor
struct PairingStoreTests {
    static func main() {
        do { try runAll() }
        catch { print("THROW: \(error)"); exit(1) }
    }
    static func runAll() throws {
        var passed = 0, failed = 0
        func check(_ cond: Bool, _ name: String) {
            if cond { passed += 1 } else { failed += 1; print("FAIL: \(name)") }
        }

        // 1. handleIncomingURL 用合法 URL
        do {
            let store = PairingStore(storage: InMemoryStorage(), fallback: nil)
            check(store.state.isPaired == false, "init unpaired")
            let url = URL(string: "tapgo-pair://mac-001?code=KYAEHS&host=100.71.223.108&port=8723&v=1#JKmacmini")!
            store.handleIncomingURL(url)
            check(store.state.isPaired, "after handleIncomingURL -> paired")
            if case .paired(let mac, _) = store.state {
                check(mac.deviceId == "mac-001", "mac.deviceId")
                check(mac.host == "100.71.223.108", "mac.host")
                check(mac.port == 8723, "mac.port")
                check(mac.hostname == "JKmacmini", "mac.hostname")
            } else {
                check(false, "state shape")
            }
        }

        // 2. handleIncomingURL 用非法 URL: state 不变, lastError 出现
        do {
            let store = PairingStore(storage: InMemoryStorage(), fallback: nil)
            let bad = URL(string: "tapgo-pair://mac-002?code=BADCODE&host=foo&port=8723&v=1")!
            store.handleIncomingURL(bad)
            check(store.state.isPaired == false, "bad code stays unpaired")
            check(store.lastError != nil, "bad code sets lastError")
        }

        // 3. handleIncomingURL 错误 scheme 直接拒绝
        do {
            let store = PairingStore(storage: InMemoryStorage(), fallback: nil)
            let wrong = URL(string: "https://example.com")!
            store.handleIncomingURL(wrong)
            check(store.state.isPaired == false, "wrong scheme stays unpaired")
        }

        // 4. handleIncomingURL v=0 协议不匹配
        do {
            let store = PairingStore(storage: InMemoryStorage(), fallback: nil)
            let v0 = URL(string: "tapgo-pair://mac-003?code=KYAEHS&host=1.2.3.4&port=8723&v=0")!
            store.handleIncomingURL(v0)
            check(store.state.isPaired == false, "v=0 stays unpaired")
        }

        // 5. acceptManualCode 6 位合法码
        do {
            let store = PairingStore(storage: InMemoryStorage(), fallback: nil)
            var r: PairingStore.AcceptResult = .success
            store.acceptManualCode("ky  ae hs") { r = $0 }
            check(store.state.isPaired, "manual code -> paired")
            if case .failure = r { check(false, "manual code should succeed") }
        }

        // 6. acceptManualCode 非法字符
        do {
            let store = PairingStore(storage: InMemoryStorage(), fallback: nil)
            var r: PairingStore.AcceptResult = .success
            store.acceptManualCode("BAD!@#") { r = $0 }
            if case .success = r { check(false, "bad chars should fail") }
        }

        // 7. unpair 回到 unpaired
        do {
            let store = PairingStore(storage: InMemoryStorage(), fallback: nil)
            store.handleIncomingURL(URL(string: "tapgo-pair://mac-004?code=KYAEHS&host=10.0.0.1&port=8723&v=1")!)
            check(store.state.isPaired, "before unpair paired")
            store.unpair()
            check(store.state.isPaired == false, "after unpair unpaired")
        }

        // 8. InMemoryStorage round-trip (模拟 Keychain 持久化)
        do {
            let storage = InMemoryStorage()
            let mac = MobilePairing.PairedMac(deviceId: "x", hostname: "y", host: "1.2.3.4", port: 1234, pairedAt: Date())
            try storage.save(mac: mac)
            let loaded = try storage.load()
            check(loaded?.deviceId == "x", "storage round-trip deviceId")
            check(loaded?.port == 1234, "storage round-trip port")
            try storage.clear()
            check(try storage.load() == nil, "storage clear")
        }

        // 9. 持久化路径: 写完再 init PairingStore 应该读到
        do {
            let storage = InMemoryStorage()
            let mac = MobilePairing.PairedMac(deviceId: "persist", hostname: "h", host: "1.1.1.1", port: 99, pairedAt: Date())
            try storage.save(mac: mac)
            let store = PairingStore(storage: storage, fallback: nil)
            if case .paired(let m, _) = store.state {
                check(m.deviceId == "persist", "init from persisted")
            } else {
                check(false, "init from persisted shape")
            }
        }

        // 10. handleIncomingURL 后 macInfo 字段 (DashboardView 用)
        do {
            let store = PairingStore(storage: InMemoryStorage(), fallback: nil)
            let url = URL(string: "tapgo-pair://dev-x?code=KYAEHS&host=192.168.1.10&port=8723&v=1#my-mac")!
            store.handleIncomingURL(url)
            if case .paired(let mac, let conn) = store.state {
                check(mac.deviceId == "dev-x", "deviceId")
                check(mac.hostname == "my-mac", "hostname fragment")
                check(conn == false, "connected default false")
            } else { check(false, "state") }
        }

        print("PairingStore 测试: passed=\(passed) failed=\(failed)")
        if failed > 0 { exit(1) }
    }
}

/// 内存版 SecureStorage, 用于测试不依赖 Keychain 的行为。
final class InMemoryStorage: PairingStore.SecureStorage {
    private var stored: MobilePairing.PairedMac?
    func save(mac: MobilePairing.PairedMac) throws { stored = mac }
    func load() throws -> MobilePairing.PairedMac? { stored }
    func clear() throws { stored = nil }
}
