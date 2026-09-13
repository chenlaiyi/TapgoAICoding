import Foundation

/// 公网中继传输层 (v1.0.5): 走 pay.itapgo.com 加密中继, 任意网络可用。
///
/// Mac 端已有 H5 公网链路: https://pay.itapgo.com/remote/<user>/r/<token>
/// 原生 App 复用同一 token 鉴权, 新增 /api/native/projects 端点。
@MainActor
final class RelayLink: ObservableObject {
    static let baseURLKey = "tapgo.relay.baseURL"

    @Published private(set) var lastError: String?
    @Published private(set) var isCheckedOK = false

    /// 例: https://pay.itapgo.com/remote/fafa/r/<token>
    private(set) var baseURL: URL?

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.baseURLKey),
           let url = URL(string: raw) {
            baseURL = url
        }
    }

    var isConfigured: Bool { baseURL != nil }

    func configure(fromScannedText text: String) -> Bool {
        // 接受完整 relay 链接 (扫码 H5 二维码)。
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.path.contains("/r/") else { return false }
        baseURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: Self.baseURLKey)
        return true
    }

    func clear() {
        baseURL = nil
        UserDefaults.standard.removeObject(forKey: Self.baseURLKey)
        isCheckedOK = false
    }

    /// GET /api/native/projects → 项目分组 JSON (结构与局域网 listProjects 相同)。
    func fetchProjects() async throws -> MobileRemoteLink.Params {
        guard let base = baseURL else { throw URLError(.badURL) }
        var req = URLRequest(url: base.appendingPathComponent("api/native/projects"))
        req.timeoutInterval = 12
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        isCheckedOK = true
        return try JSONDecoder().decode(MobileRemoteLink.Params.self, from: data)
    }

    /// GET /api/state 解析 model + models (Codex 移动端模型选择数据源)。
    func fetchState() async throws -> (current: String, options: [ModelOption]) {
        guard let base = baseURL else { throw URLError(.badURL) }
        let data = try await URLSession.shared.data(from: base.appendingPathComponent("api/state")).0
        struct R: Decodable {
            struct ModelOpt: Decodable {
                let providerId: String; let providerName: String
                let modelId: String; let modelName: String
                let configured: Bool?; let selected: Bool?
            }
            let model: String?; let models: [ModelOpt]?
        }
        let r = try JSONDecoder().decode(R.self, from: data)
        return (r.model ?? "", (r.models ?? []).map {
            ModelOption(providerId: $0.providerId, providerName: $0.providerName,
                        modelId: $0.modelId, modelName: $0.modelName,
                        configured: $0.configured ?? false, selected: $0.selected ?? false)
        })
    }

    /// POST /api/model {providerId, modelId}。
    func selectModel(providerId: String, modelId: String) async throws {
        guard let base = baseURL else { throw URLError(.badURL) }
        var req = URLRequest(url: base.appendingPathComponent("api/model"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject:
            ["providerId": providerId, "modelId": modelId])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    /// POST /api/send。
    func send(text: String) async throws {
        guard let base = baseURL else { throw URLError(.badURL) }
        var req = URLRequest(url: base.appendingPathComponent("api/send"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }
}


struct ModelOption: Identifiable, Hashable {
    var id: String { providerId + ":" + modelId }
    let providerId: String
    let providerName: String
    let modelId: String
    let modelName: String
    let configured: Bool
    let selected: Bool
}
