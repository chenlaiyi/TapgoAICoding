import Foundation

public enum PluginMarketplace: String, Codable, CaseIterable, Sendable {
    case codex
    case deepSeek

    public var displayName: String {
        switch self {
        case .codex: return "Codex 官方"
        case .deepSeek: return "DeepSeek 官方"
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
    public let version: String
    public let installed: Bool
    public let enabled: Bool
    public let source: Source?

    public func catalogItem() -> PluginCatalogItem {
        PluginCatalogItem(
            id: "codex:\(pluginId)",
            name: name,
            version: version,
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
