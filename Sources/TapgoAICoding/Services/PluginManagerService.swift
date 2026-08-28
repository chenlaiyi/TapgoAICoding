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
        return try await codex + deepSeek
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
            _ = try await Self.run(
                executable: dshPath,
                arguments: ["plugin", "--profile", dshProfileName, "remove", item.installSpecifier],
                environment: Self.commandEnvironment(extraPath: URL(fileURLWithPath: dshPath).deletingLastPathComponent().path)
            )
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
        let output = try await Self.run(
            executable: npmPath,
            arguments: ["search", "--json", "--searchlimit=250", "@deepseek-ai/dsh-"],
            environment: Self.commandEnvironment(extraPath: URL(fileURLWithPath: npmPath).deletingLastPathComponent().path)
        )
        let records: [NPMPackageSearchRecord]
        do {
            var decoded = try JSONDecoder().decode([NPMPackageSearchRecord].self, from: output.data)
            for package in ["@deepseek-ai/dsh-subagent-codex", "@deepseek-ai/dsh-subagent-claude-code"]
            where !decoded.contains(where: { $0.name == package }) {
                if let record = try? await loadNPMPackage(package, npmPath: npmPath) {
                    decoded.append(record)
                }
            }
            records = decoded
        } catch {
            throw PluginManagerError.invalidOutput("DeepSeek 官方插件目录解析失败：\(error.localizedDescription)")
        }
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
}
