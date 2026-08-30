// TapgoCore/ProviderRegistry.swift
// v0.5.53 起：把所有模型供应商（含内置 + 自定义）持久化到
// `provider-registry.json`（0600），取代 v0.5.42~v0.5.52 的 model-registry.json
// 与分散的 auth.json / auth-glm.json / auth-deepseek.json。
//
// 与 ModelRegistry 的差异：
//   * 一份 JSON 描述所有 Provider（含 baseURL + apiKey + models 数组）
//   * 每个 Provider 自带 models，自定义模型不再与 Key 分离
//   * 首次启动 v0.5.53 自动从旧 model-registry.json + auth*.json 迁移
//
// 与 TapgoProviderKind 配套：内置 Provider 由 kind.registryID 稳定
// 标识，自定义 Provider 用 "custom-<uuid>"。

import Foundation

public struct ProviderRegistryState: Codable, Equatable {
    public var providers: [Provider] = []
    public var selectedProviderID: String = ""
    public var selectedModelPerProvider: [String: String] = [:]

    public init() {}

    public init(
        providers: [Provider] = [],
        selectedProviderID: String = "",
        selectedModelPerProvider: [String: String] = [:]
    ) {
        self.providers = providers
        self.selectedProviderID = selectedProviderID
        self.selectedModelPerProvider = selectedModelPerProvider
    }

    enum CodingKeys: String, CodingKey {
        case providers
        case selectedProviderID
        case selectedModelPerProvider
    }

    // v0.5.53：显式 encode/decode 让 `[String: String]` 编为 JSON object，
    // 避免默认 `[key1, val1, key2, val2]` array-of-pairs 写法，让外部
    // `jq` 与测试断言更直观。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        providers = try c.decode([Provider].self, forKey: .providers)
        selectedProviderID = try c.decodeIfPresent(String.self, forKey: .selectedProviderID) ?? ""
        selectedModelPerProvider = try c.decodeIfPresent([String: String].self, forKey: .selectedModelPerProvider) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(providers, forKey: .providers)
        try c.encode(selectedProviderID, forKey: .selectedProviderID)
        try c.encode(selectedModelPerProvider, forKey: .selectedModelPerProvider)
    }
}

/// 供应商注册表（v0.5.53 起）。纯文件驱动、无全局单例。
public final class ProviderRegistry {
    public let fileURL: URL
    public private(set) var state: ProviderRegistryState
    /// v0.5.52 旧文件路径，用于一次性迁移。
    public let legacyModelRegistryURL: URL
    public let legacyAuthPaths: [URL]

    public init(
        fileURL: URL,
        legacyModelRegistryURL: URL? = nil,
        legacyAuthPaths: [URL] = []
    ) {
        self.fileURL = fileURL
        self.legacyModelRegistryURL = legacyModelRegistryURL
            ?? fileURL.deletingLastPathComponent()
                .appendingPathComponent("model-registry.json")
        self.legacyAuthPaths = legacyAuthPaths
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(ProviderRegistryState.self, from: data) {
            self.state = decoded
        } else {
            self.state = ProviderRegistryState()
        }
    }

    // MARK: - 迁移（v0.5.52 → v0.5.53）

