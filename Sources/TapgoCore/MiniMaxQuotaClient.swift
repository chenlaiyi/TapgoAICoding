import Foundation

/// 读取 MiniMax（MiniMax-M3 背后的厂商）官方 Token Plan / Coding Plan 剩余额度。
///
/// 原实现误用了 Codex app-server 的 `account/rateLimits/read`，但本 App 的对话模型
/// 是 MiniMax-M3，由 `https://api.minimaxi.com` 提供；Codex 那条 JSON-RPC 永远返回
/// 不到真实订阅数据，因此弹窗里的 "5 小时 / 每周 / Credits" 一直是错的。
///
/// MiniMax 官方提供的剩余额度查询（Token Plan 订阅）：
///   - 国内：`GET https://www.minimaxi.com/v1/api/openplatform/coding_plan/remains`
///   - 海外：`GET https://api.minimax.io/v1/api/openplatform/coding_plan/remains`
///   - Header：`Authorization: Bearer <Token Plan Key>`（通常 `sk-cp-` 开头，与
///     auth.json 里 `OPENAI_API_KEY` 字段共用同一把 key）。
///
/// 响应字段（MiniMax 官方 schema）：
///   {
///     "base_resp": { "status_code": 0, "status_msg": "success" },
///     "model_remains": [
///       {
///         "model_name": "MiniMax-M3",
///         "current_interval_total_count": 4500,
///         "current_interval_usage_count": 404,        // ⚠️ 这是「剩余」, 不是「已用」
///         "current_weekly_total_count": 0,
///         "current_weekly_usage_count": 0,
///         "end_time": 1756660800,                      // 周期重置时间 (秒)
///         "remains_time": 123456789,                  // 距重置的毫秒数 (备用)
///         "plan_name": "Plus"                          // 订阅等级
///       }
///     ]
///   }
///
/// 字段陷阱：`current_interval_usage_count` 与 `current_weekly_usage_count`
/// 字面是 "usage"，但实际语义是「本周期还剩多少次」；真正的「已用次数」要由
/// `total - remaining` 反算得到。本客户端负责完成这个转换。
///
/// 端点选择遵循 `TapgoConfig.Region`：
///   - `.china` → `www.minimaxi.com`（默认）
///   - 其它区域以后再扩展
public struct MiniMaxQuotaClient {
    public enum Region {
        case china
        case overseas

        public var baseURL: URL {
            switch self {
            case .china:    return URL(string: "https://www.minimaxi.com/v1")!
            case .overseas: return URL(string: "https://api.minimax.io/v1")!
            }
        }
    }

    public let region: Region
    public let authPath: URL
    public let modelName: String
    let session: URLSession
    /// 仅测试用：替换 `URLSession` 让解析逻辑在不依赖网络的情况下验证。
    private let _transportOverride: ((URLRequest) async throws -> (Data, HTTPURLResponse))?

    public init(
        region: Region = .china,
        authPath: URL,
        modelName: String,
        session: URLSession = .shared
    ) {
        self.region = region
        self.authPath = authPath
        self.modelName = modelName
        self.session = session
        self._transportOverride = nil
    }

    /// 仅供单元测试使用：传入一个固定的 transport 闭包。
    init(
        region: Region,
        authPath: URL,
        modelName: String,
        transport: @escaping (URLRequest) async throws -> (Data, HTTPURLResponse)
    ) {
        self.region = region
        self.authPath = authPath
        self.modelName = modelName
        self.session = URLSession.shared
        self._transportOverride = transport
    }

    // MARK: - Public

    enum QuotaError: LocalizedError {
        case missingAuthFile(String)
        case missingKey
        case http(status: Int)
        case business(code: Int, message: String)
        case decoding(String)
        case noMatchingModel(String)

        var errorDescription: String? {
            switch self {
            case .missingAuthFile(let path):
                return "未找到 MiniMax 凭据文件：\(path)"
            case .missingKey:
                return "auth.json 中缺少 OPENAI_API_KEY，无法查询 MiniMax 额度"
            case .http(let status):
                return "MiniMax 额度接口 HTTP \(status)"
            case .business(let code, let message):
                return "MiniMax 额度接口返回错误：\(code) \(message)"
            case .decoding(let detail):
                return "MiniMax 额度接口响应无法解析：\(detail)"
            case .noMatchingModel(let name):
                return "MiniMax 额度接口未返回模型 \(name) 的数据"
            }
        }
    }

    /// 拉取本客户端订阅账户在 `modelName` 上的剩余额度，转换为与 Codex
    /// 弹窗兼容的 `RateLimitsSnapshot`。
    public func fetchRemains(now: Date = Date()) async throws -> RateLimitsSnapshot {
        let key = try loadAPIKey()
        let request = try buildRequest(apiKey: key)
        let (data, http) = try await send(request)
        guard (200..<300).contains(http.statusCode) else {
            throw QuotaError.http(status: http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaError.decoding("顶层不是 JSON object")
        }
        // MiniMax 在业务失败时也会回 200, 但 base_resp.status_code != 0。
        if let baseResp = json["base_resp"] as? [String: Any] {
            let statusCode = (baseResp["status_code"] as? Int) ?? 0
            if statusCode != 0 {
                let msg = (baseResp["status_msg"] as? String) ?? "unknown"
                throw QuotaError.business(code: statusCode, message: msg)
            }
        }
        let modelRemains = (json["model_remains"] as? [[String: Any]]) ?? []
        guard let entry = pickEntry(modelRemains, for: modelName) else {
            throw QuotaError.noMatchingModel(modelName)
        }
        return MiniMaxQuotaSnapshotBuilder.build(from: entry, now: now)
    }

    // MARK: - Request

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

    private func buildRequest(apiKey: String) throws -> URLRequest {
        // `/v1/api/openplatform/coding_plan/remains`
        let path = "/api/openplatform/coding_plan/remains"
        guard let url = URL(string: region.baseURL.absoluteString + path) else {
            throw QuotaError.decoding("无法构造额度接口 URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("TapgoAICoding/0.5.25", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 8
        return req
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let override = _transportOverride {
            return try await override(request)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QuotaError.decoding("响应不是 HTTPURLResponse")
        }
        return (data, http)
    }

    /// 选取目标模型的条目。MiniMax 在 `model_remains` 数组里按模型分别返回，
    /// 大小写敏感。本客户端优先匹配完全相等，失败时退到大小写不敏感的包含。
    private func pickEntry(_ entries: [[String: Any]], for model: String) -> [String: Any]? {
        if let exact = entries.first(where: { ($0["model_name"] as? String) == model }) {
            return exact
        }
        if let fuzzy = entries.first(where: {
            guard let name = $0["model_name"] as? String else { return false }
            return name.lowercased().contains(model.lowercased())
        }) {
            return fuzzy
        }
        // 没有模型名匹配，但服务端只回了一条 —— 当作通配，用它兜底。
        if entries.count == 1 { return entries[0] }
        return nil
    }
}

// 注：MiniMax → RateLimitsSnapshot 的字段反转（remaining → usedPercent）已在
// TapgoCore.MiniMaxQuotaSnapshotBuilder 里实现，这里只负责 HTTP 拉取与错误归集。
