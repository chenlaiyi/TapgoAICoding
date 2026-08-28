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
    static let clientInfoVersion = "0.5.1"

    /// Token threshold at which the codex harness auto-compacts the transcript
    /// into a summary (replaces the user having to manually start a new
    /// session). Sits below `model_context_window` so compaction happens
    /// before the model hits the wall.
    // MiniMax-M3 currently exposes a 1M context window. Compact at 80%,
    // matching the pressure-based strategy used by current agent harnesses.
    static let autoCompactTokenLimit = 800_000

    /// User-level persistent memory file, injected as `baseInstructions` into
    /// every new thread so the model "remembers" context across conversations.
    static var userMemoryURL: URL {
        codexHome.deletingLastPathComponent().appendingPathComponent("memory.md")
    }

    static func readUserMemory() -> String? {
        guard let data = try? Data(contentsOf: userMemoryURL) else { return nil }
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        return DurableMemory.sanitizedMarkdown(from: raw)
    }

    /// Cross-conversation memory switch (like Codex's memory). When ON, the
    /// app extracts durable facts from each completed turn into `memory.md`
    /// and injects it as `baseInstructions` into every new thread so the model
    /// "remembers" across conversations. Defaults to ON.
    static let memoryEnabledKey = "tapgo.memoryEnabled"
    static var memoryEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: memoryEnabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: memoryEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: memoryEnabledKey) }
    }

    /// Append memorized bullets to the user-level `memory.md`. Creates the
    /// file on first use and rewrites existing content into canonical form.
    static func appendMemory(_ note: String) {
        let existing = (try? String(contentsOf: userMemoryURL, encoding: .utf8)) ?? ""
        let combined = existing + "\n" + note
        guard let body = DurableMemory.sanitizedMarkdown(from: combined) else { return }
        guard body != existing else { return }
        try? FileManager.default.createDirectory(
            at: userMemoryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? body.write(to: userMemoryURL, atomically: true, encoding: .utf8)
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

        // Catalog must list MiniMax-M3 as the only model.
        if !fm.fileExists(atPath: modelCatalogPath.path) {
            try? writeDefaultCatalog(region: defaultRegion)
            // Recursive call to re-validate.
            try ensureReady()
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

        // 2. config.toml
        let config = renderConfig(region: region)
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
        # The bearer token is supplied at runtime via auth.json so the
        # plaintext secret never lives in this file. If you ever inspect
        # config.toml in version control, you will only see the placeholder
        # above; the real token is in the 0600 auth.json alongside it.
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
              "base_instructions": "You are Tapgo AICoding, an autonomous coding agent powered by MiniMax-M3. For every actionable request, inspect the current workspace and use the available tools to implement and verify the result. Never claim that tools are unavailable unless a concrete tool call failed in the current turn. Treat persistent memory only as background; the current user request and current workspace evidence always win. Report meaningful progress incrementally and report failures immediately.",
              "supports_reasoning_summaries": true,
              "default_reasoning_summary": "none",
              "support_verbosity": false,
              "truncation_policy": { "mode": "bytes", "limit": 10000 },
              "supports_parallel_tool_calls": true,
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
