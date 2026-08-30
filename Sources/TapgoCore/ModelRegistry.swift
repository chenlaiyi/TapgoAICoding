// TapgoCore/ModelRegistry.swift
import Foundation

/// 用户自定义模型（v0.5.42 起）。内置 4 个模型（`TapgoModel`）之外，
/// 用户可在设置的「模型」页增删改查自己的模型：任意 OpenAI Responses
/// 协议端点 + API Key。Key 与模型定义一起存进注册表文件（0600），
/// `renderConfig` 会为每个自定义模型生成独立的
/// `[model_providers.custom-<id8>]` 段并注入 bearer。
///
/// 选择 ID 约定（`tapgo.model` UserDefaults）：
///   * 内置模型 = `builtin:<TapgoModel.rawValue>`（如 `builtin:MiniMax-M3`）
///   * 自定义模型 = `<CustomModel.id>`（如 `custom-AB12CD34`）
/// 旧版本只存裸 slug（如 `GLM-5.3-Flash`），读取时自动补 `builtin:` 前缀。
public struct CustomModel: Codable, Identifiable, Equatable {
    public var id: String
    public var displayName: String
    /// 发给上游 API 的模型 ID（如 `deepseek-v4-flash`）。
    public var apiModel: String
    public var brand: String
    public var baseURL: String
    public var apiKey: String
    public var contextWindow: Int

    public init(
        id: String = "custom-" + UUID().uuidString.prefix(8).uppercased(),
        displayName: String,
        apiModel: String,
        brand: String,
        baseURL: String,
        apiKey: String = "",
        contextWindow: Int = 1_000_000
    ) {
        self.id = id
        self.displayName = displayName
        self.apiModel = apiModel
        self.brand = brand
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.contextWindow = contextWindow
    }

    /// codex config.toml `[model_providers.<id>]` 段名，由模型 id 稳定派生，
    /// 增删改后保持不变。
    public var providerId: String { "custom-" + id.replacingOccurrences(of: "custom-", with: "") }

