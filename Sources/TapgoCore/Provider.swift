// TapgoCore/Provider.swift
// v0.5.53 起：模型设置 1:1 仿造 ZCode —— 把模型供应商抽成两级：
//   * Provider（供应商，例如智谱 / MiniMax / DeepSeek / 用户自建）
//   * ProviderModel（供应商下的具体模型，例如 GLM-5.3 / GLM-5.3-Flash / GLM-5-Turbo）
//
// 每个 Provider 自带 baseURL / apiKey，内嵌 models 数组；
// TapgoProviderKind 是内置供应商枚举（zhipu / minimax / deepseek）。
//
// 这套结构独立于既有 TapgoModel / CustomModel / ModelRegistry：
// 旧 API 仍由 TapgoConfig / harness catalog 使用，避免破坏 ChatView
// 与手机 H5 现有调用链。新模型设置页（ModelSettingsView）只走这里。

import Foundation

/// 内置供应商分类（v0.5.53 起）。每个 case 自带 baseURL 与默认模型列表。
/// v0.5.319 起只保留 DeepSeek 一个内置供应商（智谱 / MiniMax 已下线，
/// 对应 case 一并删除；旧 `provider-registry.json` 里的遗留条目由
/// `ensureBuiltinProviders()` 清理）。
public enum TapgoProviderKind: String, Codable, CaseIterable, Equatable {
    case deepseek

    /// 启用名单：只有名单内的内置供应商会被 `ensureBuiltinProviders()`
    /// 自动补全并出现在设置页；名单外的 `builtin:*` 条目（例如已下线的
    /// `builtin:zhipu` / `builtin:minimax`）会被连同选中态一起清除。
    /// 恢复某个内置供应商时，把 case 加回枚举并加入本名单。
    public static let enabledBuiltinKinds: [TapgoProviderKind] = [.deepseek]

    public var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        }
    }

    public var brand: String {
        switch self {
        case .deepseek: return "DeepSeek"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com"
        }
    }

    /// 该内置供应商下默认挂载的模型列表（v0.5.53）。
    /// DeepSeek 挂 flash / pro 两个模型，作为内置兜底。
    public var defaultModels: [ProviderModel] {
        switch self {
        case .deepseek:
            return [
                // deepseek API 仅接受 deepseek-flash / deepseek-v4-pro 两个模型名,
                // 传其他名字返回 invalid_request_error (v0.5.319 修正)。
                ProviderModel(
                    id: "builtin:deepseek::deepseek-v4-flash",
                    displayName: "DeepSeek V4 Flash",
                    apiModel: "deepseek-flash",
                    contextWindow: 1_048_576,
                    isCustom: false),
                ProviderModel(
                    id: "builtin:deepseek::deepseek-v4-pro",
                    displayName: "DeepSeek V4 Pro",
                    apiModel: "deepseek-v4-pro",
                    contextWindow: 1_048_576,
                    isCustom: false),
            ]
        }
    }

    /// 注册表里表示该内置供应商的稳定 ID（与 TapgoConfig 旧 `builtin:<slug>`
    /// 路径兼容，避免 v0.5.52 选中态解析失效）。
    public var registryID: String { "builtin:" + rawValue }
}

/// 官方额度接口通道。只由内置供应商身份决定，不能用可编辑的
/// `ProviderModel.apiModel` 反查：用户在模型设置页把 DeepSeek 改成
/// `deepseek-v4.1-flash` 后，旧逻辑因枚举查不到而误判为自定义模型。
/// 官方额度接口通道。当前只保留 DeepSeek 一个内置供应商身份。
public enum TapgoQuotaChannel: String, Codable, Equatable {
    case deepseek
}

/// 供应商（v0.5.53 起）。`builtIn` 非空 = 内置供应商（key/端点允许用户改，
/// 模型列表可改）；`builtIn == nil` = 用户自建供应商（全部字段可改）。
public struct Provider: Codable, Identifiable, Equatable {
    public var id: String
    public var displayName: String
    public var brand: String
    public var baseURL: String
    public var apiKey: String
    public var models: [ProviderModel]
    /// 与旧 TapgoProviderKind 字符串互转；nil 表示自定义。
    public var builtInKindRaw: String?

