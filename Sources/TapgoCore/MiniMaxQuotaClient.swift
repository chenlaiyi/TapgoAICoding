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
        case http(status: Int, endpoint: String)
        case business(code: Int, message: String, endpoint: String)
        case decoding(String, endpoint: String)
        case noMatchingModel(requested: String, returned: [String], endpoint: String)
        case emptyResponse(endpoint: String)

        var errorDescription: String? {
            switch self {
            case .missingAuthFile(let path):
                return "未找到 MiniMax 凭据文件：\(path)"
            case .missingKey:
                return "auth.json 中缺少 OPENAI_API_KEY，无法查询 MiniMax 额度"
            case .http(let status, let endpoint):
                return "MiniMax 额度接口 \(endpoint) HTTP \(status)"
            case .business(let code, let message, let endpoint):
                return "MiniMax 额度接口 \(endpoint) 返回错误：\(code) \(message)"
            case .decoding(let detail, let endpoint):
                return "MiniMax 额度接口 \(endpoint) 响应无法解析：\(detail)"
            case .noMatchingModel(let requested, let returned, let endpoint):
                let listed = returned.isEmpty ? "（接口未返回任何 model_remains 条目）" : "（接口返回的模型名：\(returned.joined(separator: ", "))）"
                return "MiniMax \(endpoint) 未匹配到 \(requested)\(listed)"
            case .emptyResponse(let endpoint):
                return "MiniMax \(endpoint) 返回的 model_remains 为空 —— 该账号可能没有 MiniMax-M3 的订阅"
            }
        }
    }

    /// 拉取本客户端订阅账户在 `modelName` 上的剩余额度，转换为与 Codex
    /// 弹窗兼容的 `RateLimitsSnapshot`。
    public func fetchRemains(now: Date = Date()) async throws -> RateLimitsSnapshot {
        let key = try loadAPIKey()
        // 国内 MiniMax 公开两条查询路径, schema 略有差异。
        // 先试 `/api/openplatform/coding_plan/remains`, 匹配失败或空响应
        // 时再退到 `/token_plan/remains`。
        let endpoints: [String] = [
            "/api/openplatform/coding_plan/remains",
            "/token_plan/remains"
        ]
        var lastNoMatch: QuotaError?
        for path in endpoints {
            do {
                let request = try buildRequest(apiKey: key, path: path)
                let (data, http) = try await send(request, endpoint: path)
                guard (200..<300).contains(http.statusCode) else {
                    throw QuotaError.http(status: http.statusCode, endpoint: path)
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw QuotaError.decoding("顶层不是 JSON object", endpoint: path)
                }
                if let baseResp = json["base_resp"] as? [String: Any] {
                    let statusCode = (baseResp["status_code"] as? Int) ?? 0
                    if statusCode != 0 {
                        let msg = (baseResp["status_msg"] as? String) ?? "unknown"
                        throw QuotaError.business(code: statusCode, message: msg, endpoint: path)
                    }
                }
                let modelRemains = (json["model_remains"] as? [[String: Any]]) ?? []
                if modelRemains.isEmpty {
                    lastNoMatch = .emptyResponse(endpoint: path)
                    continue
                }
                let returned = modelRemains.compactMap { $0["model_name"] as? String }
                if let entry = pickEntry(modelRemains, for: modelName) {
                    return MiniMaxQuotaSnapshotBuilder.build(from: entry, now: now)
                }
                lastNoMatch = .noMatchingModel(requested: modelName, returned: returned, endpoint: path)
            } catch let err as QuotaError {
                // 「未匹配模型」/「空响应」不算硬失败: 换端点还有救。
                // 其他错误 (HTTP 4xx/5xx、business 1008) 与端点无关, 立即抛。
                switch err {
                case .noMatchingModel, .emptyResponse:
                    lastNoMatch = err
                    continue
                default:
                    throw err
                }
            }
        }
        // 两个端点都试过都没匹配 —— 抛出最后一个端点的诊断信息。
        throw lastNoMatch ?? .emptyResponse(endpoint: "(none)")
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

    private func buildRequest(apiKey: String, path: String) throws -> URLRequest {
        guard let url = URL(string: region.baseURL.absoluteString + path) else {
            throw QuotaError.decoding("无法构造额度接口 URL", endpoint: path)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("TapgoAICoding/0.5.25", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 8
        return req
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

    /// 选取目标模型的条目。MiniMax 把所有模型按 quota 分桶返回，
    /// `model_name` 字段不是模型名而是 quota 类别：
    ///   - 文本/对话模型（MiniMax-M3 / M2.7 / abab6.5s-chat）  → "general"
    ///   - 视频模型                                         → "video"
    ///   - 语音模型                                         → "speech" / "audio"
    ///
    /// 我们的目标模型名是 MiniMax-M3（文本），所以优先匹配 `model_name == "general"`。
    /// 同时为一些意外命名（开发临时把模型塞到"general" 之外的桶里）保留多轮 fallback。
    ///
    /// 匹配顺序：
    ///   1. 目标模型 → 已知 quota 类别（text 模型 → "general"）
    ///   2. 完全相等（万一以后接口直接返回模型名）
    ///   3. 大小写不敏感相等
    ///   4. 去分隔符后相等
    ///   5. 去分隔符后互相包含
    ///   6. 单条目通配兜底
    private func pickEntry(_ entries: [[String: Any]], for model: String) -> [String: Any]? {
        let normalized = Self.normalize(model)

        // 1. 文本/对话模型 → "general" 桶
        if Self.isTextOrChatModel(model) {
            if let hit = entries.first(where: { ($0["model_name"] as? String) == "general" }) {
                return hit
            }
        }
        // 1b. 视频模型 → "video" 桶
        if Self.isVideoModel(model) {
            if let hit = entries.first(where: { ($0["model_name"] as? String) == "video" }) {
                return hit
            }
        }

        // 2. exact
        if let hit = entries.first(where: { ($0["model_name"] as? String) == model }) { return hit }
        // 3. case-insensitive exact
        if let hit = entries.first(where: {
            guard let n = $0["model_name"] as? String else { return false }
            return n.lowercased() == model.lowercased()
        }) { return hit }
        // 4. separator-insensitive exact
        if let hit = entries.first(where: {
            guard let n = $0["model_name"] as? String else { return false }
            return Self.normalize(n) == normalized
        }) { return hit }
        // 5. separator-insensitive contains (双向)
        if let hit = entries.first(where: {
            guard let n = $0["model_name"] as? String else { return false }
            let nn = Self.normalize(n)
            return nn.contains(normalized) || normalized.contains(nn)
        }) { return hit }
        // 6. 实在没匹配: 单条直接通配（避免因字段小差异丢数据）
        if entries.count == 1 { return entries[0] }
        return nil
    }

    /// 是否是 MiniMax 文本/对话模型。匹配 MiniMax-M3 / M2.7 / abab* / minimax-text 之类。
    private static func isTextOrChatModel(_ name: String) -> Bool {
        let n = name.lowercased()
        // 显式包含文本/对话关键词
        if n.contains("chat") || n.contains("text") || n.contains("abab") || n.contains("turbo") {
            return true
        }
        // MiniMax 自家模型名: MiniMax-M*, M2/M2.7/M3, MiniMax-Text 等
        // 走 normalize 后看是否含 "minimax" 或以 "m" 开头接数字
        let stripped = normalize(name)
        if stripped.contains("minimax") { return true }
        return false
    }

    /// 是否是 MiniMax 视频生成模型。
    private static func isVideoModel(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("video") || n.contains("t2v") || n.contains("i2v")
    }

    private static func normalize(_ s: String) -> String {
        // 去空格/连字符/下划线/点/斜杠，统一小写，方便比较。
        let separators: Set<Character> = [" ", "-", "_", ".", "/"]
        return s.lowercased().filter { !separators.contains($0) }
    }
}

// 注：MiniMax → RateLimitsSnapshot 的字段反转（remaining → usedPercent）已在
// TapgoCore.MiniMaxQuotaSnapshotBuilder 里实现，这里只负责 HTTP 拉取与错误归集。
