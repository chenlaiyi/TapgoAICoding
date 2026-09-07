import Foundation
import Security

/// Keychain 实现的 SecureStorage。
///
/// - Service: `com.devtools.terminalSimple.pairing`（与 Core 端 `MobilePairing.StorageKeys.keychainService` 对齐）。
/// - Account: `pairedMac`。
/// - Access: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` —— 设备解锁后才可读，且不随 iCloud 同步，
///   适合存本地凭证。
/// - 不指定 accessGroup，模拟器与单设备签名场景下都不需要 App Groups entitlement；
///   后续如要做 Mac ↔ iOS 跨设备 Keychain 共享，再走 `group.com.devtools.terminalSimple` 并加 entitlement。
///
/// 任何 Keychain 操作失败都会抛 `KeychainError`，由 `PairingStore` 决定是否 fallback 到 UserDefaults。
struct PairingKeychain: PairingStore.SecureStorage {
    private let service: String
    private let account = "pairedMac"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(service: String = "com.devtools.terminalSimple.pairing") {
        self.service = service
    }

    enum KeychainError: Error, CustomStringConvertible {
        case unhandled(OSStatus)
        case decode(Error)
        case encode(Error)
        var description: String {
            switch self {
            case .unhandled(let s): return "Keychain error: OSStatus=\(s)"
            case .decode(let e):    return "Keychain decode error: \(e)"
            case .encode(let e):    return "Keychain encode error: \(e)"
            }
        }
    }

    func save(mac: MobilePairing.PairedMac) throws {
        let data: Data
        do { data = try encoder.encode(mac) } catch { throw KeychainError.encode(error) }

        // 先删旧的，再 insert 新值，保持单一最新。
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var attrs = baseQuery
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    func load() throws -> MobilePairing.PairedMac? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
        guard let data = item as? Data else { return nil }
        do { return try decoder.decode(MobilePairing.PairedMac.self, from: data) }
        catch { throw KeychainError.decode(error) }
    }

    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}

/// 探测用：在某个 service 下写一条 1 字节再读回，验证 Keychain 可用。
/// 成功返回 true；任何 OSStatus != errSecSuccess 都返回 false。
struct PairingKeychainProbeKey {
    let service: String
    func writeAndRead() -> Bool {
        let probeAccount = "probe"
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: probeAccount
        ]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = Data([0])
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { return false }
        var item: CFTypeRef?
        let readStatus = SecItemCopyMatching(q as CFDictionary, &item)
        SecItemDelete(q as CFDictionary)
        return readStatus == errSecSuccess
    }
}
