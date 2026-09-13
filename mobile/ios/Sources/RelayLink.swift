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