    public init(
        id: String,
        displayName: String,
        brand: String,
        baseURL: String,
        apiKey: String = "",
        models: [ProviderModel] = [],
        builtInKindRaw: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.brand = brand
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.models = models
        self.builtInKindRaw = builtInKindRaw
    }

    /// 内置供应商便捷初始化。
    public static func builtin(_ kind: TapgoProviderKind) -> Provider {
        Provider(
            id: kind.registryID,
            displayName: kind.displayName,
            brand: kind.brand,
            baseURL: kind.defaultBaseURL,
            apiKey: "",
            models: kind.defaultModels,
            builtInKindRaw: kind.rawValue
        )
    }

    public var builtInKind: TapgoProviderKind? {
        get { builtInKindRaw.flatMap(TapgoProviderKind.init(rawValue:)) }
        set { builtInKindRaw = newValue?.rawValue }
    }

    public var isBuiltin: Bool { builtInKind != nil }

    /// 当前 Provider 对应的官方额度通道；自定义 Provider 无额度接口。
    public var quotaChannel: TapgoQuotaChannel? {
        switch builtInKind {
        case .deepseek: return .deepseek
        case nil: return nil
        }
    }

    /// 单字段校验错误列表。UI 在 Provider / AddProviderSheet 顶部红字列出。
    public var validationErrors: [String] {
        validationErrors(apiKeyRequired: true)
    }

    public func validationErrors(apiKeyRequired: Bool) -> [String] {
        var errors: [String] = []
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("请填写显示名")
        }
        if brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("请填写品牌")
        }
        if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("请填写端点 Base URL")
        } else if !ProviderURLValidator.isAcceptable(baseURL, allowLocalhost: true) {
            if ProviderURLValidator.isAcceptable(baseURL, allowLocalhost: false) {
                errors.append("端点必须是有效的 https Base URL（http 仅限本地）")
            } else if let scheme = URLComponents(string: baseURL)?.scheme?.lowercased(),
                      scheme == "http" {
                errors.append("明文 HTTP 仅限 localhost / 127.0.0.1 / ::1")
            } else {
                errors.append("端点必须是有效的 https Base URL（http 仅限本地）")
            }
        }
        if apiKeyRequired, apiKey.isEmpty {
            errors.append("请填写 API Key")
        }
        if models.isEmpty {
            errors.append("供应商至少需要一个模型")
        } else {
            for (idx, m) in models.enumerated() {
                let merrs = m.validationErrors
                if !merrs.isEmpty {
                    errors.append("模型 \(idx + 1)（\(m.displayName.isEmpty ? "未命名" : m.displayName)）：\(merrs.joined(separator: "；"))")
                }
            }
        }
        return errors
    }
}

/// 供应商下的具体模型（v0.5.53 起）。
public struct ProviderModel: Codable, Identifiable, Equatable {
    public var id: String
    public var displayName: String
    public var apiModel: String
    public var contextWindow: Int
    public var isCustom: Bool

    public init(
        id: String,
        displayName: String,
        apiModel: String,
        contextWindow: Int,
        isCustom: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.apiModel = apiModel
        self.contextWindow = contextWindow
        self.isCustom = isCustom
    }

    public var validationErrors: [String] {
        var errors: [String] = []
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("显示名")
        }
        if apiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("API 模型 ID")
        }
        if contextWindow <= 0 {
            errors.append("上下文窗口必须大于 0")
        }
        return errors
    }
}

// MARK: - 端点 URL 校验（v0.5.52 起）：https 始终接受；http 仅在 host
// 是 localhost / 127.0.0.1 / ::1 时接受，避免明文 token 走公网。
public enum ProviderURLValidator {
    public static func isAcceptable(_ raw: String, allowLocalhost: Bool) -> Bool {
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
        if !allowLocalhost { return false }
        let lower = host.lowercased()
        return lower == "localhost"
            || lower == "127.0.0.1"
            || lower == "::1"
            || lower.hasSuffix(".localhost")
    }
}
