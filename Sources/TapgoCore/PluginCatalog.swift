import Foundation

public enum PluginMarketplace: String, Codable, CaseIterable, Sendable {
    case codex
    case deepSeek
    case tapgo

    public var displayName: String {
        switch self {
        case .codex: return "Codex 官方"
        case .deepSeek: return "DeepSeek 官方"
        case .tapgo: return "Tapgo 官方"
        }
    }
}

public struct PluginCatalogItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public var displayName: String
    public let version: String
    public var summary: String
    public let marketplace: PluginMarketplace
    public let marketplaceName: String
    public let installSpecifier: String
    public var installed: Bool
    public var enabled: Bool
    public var capabilities: [String]
    public let sourcePath: String?

    public init(
        id: String,
        name: String,
        displayName: String? = nil,
        version: String,
        summary: String = "",
        marketplace: PluginMarketplace,
        marketplaceName: String,
        installSpecifier: String,
        installed: Bool,
        enabled: Bool,
        capabilities: [String] = [],
        sourcePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName ?? Self.humanized(name)
        self.version = version
        self.summary = summary
        self.marketplace = marketplace
        self.marketplaceName = marketplaceName
        self.installSpecifier = installSpecifier
        self.installed = installed
        self.enabled = enabled
        self.capabilities = capabilities
        self.sourcePath = sourcePath
    }

    public func matches(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        return [displayName, name, summary, version, capabilities.joined(separator: " ")]
            .joined(separator: " ")
            .lowercased()
            .contains(normalized)
    }

    public static func humanized(_ raw: String) -> String {
        let tail = raw.split(separator: "/").last.map(String.init) ?? raw
        return tail
            .split(separator: "-")
            .map { word in
                guard let first = word.first else { return "" }
                return String(first).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}

public struct CodexPluginListPayload: Decodable, Sendable {
    public let installed: [CodexPluginRecord]
    public let available: [CodexPluginRecord]
}

public struct CodexPluginRecord: Decodable, Sendable {
    public struct Source: Decodable, Sendable {
        public let path: String?
    }

    public let pluginId: String
    public let name: String
    public let marketplaceName: String
    /// Some git-backed marketplace entries do not publish a semantic version.
    /// Keep those records visible instead of failing the entire catalog.
    public let version: String?
    public let installed: Bool
    public let enabled: Bool
    public let source: Source?

    public func catalogItem() -> PluginCatalogItem {
        PluginCatalogItem(
            id: "codex:\(pluginId)",
            name: name,
            version: version ?? "—",
            marketplace: .codex,
            marketplaceName: marketplaceName,
            installSpecifier: pluginId,
            installed: installed,
            enabled: enabled,
            sourcePath: source?.path
        )
    }
}

public struct NPMPackageSearchRecord: Decodable, Sendable {
    public let name: String
    public let version: String
    public let description: String?

    public init(name: String, version: String, description: String?) {
        self.name = name
        self.version = version
        self.description = description
    }
}

public enum PluginCatalogParser {
    public static func decodeCodex(_ data: Data) throws -> [PluginCatalogItem] {
        let payload = try JSONDecoder().decode(CodexPluginListPayload.self, from: data)
        var byId: [String: PluginCatalogItem] = [:]
        for record in payload.available + payload.installed {
            byId[record.pluginId] = record.catalogItem()
        }
        return byId.values.sorted {
            if $0.installed != $1.installed { return $0.installed && !$1.installed }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    public static func decodeDeepSeekSearch(
        _ data: Data,
        installedNames: Set<String>
    ) throws -> [PluginCatalogItem] {
        let records = try JSONDecoder().decode([NPMPackageSearchRecord].self, from: data)
        return deepSeekItems(records, installedNames: installedNames)
    }

    public static func deepSeekItems(
        _ records: [NPMPackageSearchRecord],
        installedNames: Set<String>
    ) -> [PluginCatalogItem] {
        let officialBundles: [String: String] = [
            "@deepseek-ai/dsh-subagent-codex": "Codex 子代理",
            "@deepseek-ai/dsh-subagent-claude-code": "Claude Code 子代理"
        ]
        return records
            .filter { officialBundles[$0.name] != nil }
            .map { record in
                PluginCatalogItem(
                    id: "deepseek:\(record.name)",
                    name: record.name,
                    displayName: officialBundles[record.name],
                    version: record.version,
                    summary: record.description ?? "DeepSeek Harness 官方插件包",
                    marketplace: .deepSeek,
                    marketplaceName: "@deepseek-ai",
                    installSpecifier: record.name + "@next",
                    installed: installedNames.contains(record.name),
                    enabled: installedNames.contains(record.name),
                    capabilities: ["Harness 插件", "官方适配"]
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public static func decodeTapgo(
        _ data: Data,
        installedIds: Set<String>
    ) throws -> [PluginCatalogItem] {
        let payload = try JSONDecoder().decode(TapgoPluginListPayload.self, from: data)
        return payload.available
            .map { record -> PluginCatalogItem in
                let installed = installedIds.contains(record.pluginId)
                return record.catalogItem(installed: installed)
            }
            .sorted {
                if $0.installed != $1.installed { return $0.installed && !$1.installed }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }
}

public enum PluginConfigEditor {
    public static func settingEnabled(_ enabled: Bool, for pluginId: String, in source: String) -> String? {
        guard isSafePluginId(pluginId) else { return nil }
        let header = "[plugins.\"\(pluginId)\"]"
        var lines = source.components(separatedBy: "\n")

        if let headerIndex = lines.firstIndex(of: header) {
            var index = headerIndex + 1
            while index < lines.count, !lines[index].hasPrefix("[") {
                if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("enabled") {
                    lines[index] = "enabled = \(enabled ? "true" : "false")"
                    return lines.joined(separator: "\n")
                }
                index += 1
            }
            lines.insert("enabled = \(enabled ? "true" : "false")", at: headerIndex + 1)
            return lines.joined(separator: "\n")
        }

        var result = source
        if !result.isEmpty, !result.hasSuffix("\n") { result += "\n" }
        result += "\n\(header)\nenabled = \(enabled ? "true" : "false")\n"
        return result
    }

    public static func isSafePluginId(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 180 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._@/"))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

/// `~/.tapgo/plugins.toml` 的最小读写：只管理 `[plugins]` 表下的
/// `"<pluginId>" = true|false` 键，作为 Tapgo 官方插件启用/停用的持久化。
/// 没有记录的插件默认启用——"装了即启用"，停用是显式动作。
public enum TapgoPluginsToml {
    /// 解析 `[plugins]` 表里显式为 `true` 的 pluginId 集合；注释行与损坏行
    /// 原样跳过，其它表（`[其它]`）不参与。
    public static func enabledPluginIds(in source: String) -> Set<String> {
        var result: Set<String> = []
        var inPlugins = false
        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inPlugins = line == "[plugins]"
                continue
            }
            guard inPlugins, !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let value = parts[1].split(separator: "#").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            if value == "true" { result.insert(key) }
        }
        return result
    }

    /// 把 `pluginId` 的启用状态写回 toml 源：键已存在时原地翻转，缺 `[plugins]`
    /// 表时在文件末尾追加；其它行原样保留。pluginId 含 `..`、以 `/` 开头或
    /// 不通过 isSafePluginId 时返回 nil（isSafePluginId 允许 `/`，这里再挡
    /// 一层路径穿越）。
    public static func settingEnabled(_ enabled: Bool, pluginId: String, in source: String) -> String? {
        guard PluginConfigEditor.isSafePluginId(pluginId),
              !pluginId.contains(".."),
              !pluginId.hasPrefix("/") else { return nil }
        var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var inPlugins = false
        var pluginsHeaderIndex: Int? = nil
        var keyLineIndex: Int? = nil
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inPlugins = trimmed == "[plugins]"
                if inPlugins, pluginsHeaderIndex == nil { pluginsHeaderIndex = i }
                continue
            }
            guard inPlugins else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if key == pluginId { keyLineIndex = i; break }
        }
        let newLine = "\"\(pluginId)\" = \(enabled ? "true" : "false")"
        if let idx = keyLineIndex {
            lines[idx] = newLine
        } else if let header = pluginsHeaderIndex {
            lines.insert(newLine, at: header + 1)
        } else {
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.removeLast()
            }
            lines.append("")
            lines.append("[plugins]")
            lines.append(newLine)
        }
        return lines.joined(separator: "\n") + "\n"
    }
}


// MARK: - Tapgo 官方插件目录
//
// Tapgo 官方插件目录由 https://plugins.itapgo.com/catalog.json 提供。
// 协议保持最小：每个插件必须包含 pluginId、name、repo；displayName/version/
// description/channel/capabilities 可选，方便运维侧后期补全。
// 安装通过 `git clone <repo> --branch <channel>` 到 `~/.tapgo/plugins/<pluginId>/`
// 完成；卸载即 `rm -rf` 同名目录。本地已安装列表由文件系统直接推导，不需要
// 在服务端维护一份清单。

public struct TapgoPluginListPayload: Decodable, Sendable {
    public let available: [TapgoPluginRecord]
}

public struct TapgoPluginRecord: Decodable, Sendable {
    public let pluginId: String
    public let name: String
    public let displayName: String?
    public let version: String?
    public let description: String?
    public let repo: String
    public let channel: String?
    public let capabilities: [String]?

    public func catalogItem(installed: Bool) -> PluginCatalogItem {
        let resolvedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return PluginCatalogItem(
            id: "tapgo:\(pluginId)",
            name: name,
            displayName: (resolvedName?.isEmpty == false ? resolvedName : nil),
            version: version ?? "—",
            summary: description ?? "Tapgo 官方插件",
            marketplace: .tapgo,
            marketplaceName: "plugins.itapgo.com",
            installSpecifier: repo,
            installed: installed,
            enabled: installed,
            capabilities: capabilities ?? ["Tapgo 插件"]
        )
    }
}

