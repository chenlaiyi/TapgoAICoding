// TapgoCore/DeepSeekQuotaClient.swift
import Foundation

/// 读取 DeepSeek 账户余额，归一化为 `RateLimitsSnapshot`（仅 credits 一栏）。
///
/// DeepSeek 是按量计费（无订阅窗口），官方提供余额接口：
/// `GET https://api.deepseek.com/user/balance`，Bearer 鉴权，响应：
///
///     {"is_available":true,"balance_infos":[
///       {"currency":"CNY","total_balance":"17.95",
///        "granted_balance":"0.00","topped_up_balance":"17.95"}]}
///
/// 映射：`credits = (hasCredits: true, unlimited: false, balance: "¥17.95")`，
/// primary/secondary 恒为 nil（无 5 小时/每周窗口概念）。
public final class DeepSeekQuotaClient {
    public static let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!

    public let authPath: URL
    private let apiKey: String?
    let session: URLSession
    /// 仅测试用：替换 `URLSession` 让解析逻辑在不依赖网络的情况下验证。
    private let _transportOverride: ((URLRequest) async throws -> (Data, HTTPURLResponse))?

    public init(authPath: URL, session: URLSession = .shared) {
        self.authPath = authPath
        self.apiKey = nil
        self.session = session
        self._transportOverride = nil
    }

    /// ProviderRegistry 已接管凭据后的生产入口，不再依赖旧 auth 文件。
    public init(apiKey: String, session: URLSession = .shared) {
        self.authPath = URL(fileURLWithPath: "/dev/null")
        self.apiKey = apiKey
        self.session = session
        self._transportOverride = nil
    }

    /// 仅供单元测试使用：传入一个固定的 transport 闭包。
    init(authPath: URL, transport: @escaping (URLRequest) async throws -> (Data, HTTPURLResponse)) {
        self.authPath = authPath
        self.apiKey = nil
        self.session = URLSession.shared
        self._transportOverride = transport
    }

    // MARK: - Public

    enum QuotaError: LocalizedError {
        case missingAuthFile(String)
        case missingKey
        case http(status: Int, endpoint: String)
        case decoding(String, endpoint: String)
        case unavailable(endpoint: String)
        case noBalanceInfo(endpoint: String)

        var errorDescription: String? {
            switch self {
            case .missingAuthFile(let path):
                return "未找到 DeepSeek 凭据文件：\(path)"
            case .missingKey:
                return "auth-deepseek.json 中缺少 OPENAI_API_KEY，无法查询 DeepSeek 余额"
            case .http(let status, let endpoint):
                return "DeepSeek 余额接口 \(endpoint) HTTP \(status)"
            case .decoding(let detail, let endpoint):
                return "DeepSeek 余额接口 \(endpoint) 响应无法解析：\(detail)"
            case .unavailable(let endpoint):
                return "DeepSeek \(endpoint) 返回 is_available=false —— 账户余额不可用"
            case .noBalanceInfo(let endpoint):
                return "DeepSeek \(endpoint) 未返回 balance_infos"
            }
        }
    }

    /// 拉取余额并转换为与 Codex 弹窗兼容的 `RateLimitsSnapshot`。
    public func fetchBalance(now: Date = Date()) async throws -> RateLimitsSnapshot {
        let key = try loadAPIKey()
        var request = URLRequest(url: Self.balanceURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("TapgoAICoding/0.5.35", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        let endpoint = Self.balanceURL.path

        let (data, http) = try await send(request, endpoint: endpoint)
        guard (200..<300).contains(http.statusCode) else {
            throw QuotaError.http(status: http.statusCode, endpoint: endpoint)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaError.decoding("顶层不是 JSON object", endpoint: endpoint)
        }
        let available = (json["is_available"] as? Bool) ?? false
        guard available else {
            throw QuotaError.unavailable(endpoint: endpoint)
        }
        guard let infos = (json["balance_infos"] as? [[String: Any]]), !infos.isEmpty else {
            throw QuotaError.noBalanceInfo(endpoint: endpoint)
        }
        return Self.build(from: infos, now: now)
    }

    // MARK: - Snapshot mapping

    /// 取第一条 balance_info（官方语义：主币种余额）。
    static func build(from balanceInfos: [[String: Any]], now: Date) -> RateLimitsSnapshot {
        let info = balanceInfos.first ?? [:]
        let currency = (info["currency"] as? String) ?? ""
        let total = (info["total_balance"] as? String) ?? ""
        let balance = total.isEmpty ? "" : "¥\(total)\(currency.isEmpty ? "" : " \(currency)")"
        return RateLimitsSnapshot(
            primary: nil,
            secondary: nil,
            credits: RateLimitsCredits(hasCredits: true, unlimited: false, balance: balance),
            planType: nil,
            byLimitId: [],
            fetchedAt: now
        )
    }

    // MARK: - Private

    private func loadAPIKey() throws -> String {
        if let apiKey, !apiKey.isEmpty { return apiKey }
        guard FileManager.default.fileExists(atPath: authPath.path) else {
            throw QuotaError.missingAuthFile(authPath.path)
        }
        guard let data = try? Data(contentsOf: authPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["OPENAI_API_KEY"] as? String,
              !key.isEmpty
        else {
            throw QuotaError.missingKey
        }
        return key
    }

    private func send(_ request: URLRequest, endpoint: String) async throws -> (Data, HTTPURLResponse) {
        if let override = _transportOverride {
            return try await override(request)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QuotaError.decoding("响应不是 HTTPURLResponse", endpoint: endpoint)
        }
        return (data, http)
    }
}
