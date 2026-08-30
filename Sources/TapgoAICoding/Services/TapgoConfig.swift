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

    /// We pin the model. There is no other model available in this app.
    static let modelName = "MiniMax-M3"
    static let modelProvider = "minimax"
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
    }

    /// Public keys so `SettingsView` can bind via `@AppStorage` and stay
    /// in sync with the persisted enum values above.
    static let approvalPolicyKey = Keys.approvalPolicy
    static let sandboxKey = Keys.sandbox

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
        if effort != "" && effort != "none" && effort != "high" {
            UserDefaults.standard.removeObject(forKey: reasoningEffortKey)
        }
    }

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
    /// mirror the catalog's `supported_reasoning_levels` (`none`, `high`).
    static var reasoningEffort: String? {
        get {
            let v = UserDefaults.standard.string(forKey: reasoningEffortKey) ?? ""
            return v == "none" || v == "high" ? v : nil
        }
        set {
            let v = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let supported = v == "none" || v == "high" ? v : ""
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

    /// 计算随包分发的 `TapgoComputerUseMCP` 二进制路径: 已安装 App 取
    /// `Contents/MacOS/` 同级; `swift run` 开发态取 `.build/<cfg>/` 同级。
    static func computerUseMCPBinaryPath(bundle: Bundle = .main) -> String? {
        guard let exe = bundle.executableURL else { return nil }
        let sibling = exe.deletingLastPathComponent()
            .appendingPathComponent("TapgoComputerUseMCP")
        guard FileManager.default.isExecutableFile(atPath: sibling.path) else { return nil }
        return sibling.path
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

        // auth.json must exist and contain a non-empty OPENAI_API_KEY — that's
        // the bearer codex forwards to MiniMax-M3.
        if !fm.fileExists(atPath: authPath.path) {
            throw SetupError.missingAuth(authPath.path)
        }
        guard let auth = try? Data(contentsOf: authPath),
              let json = try? JSONSerialization.jsonObject(with: auth) as? [String: Any],
              let key = json["OPENAI_API_KEY"] as? String,
              !key.isEmpty
        else {
            throw SetupError.missingAuth(authPath.path)
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
        let desiredConfig = renderedConfigWithKey(region: defaultRegion, authKey: key)
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
    /// `__FROM_AUTH_JSON__` 占位替换为 auth.json 中的真实 key。codex 不会
    /// 解析这个占位符, 缺了它请求就会 401 (1004 login fail)。
    static func renderedConfigWithKey(region: Region, authKey: String) -> String {
        renderConfig(region: region)
            .replacingOccurrences(of: "__FROM_AUTH_JSON__", with: authKey)
    }

    static func renderConfig(region: Region) -> String {
        """
        # Tapgo AICoding — isolated Codex home.
        # This file is owned by Tapgo AICoding and is independent from ~/.codex/.
        # Do not edit by hand unless you know what you're doing.

        model = "\(modelName)"
        model_provider = "\(modelProvider)"
        model_context_window = 1000000
        model_auto_compact_token_limit = \(autoCompactTokenLimit)
        model_catalog_json = "\(modelCatalogPath.path)"

        [model_providers.\(modelProvider)]
        name = "MiniMax"
        base_url = "\(effectiveBaseURL)"
        wire_api = "responses"
        experimental_bearer_token = "__FROM_AUTH_JSON__"

        [projects."/Users/Shared"]
        trust_level = "untrusted"

        [notice]
        # experimental_bearer_token 已由 App 注入 auth.json 中的真实 key,
        # 本文件与 auth.json 同为 0600 权限, 请勿外传。
        """
    }

    static func renderCatalog() -> String {
        """
        {
          "models": [
            {
              "slug": "\(modelName)",
              "display_name": "\(modelName)",
              "description": "Tapgo AICoding 唯一可用模型。",
              "default_reasoning_level": "high",
              "supported_reasoning_levels": [
                { "effort": "none", "description": "Think-Off" },
                { "effort": "high", "description": "Deep" }
              ],
              "shell_type": "shell_command",
              "visibility": "list",
              "supported_in_api": true,
              "priority": 0,
              "base_instructions": "You are Tapgo AICoding, an autonomous coding agent powered by MiniMax-M3. For every actionable request, inspect the current workspace and use the available tools to implement and verify the result. Never claim that tools are unavailable unless a concrete tool call failed in the current turn. Treat persistent memory only as background; the current user request and current workspace evidence always win. \(AgentOutputPolicy.catalogInstructions)",
              "supports_reasoning_summaries": true,
              "default_reasoning_summary": "none",
              "support_verbosity": false,
              "truncation_policy": { "mode": "bytes", "limit": 10000 },
              "supports_parallel_tool_calls": false,
              "experimental_supported_tools": [],
              "input_modalities": ["text", "image"]
            }
          ]
        }
        """
    }

    private static func writeDefaultCatalog(region: Region) throws {
        try atomicWrite(Data(renderCatalog().utf8), to: modelCatalogPath)
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