    /// 表单值入库前统一去掉首尾空白，避免同一个模型因粘贴空格而生成
    /// 无效的 API slug / URL / Key。`id` 由 App 生成，编辑时保持不变。
    public func normalizedForStorage() -> CustomModel {
        var copy = self
        copy.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.apiModel = apiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    /// 返回适合直接展示给用户的校验错误（v0.5.52 起改为一次返回多条）。
    /// UI 在表单顶部红字列出；`nil`/`[]` 都视为可保存。
    public var validationErrors: [String] {
        validationErrors(requireAPIKey: true)
    }

    /// 同 `validationErrors`，但允许调用方在「编辑既有自定义模型且未输入新
    /// Key」时关掉 API Key 必填校验（保留已写入的旧 Key）。
    public func validationErrors(requireAPIKey: Bool) -> [String] {
        let value = normalizedForStorage()
        var errors: [String] = []
        if value.displayName.isEmpty { errors.append("请填写显示名") }
        if value.apiModel.isEmpty { errors.append("请填写 API 模型 ID") }
        if value.brand.isEmpty { errors.append("请填写品牌") }
        if value.baseURL.isEmpty {
            errors.append("请填写端点 Base URL")
        } else {
            let acceptedAny = Self.isAcceptableBaseURL(value.baseURL, allowLocalhost: true)
            let acceptedPublic = Self.isAcceptableBaseURL(value.baseURL, allowLocalhost: false)
            if acceptedAny {
                // 通过：https 或 本地 http
            } else if acceptedPublic {
                // https 接受但 http-only 的 host（理论上不会到这里，留作保险）
                errors.append("端点必须是有效的 https Base URL（http 仅限本地）")
            } else if let scheme = URLComponents(string: value.baseURL)?.scheme?.lowercased(),
                      scheme == "http" {
                errors.append("明文 HTTP 仅限 localhost / 127.0.0.1 / ::1")
            } else {
                errors.append("端点必须是有效的 https Base URL（http 仅限本地）")
            }
        }
        if requireAPIKey, value.apiKey.isEmpty {
            errors.append("请填写 API Key")
        }
        if value.contextWindow <= 0 {
            errors.append("上下文窗口必须大于 0")
        }
        return errors
    }

    /// 端点 URL 校验：`https` 始终接受；`http` 仅在 host 是
    /// localhost / 127.0.0.1 / ::1 时接受，避免明文 token 走公网。
    /// 同时要求无 user/password/query/fragment（与历史约束一致）。
    public static func isAcceptableBaseURL(_ raw: String, allowLocalhost: Bool) -> Bool {
        guard let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              let host = components.host, !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else { return false }
        if scheme == "https" { return true }
        // scheme == "http"
        if !allowLocalhost { return false }
        let lower = host.lowercased()
        return lower == "localhost"
            || lower == "127.0.0.1"
            || lower == "::1"
            || lower.hasSuffix(".localhost")
    }

    /// 兼容旧调用方（v0.5.42/v0.5.51 测试与外部 API）；返回首条错误或 nil。
    public var validationError: String? {
        validationErrors.first
    }

    /// v0.5.52 起支持更多上下文档位：8K → 1M 升序排列。
    public static let contextWindowOptions: [Int] = [
        8_192, 16_384, 32_768, 65_536, 128_000, 200_000, 256_000, 500_000, 1_000_000
    ]

    /// 把任意整数吸附到最近一档上下文窗口；未知值落到 1M。
    public static func normalizedContextWindow(_ raw: Int) -> Int {
        contextWindowOptions.first(where: { $0 == raw }) ?? 1_000_000
    }

    enum CodingKeys: String, CodingKey {
        case id, displayName, apiModel, brand, baseURL, apiKey, contextWindow
    }
}

public struct ModelRegistryState: Codable, Equatable {
    public var customModels: [CustomModel] = []
    public var selectedID: String = ""
    public init() {}
}

/// 自定义模型的注册表：持久化为单个 JSON 文件（0600，与 auth 系列同设计）。
/// 纯文件驱动、无全局单例，路径由上层注入以便单测。
public final class ModelRegistry {
    public let fileURL: URL
    public private(set) var state: ModelRegistryState

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(ModelRegistryState.self, from: data) {
            state = decoded
        } else {
            state = ModelRegistryState()
        }
    }

    // MARK: - Queries

    public var customModels: [CustomModel] { state.customModels }

    public func customModel(id: String) -> CustomModel? {
        state.customModels.first { $0.id == id }
    }

    /// 是否是内置模型的选中 ID（`builtin:<slug>`，兼容旧裸 slug）。
    public static func isBuiltinID(_ id: String) -> Bool {
        id.hasPrefix("builtin:") || !id.hasPrefix("custom-")
    }

    /// 归一化选中 ID：裸 slug → `builtin:<slug>`；自定义 ID 原样返回。
    public static func normalizedID(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("builtin:") || value.hasPrefix("custom-") { return value }
        return value.isEmpty ? "" : "builtin:" + value
    }

    // MARK: - Mutations

    public func add(_ model: CustomModel) {
        let normalized = model.normalizedForStorage()
        guard normalized.validationError == nil else { return }
        if let index = state.customModels.firstIndex(where: { $0.id == normalized.id }) {
            state.customModels[index] = normalized
        } else {
            state.customModels.append(normalized)
        }
        save()
    }

    public func update(_ model: CustomModel) {
        let normalized = model.normalizedForStorage()
        guard normalized.validationError == nil,
              let index = state.customModels.firstIndex(where: { $0.id == normalized.id })
        else { return }
        state.customModels[index] = normalized
        save()
    }

    /// 删除自定义模型。返回被删模型的显示名（供 UI 提示）；删除后若当前
    /// 选中它，选中态清空（上层回落到默认模型）。
    @discardableResult
    public func remove(id: String) -> Bool {
        guard let index = state.customModels.firstIndex(where: { $0.id == id }) else { return false }
        state.customModels.remove(at: index)
        if state.selectedID == id { state.selectedID = "" }
        save()
        return true
    }

    public func setSelected(_ id: String) {
        state.selectedID = Self.normalizedID(id)
        save()
    }

    // MARK: - Persistence

    public func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
