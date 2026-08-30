// TapgoCore/GLMQuotaClient.swift
import Foundation

/// 读取 GLM（BigModel Coding Plan）官方套餐余量，归一化为
/// `RateLimitsSnapshot` 供额度弹窗与侧栏直接复用。
///
/// 端点与鉴权方式抄自智谱官方用量查询插件
/// （github.com/zai-org/zai-coding-plugins → glm-plan-usage → query-usage.mjs）：
/// `GET https://open.bigmodel.cn/api/monitor/usage/quota/limit`，
/// `Authorization` 头直接放 key（官方脚本用裸 token，实测带 Bearer 前缀同样收）。
/// 响应结构（2026-08-30 实测）：
///
///     {"code":200,"success":true,"data":{
///       "limits":[
///         {"type":"CREDIT_LIMIT","unit":3,"number":5,"usage":2000,
///          "currentValue":385,"remaining":1614,"percentage":19,
///          "nextResetTime":1788078085488},        // 5 小时档, 已用 19%
///         {"type":"CREDIT_LIMIT","unit":6,"number":1,"usage":10000,
///          "currentValue":6749,"remaining":3250,"percentage":67,
///          "nextResetTime":1788193554998}],       // 周档, 已用 67%
///       "level":"lite"}}                          // 套餐档位
///
/// `percentage` 是**已用**百分比，与 MiniMax 侧 `usedPercent` 语义一致。
public final class GLMQuotaClient {
    public static let quotaURL = URL(
        string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit")!

    public let authPath: URL
    let session: URLSession
    /// 仅测试用：替换 `URLSession` 让解析逻辑在不依赖网络的情况下验证。
    private let _transportOverride: ((URLRequest) async throws -> (Data, HTTPURLResponse))?

    public init(authPath: URL, session: URLSession = .shared) {
        self.authPath = authPath
        self.session = session
        self._transportOverride = nil
    }

    /// 仅供单元测试使用：传入一个固定的 transport 闭包。
    init(authPath: URL, transport: @escaping (URLRequest) async throws -> (Data, HTTPURLResponse)) {
        self.authPath = authPath
        self.session = URLSession.shared
        self._transportOverride = transport
    }

    // MARK: - Public

    enum QuotaError: LocalizedError {
        case missingAuthFile(String)
        case missingKey
        case http(status: Int, endpoint: String)
        case decoding(String, endpoint: String)
        case business(code: Int, message: String, endpoint: String)
        case emptyLimits(endpoint: String)

        var errorDescription: String? {
            switch self {
            case .missingAuthFile(let path):
                return "未找到 GLM 凭据文件：\(path)"
            case .missingKey:
                return "auth-glm.json 中缺少 OPENAI_API_KEY，无法查询 GLM 额度"
            case .http(let status, let endpoint):
                return "GLM 额度接口 \(endpoint) HTTP \(status)"
            case .decoding(let detail, let endpoint):
                return "GLM 额度接口 \(endpoint) 响应无法解析：\(detail)"
            case .business(let code, let message, let endpoint):
                return "GLM 额度接口 \(endpoint) 返回错误：\(code) \(message)"
            case .emptyLimits(let endpoint):
                return "GLM \(endpoint) 返回的 limits 为空 —— 该账号可能没有 Coding Plan 订阅"
            }
        }
    }

    /// 拉取套餐余量并转换为与 Codex 弹窗兼容的 `RateLimitsSnapshot`。
    public func fetchRemains(now: Date = Date()) async throws -> RateLimitsSnapshot {
        let key = try loadAPIKey()
        var request = URLRequest(url: Self.quotaURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(key, forHTTPHeaderField: "Authorization")
        request.setValue("TapgoAICoding/0.5.34", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        let endpoint = Self.quotaURL.path

        let (data, http) = try await send(request, endpoint: endpoint)
        guard (200..<300).contains(http.statusCode) else {
            throw QuotaError.http(status: http.statusCode, endpoint: endpoint)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaError.decoding("顶层不是 JSON object", endpoint: endpoint)
        }
        if let code = int(of: json["code"]), code != 200 {
            let msg = (json["msg"] as? String) ?? "unknown"
            throw QuotaError.business(code: code, message: msg, endpoint: endpoint)
        }
        guard let payload = json["data"] as? [String: Any] else {
            throw QuotaError.decoding("缺少 data 字段", endpoint: endpoint)
        }
        let limits = (payload["limits"] as? [[String: Any]]) ?? []
        guard !limits.isEmpty else {
            throw QuotaError.emptyLimits(endpoint: endpoint)
        }
        return Self.build(from: payload, now: now)
    }

    // MARK: - Snapshot mapping

    /// 把 `data` 载荷映射为快照。static 以便单测直接喂 fixture。
    static func build(from payload: [String: Any], now: Date) -> RateLimitsSnapshot {
        let limits = (payload["limits"] as? [[String: Any]]) ?? []
        var primary: RateLimitWindow?
        var secondary: RateLimitWindow?
        for entry in limits {
            // unit 3 = 小时, 6 = 周; number 是窗口长度。
            guard let unit = int(of: entry["unit"]), let number = int(of: entry["number"]) else {
                continue
            }
            let usedPercent = int(of: entry["percentage"]) ?? 0
            let resetsAtMs = double(of: entry["nextResetTime"])
            let window = RateLimitWindow(
                usedPercent: usedPercent,
                windowDurationMins: windowMins(unit: unit, number: number),
                resetsAt: resetsAtMs.map { Date(timeIntervalSince1970: $0 / 1000) }
            )
            if unit == 3 && primary == nil {
                primary = window
            } else if unit == 6 && secondary == nil {
                secondary = window
            }
        }
        let level = payload["level"] as? String
        return RateLimitsSnapshot(
            primary: primary,
            secondary: secondary,
            credits: nil,
            planType: level,
            byLimitId: [],
            fetchedAt: now
        )
    }

    /// unit 3 = 小时 → number×60 分钟; unit 6 = 周 → number×10080 分钟;
    /// 其它单位按小时兜底。
    static func windowMins(unit: Int, number: Int) -> Int {
        switch unit {
        case 6: return number * 10080
        default: return number * 60
        }
    }

    // MARK: - Private

    private func loadAPIKey() throws -> String {
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

/// JSONSerialization 的数字可能是 NSNumber（Int/Double 随机表现），统一桥接。
private func int(of any: Any?) -> Int? {
    guard let any else { return nil }
    if let v = any as? Int { return v }
    if let v = any as? Double { return Int(v) }
    return nil
}

private func double(of any: Any?) -> Double? {
    guard let any else { return nil }
    if let v = any as? Double { return v }
    if let v = any as? Int { return Double(v) }
    return nil
}
