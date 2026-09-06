import Foundation
import TapgoCore

enum PluginManagerError: LocalizedError {
    case commandFailed(String)
    case invalidOutput(String)
    case invalidPluginId
    case executableMissing(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): return message
        case .invalidOutput(let message): return message
        case .invalidPluginId: return "插件标识不安全，已拒绝操作。"
        case .executableMissing(let name): return "没有找到 \(name)，请先安装对应的官方 CLI。"
        }
    }
}

struct PluginManagerService: Sendable {
    private struct CommandOutput: Sendable {
        let data: Data
        let status: Int32
    }

    private struct PluginManifest: Decodable {
        struct Interface: Decodable {
            let displayName: String?
            let shortDescription: String?
        }

        let description: String?
        let skills: String?
        let mcpServers: String?
        let apps: String?
        let interface: Interface?
    }

    private let codexPath: String
    private let dshPath: String?
    private let npmPath: String?
    private let codexHome: URL
    private let codexConfig: URL
    private let dshProfileName = "web"

    init() {
        let codex = RemoteCodexHomeSync.findHarness()
        codexPath = codex
        let bin = URL(fileURLWithPath: codex).deletingLastPathComponent()
        dshPath = Self.locate("dsh", preferredDirectory: bin)
        npmPath = Self.locate("npm", preferredDirectory: bin)
        codexHome = TapgoConfig.codexHome
        codexConfig = TapgoConfig.configPath
    }

    func loadCatalog() async throws -> [PluginCatalogItem] {
        async let codex = loadCodexCatalog()
        async let deepSeek = loadDeepSeekCatalog()
        // Tapgo 官方市场独立托管在 plugins.itapgo.com，下载/解析失败静默降级，
        // 不影响其它市场目录的呈现。
        let tapgo = await loadTapgoCatalog()
        return try await codex + deepSeek + tapgo
    }

    func install(_ item: PluginCatalogItem) async throws {
        guard PluginConfigEditor.isSafePluginId(item.installSpecifier) else {
            throw PluginManagerError.invalidPluginId
        }
        switch item.marketplace {
        case .codex:
            _ = try await runCodex(["plugin", "add", item.installSpecifier, "--json"])
        case .deepSeek:
            guard let dshPath else { throw PluginManagerError.executableMissing("dsh") }
            _ = try await Self.run(
                executable: dshPath,
                arguments: ["plugin", "--profile", dshProfileName, "add", item.installSpecifier],
                environment: Self.commandEnvironment(extraPath: URL(fileURLWithPath: dshPath).deletingLastPathComponent().path)
            )
        case .tapgo:
            try await installTapgoPlugin(item)
        }
    }

    func uninstall(_ item: PluginCatalogItem) async throws {
        guard PluginConfigEditor.isSafePluginId(item.installSpecifier) else {
            throw PluginManagerError.invalidPluginId
        }
        switch item.marketplace {
        case .codex:
            _ = try await runCodex(["plugin", "remove", item.installSpecifier, "--json"])
        case .deepSeek:
            guard let dshPath else { throw PluginManagerError.executableMissing("dsh") }
            guard PluginConfigEditor.isSafePluginId(item.name) else {
                throw PluginManagerError.invalidPluginId
            }
            _ = try await Self.run(
                executable: dshPath,
                arguments: ["plugin", "--profile", dshProfileName, "remove", item.name],
                environment: Self.commandEnvironment(extraPath: URL(fileURLWithPath: dshPath).deletingLastPathComponent().path)
            )
        case .tapgo:
            try await uninstallTapgoPlugin(item)
        }
    }

    func setCodexEnabled(_ enabled: Bool, item: PluginCatalogItem) async throws {
        guard item.marketplace == .codex,
              PluginConfigEditor.isSafePluginId(item.installSpecifier) else {
            throw PluginManagerError.invalidPluginId
        }
        let configURL = codexConfig
        try await Task.detached(priority: .utility) {
            let source = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
            guard let updated = PluginConfigEditor.settingEnabled(
                enabled, for: item.installSpecifier, in: source
            ) else {
                throw PluginManagerError.invalidPluginId
            }
            try updated.write(to: configURL, atomically: true, encoding: .utf8)
        }.value
    }

    private func loadCodexCatalog() async throws -> [PluginCatalogItem] {
        let output = try await runCodex(["plugin", "list", "--available", "--json"])
        var items: [PluginCatalogItem]
        do {
            items = try PluginCatalogParser.decodeCodex(output.data)
        } catch {
            throw PluginManagerError.invalidOutput("Codex 插件目录解析失败：\(error.localizedDescription)")
        }
        return items.map(enrichCodexMetadata)
    }