    /// 若旧 model-registry.json / auth*.json 存在，则把它们转成 Provider
    /// 并写回当前 registry。返回「是否执行了迁移」。
    @discardableResult
    public func migrateFromLegacyIfNeeded() -> Bool {
        let legacy = legacyModelRegistryURL
        let authPaths = legacyAuthPaths
        guard FileManager.default.fileExists(atPath: legacy.path) ||
              authPaths.contains(where: { FileManager.default.fileExists(atPath: $0.path) })
        else { return false }
        // 1) 先补齐内置 Provider（auth Key 合并依赖它们已存在）
        ensureBuiltinProviders()
        // 2) 尝试从旧 model-registry.json 拿所有自定义模型
        var customModels: [CustomModel] = []
        if let data = try? Data(contentsOf: legacy),
           let decoded = try? JSONDecoder().decode(LegacyRegistryState.self, from: data) {
            customModels = decoded.customModels
        }
        // 2) 把每个 CustomModel 转成一个独立 Provider（一个 Provider 一模型）
        for cm in customModels {
            let normalized = cm.normalizedForStorage()
            if normalized.validationErrors.first != nil { continue }
            let pid = "custom-" + UUID().uuidString.prefix(8).uppercased()
            let mid = pid + "::" + normalized.apiModel
            let provider = Provider(
                id: pid,
                displayName: normalized.displayName.isEmpty ? normalized.brand : normalized.displayName,
                brand: normalized.brand,
                baseURL: normalized.baseURL,
                apiKey: normalized.apiKey,
                models: [
                    ProviderModel(
                        id: mid,
                        displayName: normalized.displayName,
                        apiModel: normalized.apiModel,
                        contextWindow: CustomModel.normalizedContextWindow(normalized.contextWindow),
                        isCustom: true)
                ],
                builtInKindRaw: nil
            )
            state.providers.append(provider)
            state.selectedModelPerProvider[pid] = mid
        }
        // 3) 把每个 auth*.json 中的 Key 合并到对应的内置 Provider
        for (path, kind) in authPaths.compactMap({ url -> (URL, TapgoProviderKind)? in
            // 约定：文件名包含 glm → zhipu；deepseek → deepseek；否则 → minimax
            let name = url.lastPathComponent.lowercased()
            if name.contains("glm") { return (url, .zhipu) }
            if name.contains("deepseek") { return (url, .deepseek) }
            return (url, .minimax)
        }) {
            guard let data = try? Data(contentsOf: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let key = json["OPENAI_API_KEY"] as? String,
                  !key.isEmpty
            else { continue }
            let targetID = kind.registryID
            if let idx = state.providers.firstIndex(where: { $0.id == targetID }) {
                state.providers[idx].apiKey = key
            }
        }
        save()
        // 5) 把旧文件 mv 到 backup 后删除（不直接 rm，保留 tar 备份语义）
        let backupDir = fileURL.deletingLastPathComponent()
            .appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupFile = backupDir.appendingPathComponent(
            "model-registry.legacy-\(stamp).json")
        if FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: backupFile)
        }
        for path in authPaths {
            guard FileManager.default.fileExists(atPath: path.path) else { continue }
            let bk = backupDir.appendingPathComponent(
                "\(path.lastPathComponent).legacy-\(stamp)")
            try? FileManager.default.moveItem(at: path, to: bk)
        }
        return true
    }

    /// 旧 model-registry.json 的反序列化镜像（私有，仅迁移用）。
    private struct LegacyRegistryState: Codable {
        let customModels: [CustomModel]
    }

    // MARK: - 持久化

    /// 保证内置 Provider 都存在；缺失则按 kind 补回。
    public func ensureBuiltinProviders() {
        for kind in TapgoProviderKind.allCases {
            if !state.providers.contains(where: { $0.id == kind.registryID }) {
                state.providers.append(.builtin(kind))
            }
        }
    }

    public func save() {
        do {
            let encoder = JSONEncoder()
            // v0.5.53：显式 sortedKeys + 让 [String:String] 编为 object
            // （默认行为跨 SDK 不稳）。同时 prettyPrinted 便于手工排查。
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            // 落盘失败保留内存版本即可，上层会拿到错误并重试
            FileHandle.standardError.write(Data(
                "ProviderRegistry.save failed: \(error)\n".utf8))
        }
    }

    // MARK: - Queries

    public var providers: [Provider] { state.providers }
    public func provider(id: String) -> Provider? {
        state.providers.first { $0.id == id }
    }
    public var builtinProviders: [Provider] {
        state.providers.filter { $0.isBuiltin }
    }
    public var customProviders: [Provider] {
        state.providers.filter { !$0.isBuiltin }
    }
    public var selectedProviderID: String { state.selectedProviderID }

    /// 当前选中的 Provider；选中态为空时返回第一个内置。
    public func resolveSelectedProvider() -> Provider {
        ensureBuiltinProviders()
        if let p = state.providers.first(where: { $0.id == state.selectedProviderID }) {
            return p
        }
        return state.providers.first ?? .builtin(.zhipu)
    }

    public func resolveSelectedModel(for provider: Provider) -> ProviderModel {
        if let mid = state.selectedModelPerProvider[provider.id],
           let m = provider.models.first(where: { $0.id == mid }) {
            return m
        }
        return provider.models.first ?? ProviderModel(
            id: provider.id + "::placeholder",
            displayName: provider.displayName,
            apiModel: provider.displayName,
            contextWindow: 128_000,
            isCustom: !provider.isBuiltin)
    }

    // MARK: - Mutations

    public func addOrUpdate(_ provider: Provider) {
        ensureBuiltinProviders()
        let normalized = provider
        let validated = normalized.validationErrors(apiKeyRequired: !provider.isBuiltin)
        guard validated.isEmpty || provider.isBuiltin else { return }
        if let idx = state.providers.firstIndex(where: { $0.id == normalized.id }) {
            // 内置 Provider：仅允许改 apiKey / baseURL / models，不允许改 displayName / brand
            if state.providers[idx].isBuiltin {
                state.providers[idx].apiKey = normalized.apiKey
                state.providers[idx].baseURL = normalized.baseURL
                state.providers[idx].models = normalized.models
            } else {
                state.providers[idx] = normalized
            }
        } else {
            state.providers.append(normalized)
        }
        save()
    }

    @discardableResult
    public func removeProvider(id: String) -> Bool {
        ensureBuiltinProviders()
        guard let idx = state.providers.firstIndex(where: { $0.id == id }) else { return false }
        guard !state.providers[idx].isBuiltin else { return false }
        state.providers.remove(at: idx)
        if state.selectedProviderID == id { state.selectedProviderID = "" }
        state.selectedModelPerProvider.removeValue(forKey: id)
        save()
        return true
    }

    public func setSelectedProvider(id: String) {
        state.selectedProviderID = id
        save()
    }

    public func setSelectedModel(_ model: ProviderModel, for provider: Provider) {
        state.selectedModelPerProvider[provider.id] = model.id
        save()
    }

    /// 持久化 Provider 内嵌的模型列表（用于编辑 Provider 时整体替换）。
    public func updateModels(_ models: [ProviderModel], for providerID: String) {
        guard let idx = state.providers.firstIndex(where: { $0.id == providerID }) else { return }
        state.providers[idx].models = models
        save()
    }

    /// 仅更新某个 Provider 的 Key（builtin/custom 通用，UI 主要用）。
    public func setAPIKey(_ key: String, for providerID: String) {
        guard let idx = state.providers.firstIndex(where: { $0.id == providerID }) else { return }
        state.providers[idx].apiKey = key
        save()
    }

    /// UI 占位：写但 settings UI 不调；为后续 v0.5.54 拖拽排序预留。
    public func reorderProviders(_ newOrder: [String]) {
        let map = Dictionary(uniqueKeysWithValues: state.providers.map { ($0.id, $0) })
        state.providers = newOrder.compactMap { map[$0] }
        save()
    }
}
