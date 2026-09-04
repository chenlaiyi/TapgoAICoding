import Foundation
import TapgoCore

/// All paths and on-disk templates for Tapgo AICoding's isolated Codex home.
/// We never read or write anything under `~/.codex/`; everything lives under
/// `~/Library/Application Support/Tapgo AICoding/codex/`.
enum TapgoConfig {
    /// Default region. China is the only one we ship — change here if you ever
    /// need a different endpoint.
    static let defaultRegion: Region = .china

    enum Region: String, CaseIterable, Identifiable {
        case china
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .china: return "中国 (api.minimaxi.com)"
            }
        }
        var baseURL: String {
            switch self {
            case .china: return "https://api.minimaxi.com/v1"
            }
        }
    }

    /// 默认模型与 provider（config.toml 顶层缺省值）。v0.5.31 起支持
    /// 多模型切换：实际每个新会话用哪个由 `selectedModel` 决定，经
    /// `thread/start` 显式下发；后台任务（记忆整理、额度查询）固定 MiniMax。
    static let modelName = TapgoModel.minimaxM3.rawValue
    /// 当前订阅的 MiniMax 套餐显示名 (接口不返回套餐名, 以实际订阅为准)。
    static let planDisplayName = "Ultra"
    static let modelProvider = TapgoModel.minimaxM3.providerId
    static let serviceName = "tapgo_aicoding"
    static let clientInfoName = "tapgo_aicoding"
    static let clientInfoTitle = "Tapgo AICoding"
    static let clientInfoVersion = "0.5.2"

    /// Token threshold at which the codex harness auto-compacts the transcript
    /// into a summary (replaces the user having to manually start a new
    /// session). Sits below `model_context_window` so compaction happens
    /// before the model hits the wall.
    // MiniMax-M3 currently exposes a 1M context window. Compact at 80%,
    // matching the pressure-based strategy used by current agent harnesses.
    static let autoCompactTokenLimit = 800_000

    /// Memory directory hosting the three-layer durable memory model:
    /// `user.md` (cross-project user prefs), `memory.md` (global env / tools),
    /// `key-<branch>.md` (per-project, per-git-branch decisions).
    static var memoryDirectory: URL {
        codexHome.deletingLastPathComponent().appendingPathComponent("memory", isDirectory: true)
    }

    /// Backwards-compatible single-file location. Older builds wrote to
    /// `codex/memory.md`. We auto-migrate to `memory/user.md` on first read.
    static var legacyUserMemoryURL: URL {
        codexHome.deletingLastPathComponent().appendingPathComponent("memory.md")
    }

    static var userMemoryURL: URL {
        memoryDirectory.appendingPathComponent("user.md")
    }

    static var globalMemoryURL: URL {
        memoryDirectory.appendingPathComponent("memory.md")
    }

    /// Per-project, per-git-branch key file. We sanitize `branch` to keep it
    /// filename-safe; `main` and unknown branches all share `key-main.md`.
    static func keyMemoryURL(projectRoot: URL?, branch: String?) -> URL {
        let dir = memoryDirectory.appendingPathComponent("keys", isDirectory: true)
        let safeBranch = sanitizeBranchName(branch ?? "main")
        return dir.appendingPathComponent("key-\(safeBranch).md")
    }

    /// Replace any character that isn't alphanumeric / underscore / dash /
    /// dot with `_`. Caps length at 64 to avoid pathological filenames.
    static func sanitizeBranchName(_ raw: String) -> String {
        let cleaned = raw.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" || scalar == "." {
                return Character(scalar)
            }
            return "_"
        }
        let s = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if s.isEmpty { return "main" }
        return String(s.prefix(64))
    }

    /// Migrate the legacy `codex/memory.md` file into the new `memory/user.md`
    /// location, no-op if the source is missing or the destination already
    /// exists. Called lazily from `readUserMemory` and `readMemoryForInjection`.
    static func migrateLegacyMemoryIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyUserMemoryURL.path),
              !fm.fileExists(atPath: userMemoryURL.path) else { return }
        try? fm.createDirectory(at: memoryDirectory, withIntermediateDirectories: true)
        try? fm.moveItem(at: legacyUserMemoryURL, to: userMemoryURL)
    }

    // MARK: - Memory read / write switches (Codex-style independent gates).

    /// Master switch: when OFF, no extraction happens AND no injection happens.
    /// Defaults to ON. Preserved for compatibility with the existing Settings
    /// toggle; the more granular `memoryReadEnabled` / `memoryWriteEnabled`
    /// give the same effect when both are set.
    static let memoryEnabledKey = "tapgo.memoryEnabled"
    static var memoryEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: memoryEnabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: memoryEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: memoryEnabledKey)
        }
    }

    /// Independent read gate (Codex's `use_memories`). When OFF, the app still
    /// writes new bullets but stops injecting memory into `baseInstructions`.
    static let memoryReadEnabledKey = "tapgo.memory.read"
    static var memoryReadEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: memoryReadEnabledKey) == nil { return memoryEnabled }
            return UserDefaults.standard.bool(forKey: memoryReadEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: memoryReadEnabledKey) }
    }

    /// Independent write gate (Codex's `generate_memories`). When OFF, no new
    /// bullets are persisted but the model still sees the existing memory.
    static let memoryWriteEnabledKey = "tapgo.memory.write"
    static var memoryWriteEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: memoryWriteEnabledKey) == nil { return memoryEnabled }
            return UserDefaults.standard.bool(forKey: memoryWriteEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: memoryWriteEnabledKey) }
    }

    // MARK: - Read paths.

    /// Read the user-tier memory (legacy-compatible). Returns sanitized markdown.
    static func readUserMemory() -> String? {
        migrateLegacyMemoryIfNeeded()
        guard let data = try? Data(contentsOf: userMemoryURL) else { return nil }
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        return DurableMemory.sanitizedMarkdown(from: raw)
    }

    /// Build the `baseInstructions` summary across all visible layers, honoring
    /// `memoryReadEnabled`. Only the summary is injected (Codex-style
    /// progressive disclosure); the full MEMORY.md and KEY files stay on disk
    /// and the model is told it may `grep` them on demand via the injected
    /// `grepMemory` tool-call hint.
    static func readMemoryForInjection(projectRoot: URL?, gitBranch: String?) -> String? {
        guard memoryReadEnabled else { return nil }
        migrateLegacyMemoryIfNeeded()
        var sections: [String] = []
        if let user = readLayer(userMemoryURL) { sections.append(user) }
        if let global = readLayer(globalMemoryURL) { sections.append(global) }
        if let key = readLayer(keyMemoryURL(projectRoot: projectRoot, branch: gitBranch)) {
            sections.append(key)
        }
        guard !sections.isEmpty else { return nil }
        let header = """
        # 长期记忆（摘要层）

        下面是跨会话长期记忆的摘要层（最新 N 条）。需要更早或更细的内容时，使用 grep / cat 工具读取以下文件：
        - 用户层：\(userMemoryURL.path)
        - 全局层：\(globalMemoryURL.path)
        - 项目层（当前分支）：\(keyMemoryURL(projectRoot: projectRoot, branch: gitBranch).path)

        """
        return header + sections.joined(separator: "\n\n")
    }

    private static func readLayer(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        return DurableMemory.summaryForInjection(from: raw)
    }

    // MARK: - Write paths.

    /// Which layer an extracted bullet belongs to. `user` and `global` are
    /// machine-chosen by `MemoryWriter` based on content signals; `key` is
    /// for project-specific facts and gets a per-branch file.
    public enum MemoryScope: String {
        case user
        case global
        case key
    }

    /// Append one bullet to the appropriate layer. Creates parent directories
    /// and enforces the per-file byte cap. Honors `memoryWriteEnabled`.
    @discardableResult
    static func appendMemoryBullet(
        _ text: String,
        scope: MemoryScope,
        projectRoot: URL? = nil,
        gitBranch: String? = nil,
        now: Date = Date()
    ) -> Bool {
        guard memoryWriteEnabled else { return false }
        migrateLegacyMemoryIfNeeded()
        let url: URL
        switch scope {
        case .user:   url = userMemoryURL
        case .global: url = globalMemoryURL
        case .key:    url = keyMemoryURL(projectRoot: projectRoot, branch: gitBranch)
        }
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard let updated = DurableMemory.appendBullet(to: existing, text: text, now: now) else { return false }
        let capped = DurableMemory.enforceByteLimit(updated)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? capped.write(to: url, atomically: true, encoding: .utf8)
        // Mirror to iCloud Drive so other Macs signed into the same Apple ID
        // pick up the new bullet. Fire-and-forget; if iCloud isn't configured
        // locally we just no-op (MemoryCloudSync.isICloudAvailable returns
        // false in that case).
        MemoryCloudSync.push(local: url, relativePath: MemoryCloudSync.relativePath(for: url, memoryDirectory: memoryDirectory))
        return true
    }

    /// Backwards-compatible single-shot append (legacy callers — SessionStore
    /// used this before the scope split). Writes to the **user** layer, which
    /// is the closest semantic match to the old `memory.md` file.
    static func appendMemory(_ note: String) {
        appendMemoryBullet(note, scope: .user)
    }

    // MARK: - iCloud sync wrappers.

    /// Push every memory file (user / global / key-*) currently on disk into
    /// the iCloud Drive mirror. Fire-and-forget; failures are silent.
    static func syncMemoryPushAll() {
        let memDir = memoryDirectory
        // USER + GLOBAL layers.
        for url in [userMemoryURL, globalMemoryURL] {
            MemoryCloudSync.push(
                local: url,
                relativePath: MemoryCloudSync.relativePath(for: url, memoryDirectory: memDir)
            )
        }
        // KEY layer: scan `keys/` and push any per-branch files we find.
        let keysDir = memDir.appendingPathComponent("keys", isDirectory: true)
        if let entries = try? FileManager.default.contentsOfDirectory(at: keysDir, includingPropertiesForKeys: nil) {
            for url in entries where url.pathExtension == "md" {
                MemoryCloudSync.push(
                    local: url,
                    relativePath: MemoryCloudSync.relativePath(for: url, memoryDirectory: memDir)
                )
            }
        }
    }

    /// Pull every memory file that the iCloud mirror holds and whose mtime
    /// is newer than the local copy. Call on App startup so the user sees
    /// memories written on their other Macs.
    static func syncMemoryPullAll() {
        let memDir = memoryDirectory
        guard let mirror = MemoryCloudSync.iCloudMirrorURL else { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: mirror, includingPropertiesForKeys: nil) else { return }
        for remote in entries where remote.pathExtension == "md" {
            let rel = MemoryCloudSync.relativePath(for: remote, memoryDirectory: memDir)
            let local = MemoryCloudSync.localURL(forRemoteRelativePath: rel, memoryDirectory: memDir)
            _ = MemoryCloudSync.pull(remoteRelativePath: rel, into: local)
        }
    }


    /// Codex-compatible approval policy. Mirrors the current app-server
    /// values (`never`, `on-request`, `untrusted`). Persisted so
    /// the user can toggle interactive approvals from Settings; the app
    /// ships defaulting to `never` to keep the auto-approve behavior.
    enum ApprovalPolicy: String, CaseIterable, Identifiable {
        case never
        case onRequest = "on-request"
        case untrusted
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .never:      return "永不询问 (自动批准)"
            case .onRequest:  return "询问 (每次请求)"
            case .untrusted:  return "仅不受信任操作询问"
            }
        }
        var shortName: String {
            switch self {
            case .never:      return "永不"
            case .onRequest:  return "询问"
            case .untrusted:  return "风险问"
            }
        }
    }

    /// Codex-compatible sandbox mode. `danger-full-access` is the local
    /// default (no filesystem sandbox — all commands permitted).
    enum SandboxMode: String, CaseIterable, Identifiable {
        case readOnly = "read-only"
        case workspaceWrite = "workspace-write"
        case dangerFullAccess = "danger-full-access"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .readOnly:          return "只读"
            case .workspaceWrite:    return "工作区可写"
            case .dangerFullAccess:  return "完全访问 (不限制)"
            }
        }
        var shortName: String {
            switch self {
            case .readOnly:          return "只读"
            case .workspaceWrite:    return "工作区"
            case .dangerFullAccess:  return "完全访问"
            }
        }
    }

    private enum Keys {
        static let approvalPolicy = "tapgo.approvalPolicy"
        static let sandbox = "tapgo.sandboxMode"
        static let computerUseEnabled = "tapgo.computerUse.enabled"
        static let computerUseShowInComposer = "tapgo.computerUse.showInComposer"
    }

    /// Public keys so `SettingsView` can bind via `@AppStorage` and stay
    /// in sync with the persisted enum values above.
    static let approvalPolicyKey = Keys.approvalPolicy
    static let sandboxKey = Keys.sandbox
    static let computerUseEnabledKey = Keys.computerUseEnabled
    static let computerUseShowInComposerKey = Keys.computerUseShowInComposer

    /// Existing installations already had the bundled MCP registered before
    /// switches existed, so an absent preference intentionally means enabled.
    static var computerUseEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Keys.computerUseEnabled) != nil else { return true }
        return defaults.bool(forKey: Keys.computerUseEnabled)
    }

    /// The composer shortcut is independent from capability enablement. This
    /// mirrors ZCode: users may keep a visible grey shortcut while disabled so
    /// they always have a direct path back to the setting.
    static var computerUseShowInComposer: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Keys.computerUseShowInComposer) != nil else { return true }
        return defaults.bool(forKey: Keys.computerUseShowInComposer)
    }

    static var approvalPolicy: ApprovalPolicy {
        get {
            let raw = UserDefaults.standard.string(forKey: Keys.approvalPolicy) ?? ""
            // Codex 0.149+ removed `on-failure`; migrate the legacy intent to
            // the closest current policy instead of silently auto-approving.
            if raw == "on-failure" { return .untrusted }
            return ApprovalPolicy(rawValue: raw) ?? .never
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.approvalPolicy) }
    }

    static func migratePersistedSettings() {
        if UserDefaults.standard.string(forKey: Keys.approvalPolicy) == "on-failure" {
            UserDefaults.standard.set(ApprovalPolicy.untrusted.rawValue, forKey: Keys.approvalPolicy)
        }
        let effort = UserDefaults.standard.string(forKey: reasoningEffortKey) ?? ""
        if !effort.isEmpty && Self.supportedReasoningEfforts.first(where: { $0 == effort }) == nil {
            UserDefaults.standard.removeObject(forKey: reasoningEffortKey)
        }
    }

    /// v0.5.52 起思考强度固定 5 档；空串表示「模型定」，其它值经 setter
    /// 写入时按 `supportedReasoningEfforts` 过滤。
    static let supportedReasoningEfforts: [String] = ["", "none", "low", "medium", "high"]
    static let defaultReasoningEffort: String = ""

    static var sandboxMode: SandboxMode {
        get { SandboxMode(rawValue: UserDefaults.standard.string(forKey: Keys.sandbox) ?? "") ?? .dangerFullAccess }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.sandbox) }
    }

    /// Optional override for the model-provider base URL. When set, it
    /// wins over `defaultRegion.baseURL` and is re-written into
    /// `config.toml` so the next harness run hits a different endpoint
    /// (e.g. a proxy or the global MiniMax API).
    private static let baseURLKey = "tapgo.baseURL"

    static var baseURLOverride: String? {
        get { UserDefaults.standard.string(forKey: baseURLKey) }
        set { UserDefaults.standard.set(newValue, forKey: baseURLKey) }
    }

    static var effectiveBaseURL: String {
        let o = baseURLOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let o, !o.isEmpty { return o }
        return defaultRegion.baseURL
    }

    /// Public key so `SettingsView` can bind via `@AppStorage`.
    static let reasoningEffortKey = "tapgo.reasoningEffort"
    static let appearanceKey = "tapgo.appearance"

    /// Appearance override: "system" (nil), "light", or "dark". Used to
    /// pin the dynamic DSH palette.
    static var appearance: String? {
        get {
            let v = UserDefaults.standard.string(forKey: appearanceKey) ?? "system"
            return v == "system" ? nil : v
        }
        set {
            UserDefaults.standard.set(newValue ?? "system", forKey: appearanceKey)
        }
    }

    /// Optional reasoning-effort string sent as `effort` to `turn/start`.
    /// Empty/nil = don't send (keep the model's server default). Options
    /// mirror the picker in 设置 → 模型 (v0.5.52 起固定 5 档)。
    static var reasoningEffort: String? {
        get {
            let v = UserDefaults.standard.string(forKey: reasoningEffortKey) ?? ""
            return supportedReasoningEfforts.contains(v) && !v.isEmpty ? v : nil
        }
        set {
            let v = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let supported = supportedReasoningEfforts.contains(v) ? v : ""
            UserDefaults.standard.set(supported.isEmpty ? nil : supported, forKey: reasoningEffortKey)
        }
    }

    /// Set (or clear, with nil/empty) the endpoint override and rewrite
    /// `config.toml` so it takes effect on the next harness run.
    static func applyBaseURL(_ url: String?) throws {
        let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        baseURLOverride = trimmed.isEmpty ? nil : trimmed
        let config = renderConfig(region: defaultRegion)
        try atomicWrite(Data(config.utf8), to: configPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configPath.path)
        log("Applied base URL: \(effectiveBaseURL)")
    }

    // MARK: - 模型切换 (v0.5.31; v0.5.42 起支持自定义模型增删改查)

    /// 解析后的可执行模型描述：thread/start 与 UI 都以它为准。
    struct ResolvedModel: Identifiable, Equatable {
        let id: String            // "builtin:<slug>" 或自定义 "custom-XXXXXXXX"
        let displayName: String
        let apiModel: String      // 发给上游 API 的模型 ID
        let providerId: String    // config.toml [model_providers.<id>] 段名
        let baseURL: String
        let contextWindow: Int
        let builtIn: TapgoModel?  // 内置模型非空；自定义模型 nil
    }

    /// Web Remote 只需要展示与选择模型，不得把端点或 API Key 暴露给浏览器。
    struct SelectableModelOption: Equatable {
        let providerID: String
        let providerName: String
        let modelID: String
        let modelName: String
        let configured: Bool
        let selected: Bool
    }

    /// 自定义模型注册表文件（0600）。
    static var modelRegistryFileURL: URL {
        codexHome.appendingPathComponent("model-registry.json")
    }

    static func modelRegistry() -> ModelRegistry {
        ModelRegistry(fileURL: modelRegistryFileURL)
    }

    /// Provider 注册表文件（v0.5.53 起替代分散的 auth*.json + model-registry.json）。
    /// 单测里可注入替代路径；生产路径由 codexHome 决定。
    static var providerRegistryFileURL: URL {
        codexHome.appendingPathComponent("provider-registry.json")
    }

    /// Provider 注册表单例路径：每次构造新实例但路径稳定。
    /// 注入式单测传 `providerRegistryFileURL` 覆盖。
    static func providerRegistry() -> ProviderRegistry {
        ProviderRegistry(
            fileURL: providerRegistryFileURL,
            legacyModelRegistryURL: modelRegistryFileURL,
            legacyAuthPaths: [authPath, glmAuthPath, deepSeekAuthPath]
        )
    }

    /// 所有 Provider（v0.5.53 起）。同时触发首次启动的 v0.5.52 迁移。
    static func allProviders() -> [Provider] {
        let registry = providerRegistry()
        registry.migrateFromLegacyIfNeeded()
        registry.ensureBuiltinProviders()
        return registry.providers
    }

    /// 当前选中的 Provider；选中态为空时返回第一个内置。
    static func resolveSelectedProvider() -> Provider {
        let registry = providerRegistry()
        _ = registry.migrateFromLegacyIfNeeded()
        registry.ensureBuiltinProviders()
        return registry.resolveSelectedProvider()
    }

    /// v0.5.54：ProviderRegistry 已接管凭据后，启动校验、Harness 与配置
    /// 重写都从这里取 Key。旧 auth*.json 只作为尚未迁移机器的兼容回退。
    static func providerAPIKey(_ kind: TapgoProviderKind) -> String {
        let registry = providerRegistry()
        _ = registry.migrateFromLegacyIfNeeded()
        registry.ensureBuiltinProviders()
        if let key = registry.provider(id: kind.registryID)?.apiKey, !key.isEmpty {
            return key
        }
        switch kind {
        case .zhipu: return glmAuthKey()
        case .minimax:
            return ModelSettingsProbe.readAPIKey(at: authPath)
        case .deepseek: return deepSeekAuthKey()
        }
    }

    static func selectedProviderAPIKey() -> String {
        let registry = providerRegistry()
        _ = registry.migrateFromLegacyIfNeeded()
        registry.ensureBuiltinProviders()
        let selected = registry.resolveSelectedProvider()
        if !selected.apiKey.isEmpty { return selected.apiKey }
        return registry.providers.first(where: { !$0.apiKey.isEmpty })?.apiKey ?? ""
    }

    /// 全部可选模型：内置 4 个 + 用户自定义，内置在前。
    static func allModels() -> [ResolvedModel] {
        var out: [ResolvedModel] = TapgoModel.allCases.map { m in
            ResolvedModel(
                id: "builtin:\(m.rawValue)",
                displayName: m.displayName,
                apiModel: m.rawValue,
                providerId: m.providerId,
                baseURL: effectiveBaseURL(for: m),
                contextWindow: m.contextWindow,
                builtIn: m
            )
        }
        let registry = modelRegistry()
        out.append(contentsOf: registry.customModels.map { c in
            ResolvedModel(
                id: c.id,
                displayName: c.displayName,
                apiModel: c.apiModel,
                providerId: c.providerId,
                baseURL: c.baseURL,
                contextWindow: c.contextWindow,
                builtIn: nil
            )
        })
        return out
    }

    /// 当前选中的模型。v0.5.54 起 ProviderRegistry 是唯一真相源；
    /// `tapgo.model` 仅保留给旧版偏好与 composer 的兼容显示。
    static func resolveSelected() -> ResolvedModel {
        let registry = providerRegistry()
        _ = registry.migrateFromLegacyIfNeeded()
        registry.ensureBuiltinProviders()
        let provider = registry.resolveSelectedProvider()
        let model = registry.resolveSelectedModel(for: provider)
        if !model.apiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ResolvedModel(
                id: model.id,
                displayName: "\(provider.displayName) \(model.displayName)",
                apiModel: model.apiModel,
                providerId: configProviderID(for: provider),
                baseURL: provider.baseURL,
                contextWindow: model.contextWindow,
                builtIn: TapgoModel(rawValue: model.apiModel)
            )
        }

        // 极旧或损坏注册表的兼容回退。
        let raw = UserDefaults.standard.string(forKey: selectedModelKey) ?? ""
        let id = ModelRegistry.normalizedID(raw)
        let models = allModels()
        if let hit = models.first(where: { $0.id == id }) { return hit }
        return models[0]
    }

    /// ProviderRegistry 是桌面模型设置页与 Web Remote 的共同真相源。
    /// 返回值刻意不包含 baseURL / apiKey，避免凭据进入手机端状态快照。
    static func selectableModelOptions() -> [SelectableModelOption] {
        let registry = providerRegistry()
        _ = registry.migrateFromLegacyIfNeeded()
        registry.ensureBuiltinProviders()
        let selectedProvider = registry.resolveSelectedProvider()
        let selectedModel = registry.resolveSelectedModel(for: selectedProvider)
        return registry.providers.flatMap { provider in
            let configured: Bool
            if let kind = provider.builtInKind {
                configured = !providerAPIKey(kind).isEmpty
            } else {
                configured = !provider.apiKey.isEmpty
            }
            return provider.models.map { model in
                SelectableModelOption(
                    providerID: provider.id,
                    providerName: provider.displayName,
                    modelID: model.id,
                    modelName: model.displayName,
                    configured: configured,
                    selected: provider.id == selectedProvider.id && model.id == selectedModel.id
                )
            }
        }
    }

    /// 与 ModelSettingsView 使用同一套 ProviderRegistry 选择语义。仅接受当前
    /// 注册表中确实存在的 provider/model 组合，拒绝浏览器注入任意模型 ID。
    @discardableResult
    static func selectProviderModel(providerID: String, modelID: String) -> Bool {
        let registry = providerRegistry()
        _ = registry.migrateFromLegacyIfNeeded()
        registry.ensureBuiltinProviders()
        guard let provider = registry.provider(id: providerID),
              let model = provider.models.first(where: { $0.id == modelID })
        else { return false }
        let configured = provider.builtInKind.map { !providerAPIKey($0).isEmpty }
            ?? !provider.apiKey.isEmpty
        guard configured else { return false }

        registry.setSelectedProvider(id: provider.id)
        registry.setSelectedModel(model, for: provider)
        let legacyID = provider.isBuiltin ? "builtin:\(model.apiModel)" : provider.id
        UserDefaults.standard.set(legacyID, forKey: selectedModelKey)
        modelRegistry().setSelected(legacyID)
        syncProviderFiles()
        return true
    }

    /// ProviderRegistry ID 到 Codex config.toml provider 段名的稳定映射。
    private static func configProviderID(for provider: Provider) -> String {
        switch provider.builtInKind {
        case .zhipu: return TapgoModel.glm53Flash.providerId
        case .minimax: return TapgoModel.minimaxM3.providerId
        case .deepseek: return TapgoModel.deepSeekV4Flash.providerId
        case nil: return provider.id
        }
    }

    /// 选择模型：写 UserDefaults + 注册表，并重写 config.toml / 目录，
    /// 让 harness 热加载到（可能刚新增的）provider。
    static func setSelectedModel(id: String) {
        let normalized = ModelRegistry.normalizedID(id)
        let models = allModels()
        let selected = models.first(where: { $0.id == normalized }) ?? models[0]
        UserDefaults.standard.set(selected.id, forKey: selectedModelKey)
        let legacyRegistry = modelRegistry()
        legacyRegistry.setSelected(selected.id)

        // composer 仍会传 v0.5.52 的 builtin:<slug>；同步映射到新的
        // ProviderRegistry，避免界面显示已切换而 thread/start 仍沿用旧供应商。
        let registry = providerRegistry()
        _ = registry.migrateFromLegacyIfNeeded()
        registry.ensureBuiltinProviders()
        if let providerAndModel = registry.providers.lazy.compactMap({ provider -> (Provider, ProviderModel)? in
            guard let model = provider.models.first(where: {
                $0.id == normalized || $0.apiModel == selected.apiModel
            }) else { return nil }
            return (provider, model)
        }).first {
            registry.setSelectedProvider(id: providerAndModel.0.id)
            registry.setSelectedModel(providerAndModel.1, for: providerAndModel.0)
        }
        syncModelConfigFiles()
    }

    /// 当前选中态是否引用了某个自定义模型 id（v0.5.52 起，删除路径
    /// 用此判断是否需要主动写回 `builtin:MiniMax-M3`，避免隐式回落）。
    static func isSelectedCustomModel(id: String) -> Bool {
        let raw = UserDefaults.standard.string(forKey: selectedModelKey) ?? ""
        return ModelRegistry.normalizedID(raw) == id
    }

    /// 删除自定义模型。删除前若选中态指向该模型，主动写回
    /// `builtin:MiniMax-M3` 并重写 config.toml / 目录，避免旧 ID
    /// 残留在 UserDefaults 后被 `resolveSelected` 隐式回落（v0.5.52）。
    /// 返回「是否真的删除了该自定义模型」，上层据此决定是否 toast 提示。
    @discardableResult
    static func deleteCustomModel(id: String) -> Bool {
        let removed = ModelSettingsProbe.deleteCustomModel(
            id: id,
            registry: modelRegistry(),
            selectedModelKey: selectedModelKey,
            fallbackSelectedID: "builtin:\(TapgoModel.minimaxM3.rawValue)"
        )
        syncModelConfigFiles()
        return removed
    }

    /// 清除内置模型的凭据文件（0600）。下次启动未重写时，harness 会拿到
    /// 空 bearer 并返回 401。新会话将无法使用该内置模型，直到重新填 Key。
    /// 自定义模型 Key 与定义一起存在 `model-registry.json`，由
    /// `CustomModel` 自身管理，不走此 API。
    static func clearAPIKey(for model: TapgoModel) {
        let path: URL
        switch model {
        case .minimaxM3: path = authPath
        case .glm53Flash: path = glmAuthPath
        case .deepSeekV4Flash, .deepSeekV4Pro: path = deepSeekAuthPath
        }
        try? FileManager.default.removeItem(at: path)
        syncModelConfigFiles()
    }

    /// 探测任意模型（含自定义）的端点连通性（v0.5.52）。
    /// 内部走 `ModelSettingsProbe.testConnection`，注入 baseURL + Key。
    static func testConnection(
        for row: ResolvedModel,
        completion: @escaping (Result<UInt, Error>) -> Void
    ) {
        let key: String?
        if let builtIn = row.builtIn {
            switch builtIn {
            case .minimaxM3: key = ModelSettingsProbe.readAPIKey(at: authPath)
            case .glm53Flash: key = ModelSettingsProbe.readAPIKey(at: glmAuthPath)
            case .deepSeekV4Flash, .deepSeekV4Pro: key = ModelSettingsProbe.readAPIKey(at: deepSeekAuthPath)
            }
        } else {
            key = TapgoConfig.modelRegistry().customModel(id: row.id)?.apiKey
        }
        ModelSettingsProbe.testConnection(
            baseURL: row.baseURL,
            apiKey: key,
            completion: completion
        )
    }

    // MARK: - v0.5.53 Provider-aware API（仿造 ZCode）

    /// 清除指定 Provider 的 Key（v0.5.53 起）。内置 / 自定义 Provider 都用这个
    /// API；旧 `clearAPIKey(for: TapgoModel)` 保留供 ChatView 等旧路径用。
    /// 内部委托给 ProviderRegistry.setAPIKey，并触发 syncModelConfigFiles
    /// 让 config.toml 重写。
    static func clearAPIKey(providerID: String) {
        let registry = providerRegistry()
        registry.migrateFromLegacyIfNeeded()
        registry.setAPIKey("", for: providerID)
        syncModelConfigFiles()
    }

    /// 探测某个 Provider 下某个 Model 的端点连通性（v0.5.53 起）。
    static func testConnection(
        provider: Provider,
        model: ProviderModel,
        completion: @escaping (Result<UInt, Error>) -> Void
    ) {
        ModelSettingsProbe.testConnection(
            baseURL: provider.baseURL,
            apiKey: provider.apiKey,
            completion: completion
        )
    }

    /// 触发 Provider 注册表同步到 harness config.toml / catalog（v0.5.53）。
    /// 旧 `syncModelConfigFiles` 路径完整保留，本函数只是它的别名 + 触发
    /// 迁移；新代码优先用本函数。
    static func syncProviderFiles() {
        let registry = providerRegistry()
        registry.migrateFromLegacyIfNeeded()
        syncModelConfigFiles()
    }

    /// 增删改自定义模型 / 切换选择后调用：按最新注册表重写
    /// config.toml（含自定义 provider 段与 bearer）与模型目录。
    /// harness 实测支持热加载 provider（无需重启）。
    static func syncModelConfigFiles() {
        let config = renderedConfigWithKey(
            region: defaultRegion,
            authKey: providerAPIKey(.minimax),
            glmKey: providerAPIKey(.zhipu),
            deepSeekKey: providerAPIKey(.deepseek)
        )
        try? atomicWrite(Data(config.utf8), to: configPath)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configPath.path)
        try? writeDefaultCatalog(region: defaultRegion)
        syncComputerUseMCPPreference()
        log("syncModelConfigFiles: config.toml + catalog 已按模型注册表重写")
    }

    /// 当前选中的模型（composer 弹窗切换）。只影响**新会话**——进行中的
    /// 会话沿用创建时的模型；记忆整理与额度查询等后台任务固定 MiniMax。
    static let selectedModelKey = "tapgo.model"

    static var selectedModel: TapgoModel {
        get {
            let id = ModelRegistry.normalizedID(
                UserDefaults.standard.string(forKey: selectedModelKey) ?? ""
            )
            let slug = id.hasPrefix("builtin:") ? String(id.dropFirst("builtin:".count)) : id
            return TapgoModel(rawValue: slug)
                ?? .minimaxM3
        }
        set { UserDefaults.standard.set("builtin:\(newValue.rawValue)", forKey: selectedModelKey) }
    }

    /// 选中模型的实际端点：MiniMax 尊重用户在运行设置里的覆盖，GLM 固定。
    static func effectiveBaseURL(for model: TapgoModel) -> String {
        switch model {
        case .minimaxM3: return effectiveBaseURL
        case .glm53Flash, .deepSeekV4Flash, .deepSeekV4Pro: return model.defaultBaseURL
        }
    }

    /// GLM（BigModel Coding Plan）的独立鉴权文件，与 auth.json 同设计
    /// （0600，`{"OPENAI_API_KEY": "<key>"}`）。`renderConfig` 会把其中
    /// 的 key 注入 `[model_providers.glm]` 的 bearer。文件缺失时注入
    /// 空串而不是占位符——占位符没有任何运行时替换机制（v0.5.28 的
    /// 教训），选 GLM 的新会话会直接收到 401，错误清晰可定位。
    static var glmAuthPath: URL { codexHome.appendingPathComponent("auth-glm.json") }

    static func glmAuthKey() -> String {
        guard let data = try? Data(contentsOf: glmAuthPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["OPENAI_API_KEY"] as? String
        else { return "" }
        return key
    }

    /// DeepSeek（按量计费）的独立鉴权文件，与 auth-glm.json 同设计
    /// （0600，`{"OPENAI_API_KEY": "<key>"}`）。文件缺失时 bearer 为空，
    /// 选 DeepSeek 的新会话会收到 401。
    static var deepSeekAuthPath: URL { codexHome.appendingPathComponent("auth-deepseek.json") }

    static func deepSeekAuthKey() -> String {
        guard let data = try? Data(contentsOf: deepSeekAuthPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["OPENAI_API_KEY"] as? String
        else { return "" }
        return key
    }

    /// Root of the isolated Codex home.
    static var codexHome: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Tapgo AICoding/codex", isDirectory: true)
    }

    static var configPath: URL { codexHome.appendingPathComponent("config.toml") }
    static var authPath: URL { codexHome.appendingPathComponent("auth.json") }
    static var modelCatalogPath: URL {
        codexHome.appendingPathComponent("model-catalogs/tapgo-catalog.json", isDirectory: false)
    }

    // MARK: 电脑控制 MCP 注册 (v0.5.20)

    private static var computerUseHelperInstallRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Tapgo AICoding", isDirectory: true)
            .appendingPathComponent(ComputerUseMCP.helperInstallDirectoryName, isDirectory: true)
    }

    private static let computerUseHelperInstallLock = NSLock()

    private static func bundledComputerUseHelperAppURL(bundle: Bundle) -> URL? {
        guard let resources = bundle.resourceURL else { return nil }
        let helper = resources
            .appendingPathComponent(ComputerUseMCP.helperDirectoryName, isDirectory: true)
            .appendingPathComponent(ComputerUseMCP.helperAppName, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: helper.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return helper
    }

    /// Install the bundled helper at an owner-controlled, stable standalone
    /// path before registering, probing, or dragging it. macOS privacy lists
    /// expect a real application item; ZCode follows the same pattern instead
    /// of dragging the nested bundle directly from its parent's Resources.
    static func computerUseHelperAppURL(bundle: Bundle = .main) -> URL? {
        computerUseHelperInstallLock.lock()
        defer { computerUseHelperInstallLock.unlock() }
        guard let bundled = bundledComputerUseHelperAppURL(bundle: bundle) else { return nil }
        let fm = FileManager.default
        let target = computerUseHelperInstallRoot
            .appendingPathComponent(ComputerUseMCP.helperAppName, isDirectory: true)
        let bundledExecutable = bundled
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(ComputerUseMCP.helperExecutableName)
        let targetExecutable = target
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(ComputerUseMCP.helperExecutableName)
        let bundledInfo = bundled.appendingPathComponent("Contents/Info.plist")
        let targetInfo = target.appendingPathComponent("Contents/Info.plist")

        if fm.fileExists(atPath: target.path),
           fm.contentsEqual(atPath: bundledExecutable.path, andPath: targetExecutable.path),
           fm.contentsEqual(atPath: bundledInfo.path, andPath: targetInfo.path) {
            return target
        }

        do {
            try fm.createDirectory(
                at: computerUseHelperInstallRoot,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let staging = computerUseHelperInstallRoot
                .appendingPathComponent(".Tapgo Computer Use-\(UUID().uuidString).app", isDirectory: true)
            defer { try? fm.removeItem(at: staging) }
            try fm.copyItem(at: bundled, to: staging)
            if fm.fileExists(atPath: target.path) {
                _ = try fm.replaceItemAt(target, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: target)
            }
            return target
        } catch {
            log("computerUseHelperAppURL: 独立 Helper 安装失败：\(error.localizedDescription)")
            return nil
        }
    }

    static func computerUseMCPBinaryURL(bundle: Bundle = .main) -> URL? {
        if let helperApp = computerUseHelperAppURL(bundle: bundle) {
            let helperExecutable = URL(fileURLWithPath: ComputerUseMCP.helperExecutablePath(
                helperAppPath: helperApp.path
            ))
            if FileManager.default.isExecutableFile(atPath: helperExecutable.path) {
                return helperExecutable
            }
        }
        guard let exe = bundle.executableURL else { return nil }
        let sibling = exe.deletingLastPathComponent()
            .appendingPathComponent(ComputerUseMCP.helperExecutableName)
        return FileManager.default.isExecutableFile(atPath: sibling.path) ? sibling : nil
    }

    static func computerUseMCPBinaryPath(bundle: Bundle = .main) -> String? {
        computerUseMCPBinaryURL(bundle: bundle)?.path
    }

    /// 把 `[mcp_servers.tapgo_computer_use]` 幂等写入隔离 Codex home 的
    /// config.toml, 让模型获得电脑控制工具。二进制不存在 (尚未随包部署)
    /// 时不动配置, 返回 false。App 每次启动调用一次, harness 下次拉起生效。
    @discardableResult
    static func ensureComputerUseMCPSection(binaryPath: String? = nil) -> Bool {
        let resolved = binaryPath ?? computerUseMCPBinaryPath()
        guard let mcpBinary = resolved else {
            log("ensureComputerUseMCPSection: 未找到 TapgoComputerUseMCP 二进制, 跳过注册")
            return false
        }
        let fm = FileManager.default
        guard let current = try? String(contentsOf: configPath, encoding: .utf8) else {
            log("ensureComputerUseMCPSection: config.toml 不存在 (尚未完成初始化), 跳过注册")
            return false
        }
        let updated = ComputerUseMCP.upsertSection(inConfig: current, commandPath: mcpBinary)
        guard updated != current else { return true }
        do {
            try atomicWrite(Data(updated.utf8), to: configPath)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configPath.path)
            log("ensureComputerUseMCPSection: 已注册电脑控制 MCP server → \(mcpBinary)")
            return true
        } catch {
            log("ensureComputerUseMCPSection: 写入 config.toml 失败 \(error)")
            return false
        }
    }

    /// Remove the bundled computer-control MCP table from the isolated Codex
    /// config. Existing harness processes may retain already-loaded tools;
    /// new sessions/harnesses use the updated state.
    @discardableResult
    static func removeComputerUseMCPSection() -> Bool {
        let fm = FileManager.default
        guard let current = try? String(contentsOf: configPath, encoding: .utf8) else {
            log("removeComputerUseMCPSection: config.toml 不存在，无需移除")
            return true
        }
        let updated = ComputerUseMCP.removeSection(fromConfig: current)
        guard updated != current else { return true }
        do {
            try atomicWrite(Data(updated.utf8), to: configPath)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configPath.path)
            log("removeComputerUseMCPSection: 已停用电脑控制 MCP server")
            return true
        } catch {
            log("removeComputerUseMCPSection: 写入 config.toml 失败 \(error)")
            return false
        }
    }

    /// Apply the persisted master switch to the real MCP config. Enabling
    /// upserts the bundled executable; disabling removes the server table.
    @discardableResult
    static func syncComputerUseMCPPreference() -> Bool {
        computerUseEnabled
            ? ensureComputerUseMCPSection()
            : removeComputerUseMCPSection()
    }

    /// Logs land next to the system-wide Logs directory so the user can
    /// `tail -f` from Terminal.
    static var logFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Tapgo AICoding/harness.log", isDirectory: false)
    }

    /// Make sure the on-disk layout exists and is valid. If anything is
    /// missing or stale (e.g. no `auth.json`, or the catalog doesn't list
    /// `MiniMax-M3`), throw a `SetupError` that the UI can render as a
    /// setup screen.
    static func ensureReady() throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: codexHome,
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: codexHome.appendingPathComponent("model-catalogs"),
            withIntermediateDirectories: true
        )

        // v0.5.53 已把 auth*.json 迁入 provider-registry.json；继续死查旧
        // auth.json 会让迁移成功的用户反而落回初始化拦截页。
        let key = selectedProviderAPIKey()
        guard !key.isEmpty else {
            throw SetupError.missingAuth(providerRegistryFileURL.path)
        }

        // config.toml must mention MiniMax-M3 + the minimax provider.
        if !fm.fileExists(atPath: configPath.path) {
            throw SetupError.missingConfig(configPath.path)
        }
        let config = (try? String(contentsOf: configPath, encoding: .utf8)) ?? ""
        if !config.contains("MiniMax-M3") || !config.contains("[model_providers.minimax]") {
            throw SetupError.missingConfig(configPath.path)
        }

        let harnessPath = RemoteCodexHomeSync.findHarness()
        guard !harnessPath.isEmpty else {
            throw SetupError.harnessNotFound
        }
        guard RemoteCodexHomeSync.supportedHarnessVersion(at: harnessPath) != nil else {
            throw SetupError.harnessVersionUnsupported(harnessPath)
        }

        // Refresh the app-owned catalog whenever its generated policy changes.
        // Merely checking that the file exists left upgraded installations on
        // stale base instructions indefinitely.
        let desiredCatalog = renderCatalog()
        let installedCatalog = (try? String(contentsOf: modelCatalogPath, encoding: .utf8)) ?? ""
        if installedCatalog != desiredCatalog {
            try writeDefaultCatalog(region: defaultRegion)
        }

        // 同样地同步 config.toml: 老版本写出的 config.toml 可能漏掉
        // `model_auto_compact_token_limit` (v0.3.0 之后才加入模板), 缺了这条
        // harness 就不会在 800k 自动压缩上下文, 用户会话会一路累积到几十 MB
        // (实测 24M tokens 仍不 compact, 弹窗里 contextPercent 显示 2524%)。
        // 这里只 diff 期望内容, 不动 auth.json。注意 bearer 必须注入真实 key:
        // v0.5.27 的重写曾把旧 config 里的真实鉴权覆盖回占位符, MiniMax 返回
        // 401 (1004 login fail) —— 占位符没有任何运行时替换机制。
        let desiredConfig = renderedConfigWithKey(
            region: defaultRegion,
            authKey: providerAPIKey(.minimax),
            glmKey: providerAPIKey(.zhipu),
            deepSeekKey: providerAPIKey(.deepseek)
        )
        let installedConfig = (try? String(contentsOf: configPath, encoding: .utf8)) ?? ""
        if installedConfig != desiredConfig {
            try atomicWrite(Data(desiredConfig.utf8), to: configPath)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configPath.path)
            Self.log("ensureReady: config.toml 漂移, 已用模板重写 (保留 auth.json 不动)")
        }
    }

    /// Writes config.toml + auth.json + model-catalogs/tapgo-catalog.json
    /// atomically, using the provided API key.
    ///
    /// `keySource` is logged so the user can see where the key came from
    /// (e.g. "user-typed", "migrated-from ~/.codex/config.toml.bak").
    /// The key itself is never logged.
    static func initializeFresh(apiKey: String, region: Region, keySource: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: codexHome,
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: codexHome.appendingPathComponent("model-catalogs"),
            withIntermediateDirectories: true
        )

        // 1. auth.json
        let auth: [String: Any] = ["OPENAI_API_KEY": apiKey]
        let authData = try JSONSerialization.data(
            withJSONObject: auth,
            options: [.prettyPrinted, .sortedKeys]
        )
        try atomicWrite(authData, to: authPath)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authPath.path)

        // 2. config.toml — 占位符替换为真实 key (0600 文件, 与官方备份同设计)。
        let config = renderedConfigWithKey(region: region, authKey: apiKey)
        try atomicWrite(Data(config.utf8), to: configPath)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configPath.path)

        // 3. model-catalogs/tapgo-catalog.json
        try writeDefaultCatalog(region: region)

        Self.log("Initialized Tapgo AICoding isolated Codex home at \(codexHome.path) (key source: \(keySource))")
    }

    /// Tries to import the MiniMax-M3 key from
    /// `~/.codex/config.toml.bak.pre-official-restore.20260824-202414`.
    /// If present, extracts the `experimental_bearer_token` and writes
    /// the new independent config. The original backup is **never**
    /// modified.
    ///
    /// Returns the key + a `keySource` string on success, or nil if the
    /// backup isn't there / doesn't have a key.
    static func tryImportFromOfficialBackup() -> (key: String, source: String)? {
        let backup = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml.bak.pre-official-restore.20260824-202414")
        guard let text = try? String(contentsOf: backup, encoding: .utf8) else { return nil }
        // Bare TOML key/value parse — we just want one line.
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("experimental_bearer_token") {
                if let value = parseTomlStringValue(trimmed) {
                    return (value, "migrated-from \(backup.lastPathComponent)")
                }
            }
        }
        return nil
    }

    // MARK: - Templates

    /// 模板渲染 + 占位符注入: config.toml 里 `experimental_bearer_token` 的
    /// `__FROM_AUTH_JSON__` / `__FROM_AUTH_GLM_JSON__` 占位分别替换为
    /// auth.json 与 auth-glm.json 中的真实 key。codex 不会解析占位符,
    /// 缺了它们请求就会 401。
    static func renderedConfigWithKey(
        region: Region,
        authKey: String,
        glmKey: String? = nil,
        deepSeekKey: String? = nil
    ) -> String {
        var config = renderConfig(region: region)
            .replacingOccurrences(
                of: "__FROM_AUTH_GLM_JSON__",
                with: tomlBasicStringContent(glmKey ?? glmAuthKey()))
            .replacingOccurrences(
                of: "__FROM_AUTH_DEEPSEEK_JSON__",
                with: tomlBasicStringContent(deepSeekKey ?? deepSeekAuthKey()))
            .replacingOccurrences(
                of: "__FROM_AUTH_JSON__",
                with: tomlBasicStringContent(authKey))
        // 自定义模型 bearer: 占位符 __CUSTOM_<id>__ 以注册表中的 key 替换。
        // Key 为空也必须替换为空串，不能把占位符本身误当成凭据发给上游。
        let registry = providerRegistry()
        _ = registry.migrateFromLegacyIfNeeded()
        registry.ensureBuiltinProviders()
        for provider in registry.customProviders {
            config = config.replacingOccurrences(
                of: "__CUSTOM_\(provider.id)__",
                with: tomlBasicStringContent(provider.apiKey))
        }
        return config
    }

    static func renderConfig(region: Region) -> String {
        let registry = providerRegistry()
        _ = registry.migrateFromLegacyIfNeeded()
        registry.ensureBuiltinProviders()
        let customSections = registry.customProviders.map { provider -> String in
            """
            [model_providers.\(configProviderID(for: provider))]
            name = "\(tomlBasicStringContent(provider.brand.isEmpty ? "Custom" : provider.brand))"
            base_url = "\(tomlBasicStringContent(provider.baseURL))"
            wire_api = "responses"
            experimental_bearer_token = "__CUSTOM_\(provider.id)__"
            """
        }.joined(separator: "\n\n")
        let customBlock = customSections.isEmpty ? "" : "\n" + customSections + "\n"
        var base = renderConfigBody(region: region)
        // 自定义段插在 [projects.] 之前, 保持内置段顺序稳定。
        if let range = base.range(of: "[projects.") {
            base.insert(contentsOf: customBlock, at: range.lowerBound)
        }
        return base
    }

    private static func renderConfigBody(region: Region) -> String {
        let registry = providerRegistry()
        _ = registry.migrateFromLegacyIfNeeded()
        registry.ensureBuiltinProviders()
        let minimaxBaseURL = registry.provider(id: TapgoProviderKind.minimax.registryID)?.baseURL
            ?? effectiveBaseURL
        let glmBaseURL = registry.provider(id: TapgoProviderKind.zhipu.registryID)?.baseURL
            ?? TapgoModel.glm53Flash.defaultBaseURL
        let deepSeekBaseURL = registry.provider(id: TapgoProviderKind.deepseek.registryID)?.baseURL
            ?? TapgoModel.deepSeekV4Flash.defaultBaseURL
        return """
        # Tapgo AICoding — isolated Codex home.
        # This file is owned by Tapgo AICoding and is independent from ~/.codex/.
        # Do not edit by hand unless you know what you're doing.

        model = "\(modelName)"
        model_provider = "\(modelProvider)"
        model_context_window = 1000000
        model_auto_compact_token_limit = \(autoCompactTokenLimit)
        model_catalog_json = "\(modelCatalogPath.path)"

        [model_providers.\(TapgoModel.minimaxM3.providerId)]
        name = "MiniMax"
        base_url = "\(tomlBasicStringContent(minimaxBaseURL))"
        wire_api = "responses"
        experimental_bearer_token = "__FROM_AUTH_JSON__"

        # v0.5.31: GLM-5.3-Flash (BigModel Coding Plan)。智谱官方给 Codex 的
        # OpenAI Responses 协议专属端点, wire 必须是 responses (harness 0.149+
        # 已移除 chat)。鉴权来自独立的 auth-glm.json; 文件缺失时 bearer 为空,
        # 选 GLM 的新会话会收到 401。
        [model_providers.\(TapgoModel.glm53Flash.providerId)]
        name = "GLM"
        base_url = "\(tomlBasicStringContent(glmBaseURL))"
        wire_api = "responses"
        experimental_bearer_token = "__FROM_AUTH_GLM_JSON__"

        # v0.5.35: DeepSeek V4 系列。API 原生支持 OpenAI Responses 协议
        # (api-docs.deepseek.com/quick_start/agent_integrations/codex),
        # wire 必须 responses。鉴权来自独立的 auth-deepseek.json;
        # 文件缺失时 bearer 为空, 选 DeepSeek 的新会话会收到 401。
        [model_providers.\(TapgoModel.deepSeekV4Flash.providerId)]
        name = "DeepSeek"
        base_url = "\(tomlBasicStringContent(deepSeekBaseURL))"
        wire_api = "responses"
        experimental_bearer_token = "__FROM_AUTH_DEEPSEEK_JSON__"

        # v0.5.42: 用户自定义模型（设置 → 模型 里增删改查）。每个模型
        # 独立 provider 段 + bearer，随注册表 (model-registry.json) 动态生成。

        [projects."/Users/Shared"]
        trust_level = "untrusted"

        [notice]
        # experimental_bearer_token 已由 App 注入真实 key,
        # 本文件与 auth.json / auth-glm.json / auth-deepseek.json 同为 0600 权限, 请勿外传。
        """
    }

    static func renderCatalog() -> String {
        let registry = providerRegistry()
        _ = registry.migrateFromLegacyIfNeeded()
        registry.ensureBuiltinProviders()
        let providerModels = registry.providers.flatMap { provider in
            provider.models.compactMap { model -> CustomModel? in
                if TapgoModel(rawValue: model.apiModel) != nil { return nil }
                return CustomModel(
                    id: model.id,
                    displayName: model.displayName,
                    apiModel: model.apiModel,
                    brand: provider.brand,
                    baseURL: provider.baseURL,
                    apiKey: provider.apiKey,
                    contextWindow: model.contextWindow
                )
            }
        }
        return TapgoModel.catalogJSON(customs: providerModels)
    }

    private static func writeDefaultCatalog(region: Region) throws {
        try atomicWrite(Data(renderCatalog().utf8), to: modelCatalogPath)
    }

    /// TOML basic string（双引号）内部的安全编码。模型字段与 Key 都可能来自
    /// 粘贴输入，必须防止引号、反斜杠或换行破坏 config.toml。
    private static func tomlBasicStringContent(_ value: String) -> String {
        var out = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08: out += "\\b"
            case 0x09: out += "\\t"
            case 0x0A: out += "\\n"
            case 0x0C: out += "\\f"
            case 0x0D: out += "\\r"
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x00...0x1F, 0x7F:
                out += String(format: "\\u%04X", scalar.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    private static func atomicWrite(_ data: Data, to url: URL) throws {
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }

    /// Tiny TOML string-value extractor — handles `"value"` and `'value'`.
    /// Only used for the backup-migration helper, not for parsing our own
    /// generated config (which is what codex actually loads).
    private static func parseTomlStringValue(_ line: String) -> String? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let raw = line[line.index(after: eq)...]
            .trimmingCharacters(in: .whitespaces)
        guard raw.count >= 2 else { return nil }
        let first = raw.first!
        let last = raw.last!
        guard (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return nil
        }
        return String(raw.dropFirst().dropLast())
    }

    static func log(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let dir = logFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? h.close() }
            h.seekToEndOfFile()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }
}

enum SetupError: LocalizedError {
    case missingAuth(String)
    case missingConfig(String)
    case harnessNotFound
    case harnessVersionUnsupported(String)

    var errorDescription: String? {
        switch self {
        case .missingAuth(let path):
            return "缺少独立 auth.json: \(path)。请先运行 scripts/init-tapgo.sh 写入 MiniMax-M3 凭据。"
        case .missingConfig(let path):
            return "缺少独立 config.toml: \(path)。请先运行 scripts/init-tapgo.sh。"
        case .harnessNotFound:
            return "找不到 `codex` CLI。请先通过 Homebrew 安装: brew install --cask codex（需要 0.149.1 或更高）。"
        case .harnessVersionUnsupported(let path):
            return "Codex CLI 版本过旧或无法识别：\(path)。请升级到 \(RemoteCodexHomeSync.minimumHarnessVersion) 或更高。"
        }
    }
}
