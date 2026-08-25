import Foundation

/// Minimal client for reusing the OctTapgo admin **WeChat website QR login**
/// (Path A). The macOS app talks to the same Laravel backend that the
/// `admin-mac` client uses — it only needs the `login-url` / `login-status`
/// endpoints to drive its own QR scanner, and `me` to validate/restore a
/// session token. Everything else lives on the backend.
///
/// Backend facts (from `admin/app/Http/Controllers/Admin/Api/V1/AuthController.php`):
///   - `GET /api/admin/v1/auth/wechat/login-url` returns `{ js_config: { appid,
///     scope, redirect_uri, state }, ... }`; we build the `open.weixin.qq.com`
///     qrconnect URL from it.
///   - `GET /api/admin/v1/auth/wechat/login-status?state=…` returns
///     `{ status: "waiting|confirmed|need_bind|expired", token?, user? }`.
///   - `GET /api/admin/mac/v1/me` returns the current admin user.
struct AdminLoginClient {
    /// Default base host for the reused OctTapgo backend.
    static let defaultBaseURLString = "https://pay.itapgo.com"
    let baseURL: URL

    init(baseURLString: String? = nil) {
        let trimmed = baseURLString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved = (trimmed.isEmpty ? Self.defaultBaseURLString : trimmed)
        // Clean a potential trailing slash so path concatenation is stable.
        let normalized = resolved.hasSuffix("/") ? String(resolved.dropLast()) : resolved
        self.baseURL = URL(string: normalized) ?? URL(string: Self.defaultBaseURLString)!
    }

    // MARK: - WeChat QR login

    /// Fetches the qrconnect URL + polling `state` from the backend.
    func fetchWechatLoginURL() async throws -> (url: URL, state: String) {
        let endpoint = try wechatLoginEndpoint()
        let (data, http) = try await get(endpoint, token: nil)
        try Self.assertOK(http)

        let envelope = try JSONDecoder().decode(WechatLoginUrlEnvelope.self, from: data)
        guard envelope.code == 0 || envelope.code == 200 else {
            throw AdminLoginError.business(envelope.message ?? "获取微信登录配置失败")
        }
        guard let data = envelope.data,
              let loginURL = data.loginURL,
              let state = data.state, !state.isEmpty else {
            throw AdminLoginError.incompleteConfig
        }
        return (loginURL, state)
    }

    /// One status snapshot for a given polling `state`.
    func pollWechatLoginStatus(state: String) async throws -> AdminWechatStatus {
        let endpoint = try wechatLoginStatusEndpoint(state: state)
        let (data, http) = try await get(endpoint, token: nil)
        try Self.assertOK(http)

        let envelope = try JSONDecoder().decode(WechatLoginStatusEnvelope.self, from: data)
        guard envelope.code == 0 || envelope.code == 200 else {
            throw AdminLoginError.business(envelope.message ?? "微信登录状态异常")
        }
        guard let statusData = envelope.data else {
            return .waiting
        }

        switch statusData.status {
        case "confirmed":
            guard let token = statusData.token, !token.isEmpty else {
                throw AdminLoginError.incompleteConfig
            }
            return .confirmed(token: token, user: statusData.user)
        case "need_bind":
            return .needBind(message: envelope.message ?? "该微信尚未绑定管理员账号")
        case "expired":
            return .expired
        case "waiting", "create", "scan", "scanned", "confirmed_scan":
            return .waiting
        default:
            return .unknown(statusData.status)
        }
    }

    // MARK: - Session validation

    /// Validates a stored Bearer token and returns the admin user. Throws
    /// `AdminLoginError.unauthorized` when the token is no longer valid.
    func me(token: String) async throws -> AdminUser {
        let endpoint = try meEndpoint()
        let (data, http) = try await get(endpoint, token: token)
        if http.statusCode == 401 { throw AdminLoginError.unauthorized }
        try Self.assertOK(http)

        let envelope = try JSONDecoder().decode(MeEnvelope.self, from: data)
        guard envelope.code == 0 || envelope.code == 200 else {
            throw AdminLoginError.business(envelope.message ?? "获取用户信息失败")
        }
        guard let user = envelope.data?.user else {
            throw AdminLoginError.emptyUser
        }
        return user
    }

    // MARK: - Endpoints

    private func wechatLoginEndpoint() throws -> URL {
        try endpoint("/api/admin/v1/auth/wechat/login-url")
    }

    private func wechatLoginStatusEndpoint(state: String) throws -> URL {
        var components = URLComponents(url: try endpoint("/api/admin/v1/auth/wechat/login-status"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "state", value: state)]
        guard let url = components?.url else { throw AdminLoginError.invalidURL }
        return url
    }