    private func enrichCodexMetadata(_ item: PluginCatalogItem) -> PluginCatalogItem {
        guard let sourcePath = item.sourcePath else { return item }
        let manifestURL = URL(fileURLWithPath: sourcePath)
            .appendingPathComponent(".codex-plugin/plugin.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else {
            return item
        }
        var enriched = item
        enriched.displayName = manifest.interface?.displayName ?? item.displayName
        enriched.summary = manifest.interface?.shortDescription
            ?? manifest.description?.components(separatedBy: "\n").first
            ?? "Codex 官方插件"
        var capabilities: [String] = []
        if manifest.apps != nil { capabilities.append("应用") }
        if manifest.mcpServers != nil { capabilities.append("MCP") }
        if manifest.skills != nil { capabilities.append("技能") }
        enriched.capabilities = capabilities
        return enriched
    }

    private func loadDeepSeekCatalog() async throws -> [PluginCatalogItem] {
        guard let npmPath else { return [] }
        let installed = Self.deepSeekInstalledPackages(profile: dshProfileName)
        async let codex = loadNPMPackage("@deepseek-ai/dsh-subagent-codex@next", npmPath: npmPath)
        async let claude = loadNPMPackage("@deepseek-ai/dsh-subagent-claude-code@next", npmPath: npmPath)
        let records = try await [codex, claude]
        return PluginCatalogParser.deepSeekItems(records, installedNames: installed)
    }

    private func loadNPMPackage(_ name: String, npmPath: String) async throws -> NPMPackageSearchRecord {
        let output = try await Self.run(
            executable: npmPath,
            arguments: ["view", name, "name", "version", "description", "--json"],
            environment: Self.commandEnvironment(extraPath: URL(fileURLWithPath: npmPath).deletingLastPathComponent().path)
        )
        return try JSONDecoder().decode(NPMPackageSearchRecord.self, from: output.data)
    }

    private func runCodex(_ arguments: [String]) async throws -> CommandOutput {
        var environment = Self.commandEnvironment(extraPath: URL(fileURLWithPath: codexPath).deletingLastPathComponent().path)
        environment["CODEX_HOME"] = codexHome.path
        return try await Self.run(executable: codexPath, arguments: arguments, environment: environment)
    }

