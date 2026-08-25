import Foundation
import Combine

/// Session state for the admin **scan-to-login** gate.
///
/// Follows this app's existing secret convention (see `TapgoConfig`): the
/// backend Bearer token is stored in a 0600 JSON file under the app's
/// Application Support dir — the same way the MiniMax key lives in `auth.json`.
/// We deliberately do **not** use Keychain: this repo avoids it for its
/// secrets (README), and ad-hoc codesigning + Keychain ACLs are fragile.
@MainActor
final class AdminAuthStore: ObservableObject {
    @Published private(set) var token: String?
    @Published private(set) var currentUser: AdminUser?
    @Published private(set) var isRestoring = false
    @Published var errorMessage: String?

    let client: AdminLoginClient

    private let tokenFileURL: URL
    private let fileManager: FileManager

    var isAuthenticated: Bool { token != nil && currentUser != nil }

    init(baseURLString: String? = nil, fileManager: FileManager = .default) {
        self.client = AdminLoginClient(baseURLString: baseURLString)
        self.fileManager = fileManager
        // ~/Library/Application Support/Tapgo AICoding/admin-auth.json
        self.tokenFileURL = TapgoConfig.codexHome
            .deletingLastPathComponent()
            .appendingPathComponent("admin-auth.json", isDirectory: false)
        self.token = Self.readToken(from: tokenFileURL, fileManager: fileManager)
    }

    /// On launch: if a token was persisted, validate it against `/me` so a
    /// revoked/expired session falls back to the login gate instead of being
    /// silently trusted. Only an `unauthorized` (401) response clears the
    /// session — a transient network/5xx error keeps the stored token and
    /// surfaces the problem so the user can re-scan.
    func bootstrap() async {
        guard token != nil else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            let t = try await tokenValue()
            currentUser = try await client.me(token: t)
            errorMessage = nil
        } catch AdminLoginError.unauthorized {
            clearSession()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Finalises a scan-to-login success: persist the token, then resolve the
    /// admin identity (either supplied by `login-status`, or via `/me`).
    @discardableResult
    func completeLogin(token newToken: String, user: AdminUser?) async throws -> AdminUser? {
        token = newToken
        do {
            try Self.writeToken(newToken, to: tokenFileURL, fileManager: fileManager)
        } catch {
            // Persistence must not block the session in-memory; surface but continue.
            NSLog("[AdminAuthStore] failed to persist token: \(error.localizedDescription)")
        }

        if let user {
            currentUser = user
            errorMessage = nil
            return user
        }
        let fetched = try await client.me(token: newToken)
        currentUser = fetched
        errorMessage = nil
        return fetched
    }

    func logout() {
        clearSession()
    }

    func clearSession() {
        token = nil
        currentUser = nil
        errorMessage = nil
        try? fileManager.removeItem(at: tokenFileURL)
    }

    func setError(_ message: String) {
        errorMessage = message
    }

    private func tokenValue() async throws -> String {
        guard let token, !token.isEmpty else { throw AdminLoginError.emptyUser }
        return token
    }

    // MARK: - Token file

    private static func tokenFile(_ fileManager: FileManager) -> URL {
        TapgoConfig.codexHome
            .deletingLastPathComponent()
            .appendingPathComponent("admin-auth.json", isDirectory: false)
    }

    private static func readToken(from url: URL, fileManager: FileManager) -> String? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = json["token"] as? String, !t.isEmpty else {
            return nil
        }
        return t
    }

    private static func writeToken(_ token: String, to url: URL, fileManager: FileManager) throws {
        let dir = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: ["token": token])
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