    private func meEndpoint() throws -> URL {
        try endpoint("/api/admin/mac/v1/me")
    }

    private func endpoint(_ path: String) throws -> URL {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw AdminLoginError.invalidURL
        }
        return url
    }

    // MARK: - HTTP

    private func get(_ url: URL, token: String?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AdminLoginError.invalidResponse
        }
        return (data, http)
    }

    private static func assertOK(_ http: HTTPURLResponse) throws {
        guard (200..<300).contains(http.statusCode) else {
            throw AdminLoginError.server(status: http.statusCode)
        }
    }
}

// MARK: - Models

struct AdminUser: Codable, Equatable, Identifiable {
    let id: Int
    let username: String
    let name: String?
    let email: String?
    let phone: String?
    let avatar: String?
    let wechatAvatar: String?
    let wechatNickname: String?
    let role: String?
    let displayAvatar: String?

    enum CodingKeys: String, CodingKey {
        case id, username, name, email, phone, avatar, role
        case wechatAvatar = "wechat_avatar"
        case wechatNickname = "wechat_nickname"
        case displayAvatar = "display_avatar"
    }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? username : trimmed
    }

    var roleText: String {
        switch role {
        case "super_admin": return "超级管理员"
        case "admin":       return "系统管理员"
        case "operator":    return "运营管理员"
        case .some(let value) where !value.isEmpty: return value
        default:            return "管理员"
        }
    }

    /// Best available avatar URL: backend `display_avatar`, then the WeChat
    /// avatar, then the plain `avatar` field. Empty strings are skipped.
    var avatarURL: URL? {
        [displayAvatar, wechatAvatar, avatar]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            .flatMap(URL.init(string:))
    }
}

enum AdminWechatStatus: Equatable {
    case waiting
    case confirmed(token: String, user: AdminUser?)
    case needBind(message: String)
    case expired
    case unknown(String)
}

enum AdminLoginError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(status: Int)
    case business(String)
    case incompleteConfig
    case emptyUser
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:      return "微信登录接口地址无效"
        case .invalidResponse: return "微信登录服务响应无效"
        case .server(let status): return "微信登录服务异常：\(status)"
        case .business(let message): return message
        case .incompleteConfig: return "微信登录配置不完整"
        case .emptyUser:       return "登录成功但无法读取账号信息"
        case .unauthorized:    return "登录已过期，请重新登录"
        }
    }
}

// MARK: - Envelopes

private struct ApiEnvelope<T: Decodable>: Decodable {
    let code: Int
    let message: String?
    let data: T?
}

private struct WechatLoginUrlEnvelope: Decodable {
    let code: Int
    let message: String?
    let data: WechatLoginUrlData?
}

private struct WechatLoginUrlData: Decodable {
    let qrcodeURL: String?
    let jsConfig: WechatJSConfig?
    let rawState: String?

    enum CodingKeys: String, CodingKey {
        case qrcodeURL = "qrcode_url"
        case jsConfig = "js_config"
        case rawState = "state"
    }

    var state: String? { jsConfig?.state ?? rawState }

    /// Builds the WeChat website login URL. Prefers an explicit `qrcode_url`;
    /// otherwise assembles the official `open.weixin.qq.com/connect/qrconnect`
    /// URL from the `js_config` parameters (matching `admin-mac`'s logic).
    var loginURL: URL? {
        if let qrcodeURL, let url = URL(string: qrcodeURL) { return url }
        guard let jsConfig else { return nil }

        var components = URLComponents(string: "https://open.weixin.qq.com/connect/qrconnect")
        components?.queryItems = [
            URLQueryItem(name: "appid", value: jsConfig.appid),
            URLQueryItem(name: "redirect_uri", value: jsConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: jsConfig.scope),
            URLQueryItem(name: "state", value: jsConfig.state),
        ]
        guard let baseURL = components?.url else { return nil }
        return URL(string: baseURL.absoluteString + "#wechat_redirect")
    }
}

private struct WechatJSConfig: Decodable {
    let appid: String
    let redirectURI: String
    let scope: String
    let state: String

    enum CodingKeys: String, CodingKey {
        case appid
        case redirectURI = "redirect_uri"
        case scope
        case state
    }
}

private struct WechatLoginStatusEnvelope: Decodable {
    let code: Int
    let message: String?
    let data: WechatLoginStatusData?
}

private struct WechatLoginStatusData: Decodable {
    let status: String
    let token: String?
    let user: AdminUser?
}

private struct MeEnvelope: Decodable {
    let code: Int
    let message: String?
    let data: MePayload?
}

private struct MePayload: Decodable {
    let user: AdminUser?
    let abilities: [String]?
}