    private static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) async throws -> CommandOutput {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                throw PluginManagerError.commandFailed("无法启动插件管理命令：\(error.localizedDescription)")
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw PluginManagerError.commandFailed(message?.isEmpty == false ? message! : "插件管理命令执行失败。")
            }
            return CommandOutput(data: data, status: process.terminationStatus)
        }.value
    }

    private static func deepSeekInstalledPackages(profile: String) -> Set<String> {
        let home = ProcessInfo.processInfo.environment["DSH_HOME"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh")
        let manifest = home.appendingPathComponent("profiles/\(profile)/package.json")
        guard let data = try? Data(contentsOf: manifest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dependencies = json["dependencies"] as? [String: Any] else { return [] }
        return Set(dependencies.keys)
    }

    private static func commandEnvironment(extraPath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let current = environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        environment["PATH"] = extraPath + ":" + current
        environment["NO_COLOR"] = "1"
        return environment
    }

    private static func locate(_ name: String, preferredDirectory: URL) -> String? {
        let fm = FileManager.default
        let preferred = preferredDirectory.appendingPathComponent(name).path
        if fm.isExecutableFile(atPath: preferred) { return preferred }
        for path in ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        where fm.isExecutableFile(atPath: path) {
            return path
        }
        let nvm = fm.homeDirectoryForCurrentUser.appendingPathComponent(".nvm/versions/node")
        let versions = (try? fm.contentsOfDirectory(at: nvm, includingPropertiesForKeys: nil)) ?? []
        for version in versions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            let candidate = version.appendingPathComponent("bin/\(name)").path
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    // MARK: - Tapgo 官方插件市场
    //
    // 协议：plugins.itapgo.com/catalog.json 返回 TapgoPluginListPayload。
    // 安装通过 `git clone <repo> [--branch <channel>]` 到 ~/.tapgo/plugins/<id>/
    // 完成；卸载即 rm -rf 整个目录。pluginId 由 item.id 末段取出
    // （"tapgo:<pluginId>"），需通过 PluginConfigEditor.isSafePluginId 校验。

    private let tapgoCatalogURL = URL(string: "https://plugins.itapgo.com/catalog.json")!

    private func tapgoPluginsRoot() -> URL {
        let home = ProcessInfo.processInfo.environment["TAPGO_PLUGINS_HOME"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tapgo/plugins")
        return home
    }

    private func tapgoPluginDirectory(for item: PluginCatalogItem) throws -> URL {
        let id = try Self.tapgoPluginId(from: item.id)
        return tapgoPluginsRoot().appendingPathComponent(id, isDirectory: true)
    }

    private static func tapgoPluginId(from catalogId: String) throws -> String {
        let parts = catalogId.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == "tapgo" else {
            throw PluginManagerError.invalidPluginId
        }
        let id = parts[1]
        guard PluginConfigEditor.isSafePluginId(id), !id.isEmpty else {
            throw PluginManagerError.invalidPluginId
        }
        return id
    }

    private func loadTapgoCatalog() async -> [PluginCatalogItem] {
        do {
            let data = try await Self.fetchTapgoCatalog(url: tapgoCatalogURL)
            let installed = Self.installedTapgoPluginIds(root: tapgoPluginsRoot())
            return try PluginCatalogParser.decodeTapgo(data, installedIds: installed)
        } catch {
            // 官方目录拉取/解析失败时静默降级，避免阻塞其它市场；网络问题留到
            // 用户点击「Tapgo 官方」Tab 时通过空列表的 emptyMessage 提示。
            return []
        }
    }

    private func installTapgoPlugin(_ item: PluginCatalogItem) async throws {
        let target = try self.tapgoPluginDirectory(for: item)
        let repoURL = item.installSpecifier
        guard let repo = URL(string: repoURL),
                  let scheme = repo.scheme?.lowercased(),
                  scheme == "https" || scheme == "git" || scheme == "ssh" else {
            throw PluginManagerError.invalidOutput("Tapgo 插件仓库地址不合法：\(repoURL)")
        }
        guard let gitPath = Self.locate("git", preferredDirectory: URL(fileURLWithPath: "/")) else {
            throw PluginManagerError.executableMissing("git")
        }
        let pluginId = try Self.tapgoPluginId(from: item.id)
        let channel = Self.tapgoChannel(fromSummary: item.summary)

        try FileManager.default.createDirectory(
            at: tapgoPluginsRoot(),
            withIntermediateDirectories: true
        )

        var arguments = ["clone", "--depth", "1"]
        if let channel, PluginConfigEditor.isSafePluginId(channel) {
            arguments.append(contentsOf: ["--branch", channel])
        }
        arguments.append(contentsOf: [repoURL, target.path])

        _ = try await Self.run(
            executable: gitPath,
            arguments: arguments,
            environment: Self.commandEnvironment(extraPath: URL(fileURLWithPath: gitPath).deletingLastPathComponent().path)
        )

        // 把 pluginId 写入本地 manifest，便于下次加载时识别已安装。
        let manifest = target.appendingPathComponent(".tapgo-plugin.json")
        let payload: [String: Any] = [
            "pluginId": pluginId,
            "name": item.name,
            "version": item.version,
            "installedAt": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: manifest)
        }
    }

    private func uninstallTapgoPlugin(_ item: PluginCatalogItem) async throws {
        let target = try self.tapgoPluginDirectory(for: item)
        let fm = FileManager.default
        if fm.fileExists(atPath: target.path) {
            try fm.removeItem(at: target)
        }
    }

    private static func tapgoChannel(fromSummary summary: String) -> String? {
        // 预留钩子：后续 summary 里出现 "#channel=xxx" 时优先采用；
        // 当前 catalog 协议把 channel 放在独立字段，留作后续解析。
        return nil
    }

    private static func installedTapgoPluginIds(root: URL) -> Set<String> {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var ids = Set<String>()
        for entry in entries {
            let manifest = entry.appendingPathComponent(".tapgo-plugin.json")
            if let data = try? Data(contentsOf: manifest),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = json["pluginId"] as? String,
               PluginConfigEditor.isSafePluginId(id) {
                ids.insert(id)
            } else if PluginConfigEditor.isSafePluginId(entry.lastPathComponent) {
                // 即便没写 manifest，也认目录名作为 pluginId，宽容手装插件。
                ids.insert(entry.lastPathComponent)
            }
        }
        return ids
    }

    private static func fetchTapgoCatalog(url: URL) async throws -> Data {
        try await Task.detached(priority: .utility) { () -> Data in
            let session = URLSession(configuration: .ephemeral)
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 6
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw PluginManagerError.commandFailed("Tapgo 官方目录返回 \(http.statusCode)")
            }
            return data
        }.value
    }

}

