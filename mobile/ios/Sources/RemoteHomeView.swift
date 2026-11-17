import SwiftUI
import UIKit
import WebKit

private struct RemoteSession: Decodable, Identifiable {
    let sessionId: String
    let cwd: String?
    let running: Bool
    let updatedAt: Double
    let projections: Projections?
    var draftTitle: String? = nil
    var id: String { sessionId }
    var title: String { draftTitle ?? projections?.values.title.flatMap { $0.isEmpty ? nil : $0 } ?? "未命名对话" }
    var project: String { cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "其他" }

    struct Projections: Decodable {
        let values: Values
    }
    struct Values: Decodable {
        let title: String?
    }
}

private struct SessionListResponse: Decodable {
    let result: ResultValue
    struct ResultValue: Decodable {
        let ok: Bool
        let value: Value?
        let error: Failure?
    }
    struct Value: Decodable { let items: [RemoteSession] }
    struct Failure: Decodable { let message: String }
}

private struct RemoteWorkspace: Decodable {
    let workspaceId: String?
    let path: String
    let title: String
    let sessionIds: [String]

    init(path: String, title: String, sessionIds: [String], workspaceId: String? = nil) {
        self.path = path
        self.title = title
        self.sessionIds = sessionIds
        self.workspaceId = workspaceId
    }
}

private struct RemoteDirectory: Decodable, Identifiable {
    let name: String
    let path: String
    let hidden: Bool
    var id: String { path }
}

private struct RemoteDirectoryListing: Decodable {
    let path: String
    let home: String
    let crumbs: [RemoteDirectory]
    let entries: [RemoteDirectory]
    let truncated: Bool
}

private struct ComposerModel: Identifiable {
    let provider: String
    let model: String
    let name: String
    let efforts: [MobileModelReasoning]
    let defaultEffort: String?

    /// Describes one route the new-conversation menu can start with.
    /// - Parameters:
    ///   - provider: provider id owning the route.
    ///   - model: adapter model id.
    ///   - name: display name reported by the Host.
    ///   - efforts: reasoning levels; empty when the route offers none.
    ///   - defaultEffort: level the Host applies when a selection omits one.
    init(provider: String, model: String, name: String,
         efforts: [MobileModelReasoning] = [], defaultEffort: String? = nil) {
        self.provider = provider
        self.model = model
        self.name = name
        self.efforts = efforts
        self.defaultEffort = defaultEffort
    }

    var id: String { "\(provider)/\(model)" }
    var shortName: String { mobileModelDisplayName(name, modelID: model, provider: provider) }
}

func mobileModelDisplayName(_ name: String, modelID: String, provider: String) -> String {
    "\(mobileModelShortName(name, modelID: modelID)) · \(provider == "deepseek-account" ? "账号" : "API")"
}

private func mobileModelShortName(_ name: String, modelID: String) -> String {
    let words = name.split(whereSeparator: { $0.isWhitespace })
    if let version = words.firstIndex(where: { word in
        let text = word.lowercased()
        return text.hasPrefix("v") && text.dropFirst().first?.isNumber == true
    }) {
        return words[version...].joined(separator: " ")
    }
    let parts = modelID.split(separator: "-").map(String.init)
    let modelParts = parts.first?.lowercased() == "deepseek" ? parts.dropFirst() : parts[...]
    return modelParts.map { part in
        part.first?.lowercased() == "v" && part.dropFirst().first?.isNumber == true
            ? part.uppercased() : part.capitalized
    }.joined(separator: " ")
}

private struct WorkspaceBaseline: Decodable {
    let items: [RemoteWorkspace]
    let pinnedSessionIds: [String]
}

private struct WorkspaceFrame: Decodable {
    let type: String
    let streamId: String
    let value: WorkspaceValue?
    struct WorkspaceValue: Decodable {
        let type: String
        let value: WorkspaceBaseline?
    }
}

@MainActor
private final class RemoteSessions: ObservableObject {
    @Published var items: [RemoteSession] = []
    @Published var loading = false
    @Published var error: String?
    @Published var lastConnectedAt: Date?
    @Published var workspaces: [RemoteWorkspace] = []
    @Published var pinnedSessionIds: [String] = []
    @Published var starting = false
    @Published var startError: String?
    @Published var models: [ComposerModel] = []
    @Published var defaultModel: String?
    @Published var funds = MobileBalanceSnapshot()
    var balance: String? { funds.account }
    private var fundsOrigin: String?
    private var balanceRevision = UUID()
    private var loadToken: UUID?
    private var consecutiveFailures = 0
    /// Whether the last load failed because the route itself was unreachable.
    private(set) var transportUnreachable = false
    /// The last first message this iPhone may already have delivered, so a retry of the same draft reuses its id.
    private var pendingStart: MobilePendingSubmission?

    /// Reads the session list once.
    /// - Parameters:
    ///   - computer: paired computer whose active route to dial.
    ///   - quietly: suppress the loading indicator for background refreshes.
    /// - Returns: `true` when the Host answered with a session list.
    @discardableResult
    func load(computer: SavedComputer, quietly: Bool = false) async -> Bool {
        if fundsOrigin != computer.id {
            funds = MobileBalanceSnapshot()
            fundsOrigin = computer.id
            balanceRevision = UUID()
            loadToken = nil
        }
        if loadToken != nil { return false }
        let token = UUID()
        loadToken = token
        defer { if loadToken == token { loadToken = nil } }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--dsh-mobile-test-sessions"),
           arguments.indices.contains(index + 1),
           let data = arguments[index + 1].data(using: .utf8),
           let fixture = try? JSONDecoder().decode([RemoteSession].self, from: data) {
            items = fixture
            applyModelCatalog(["groups": [["id": "deepseek-account", "models": [
                ["id": "deepseek-v41-flash", "name": "DeepSeek Official V41 Flash"]
            ]]], "default": ["provider": "deepseek-account", "model": "deepseek-v41-flash"]])
            if let index = arguments.firstIndex(of: "--dsh-mobile-test-balance"),
               arguments.indices.contains(index + 1) {
                let recharge = Decimal(string: arguments[index + 1]) ?? 0
                let bonus = arguments.firstIndex(of: "--dsh-mobile-test-bonus")
                    .flatMap { arguments.indices.contains($0 + 1) ? Decimal(string: arguments[$0 + 1]) : nil } ?? 0
                funds.account = Self.formatBalance(recharge + bonus)
                if let index = arguments.firstIndex(of: "--dsh-mobile-test-api-balance"), arguments.indices.contains(index + 1) {
                    funds.providers["deepseek-official"] = "¥" + arguments[index + 1]
                    models.append(ComposerModel(provider: "deepseek-official", model: "deepseek-chat", name: "DeepSeek V41 Flash"))
                }
            }
            if let pinsIndex = arguments.firstIndex(of: "--dsh-mobile-test-pins"),
               arguments.indices.contains(pinsIndex + 1) {
                pinnedSessionIds = arguments[pinsIndex + 1].split(separator: ",").map(String.init)
            }
            error = nil
            lastConnectedAt = .now
            return true
        }
        #endif
        guard let url = URL(string: computer.connectionURL), let origin = URL(string: computer.origin) else {
            return false
        }
        if !quietly { loading = true }
        defer { if !quietly { loading = false } }
        do {
            let configuration = URLSessionConfiguration.default
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpShouldSetCookies = true
            let cookies = await withCheckedContinuation { continuation in
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies {
                    continuation.resume(returning: $0)
                }
            }
            for cookie in cookies where cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == origin.host {
                configuration.httpCookieStorage?.setCookie(cookie)
            }
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            var request = URLRequest(url: origin.appendingPathComponent("api/session/list"))
            request.httpMethod = "POST"
            request.timeoutInterval = 8
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "type": "client-request",
                "rpcId": UUID().uuidString,
                "method": "session/list",
                "payload": ["args": ["_request": [:]]]
            ])
            var (data, response) = try await session.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 401 {
                let (_, authentication) = try await session.data(from: url)
                if (authentication as? HTTPURLResponse)?.statusCode == 401 {
                    throw RemoteError.pairingExpired
                }
                guard (authentication as? HTTPURLResponse)?.statusCode == 200 else {
                    throw RemoteError.unavailable
                }
                (data, response) = try await session.data(for: request)
            }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw RemoteError.unavailable
            }
            let decoded = try JSONDecoder().decode(SessionListResponse.self, from: data)
            guard decoded.result.ok, let value = decoded.result.value else {
                throw RemoteError.server(decoded.result.error?.message ?? "请求失败")
            }
            guard loadToken == token, fundsOrigin == computer.id else { return false }
            items = value.items.filter { $0.cwd != nil }
            error = nil
            consecutiveFailures = 0
            transportUnreachable = false
            lastConnectedAt = .now
            if let baseline = try? await readWorkspaces(session: session, origin: origin) {
                workspaces = baseline.items
                pinnedSessionIds = baseline.pinnedSessionIds
            }
            await loadComposerSettings(session: session, origin: origin, computerID: computer.id)
            return true
        } catch {
            transportUnreachable = MobileFailover.isRouteFailure(error)
            guard loadToken == token, fundsOrigin == computer.id else { return false }
            consecutiveFailures += 1
            if !quietly || consecutiveFailures >= 2 {
                lastConnectedAt = nil
                self.error = "无法读取这台 Mac 的对话：\(error.localizedDescription)"
            }
            return false
        }
    }

    /// Runs one Remote action against the paired Host with the stored pairing cookie.
    /// - Parameters:
    ///   - method: Remote endpoint, such as `session/rename`.
    ///   - arguments: endpoint arguments.
    ///   - computer: paired computer whose active route is dialed.
    /// - Returns: the endpoint value.
    private func perform(_ method: String, arguments: [String: Any], computer: SavedComputer) async throws -> Any {
        guard let origin = URL(string: computer.origin), let pairing = URL(string: computer.connectionURL) else {
            throw RemoteError.unavailable
        }
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = true
        let cookies = await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies {
                continuation.resume(returning: $0)
            }
        }
        for cookie in cookies where cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == origin.host {
            configuration.httpCookieStorage?.setCookie(cookie)
        }
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            return try await rpcValue(session: session, origin: origin, method: method, args: arguments)
        } catch {
            // The pairing cookie may have expired; renew it once and replay the action.
            var pairingRequest = URLRequest(url: pairing)
            pairingRequest.timeoutInterval = 8
            let (_, authentication) = try await session.data(for: pairingRequest)
            guard (authentication as? HTTPURLResponse)?.statusCode == 200 else { throw error }
            return try await rpcValue(session: session, origin: origin, method: method, args: arguments)
        }
    }

    /// Renames one conversation and refreshes the list.
    /// - Parameters:
    ///   - item: conversation to rename.
    ///   - title: new title; surrounding whitespace is ignored.
    ///   - computer: paired computer.
    /// - Returns: an error message, or nil when the Host accepted the title.
    func rename(_ item: RemoteSession, to title: String, computer: SavedComputer) async -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 120 else { return "对话名称需为 1–120 个字符" }
        do {
            _ = try await perform("session/rename", arguments: ["request": [
                "sessionId": item.sessionId, "title": trimmed,
            ]], computer: computer)
            await load(computer: computer)
            return nil
        } catch {
            return "重命名失败，请重试"
        }
    }

    /// Pins or unpins one conversation and adopts the Host's pinned order.
    /// - Parameters:
    ///   - item: conversation to change.
    ///   - pinned: whether it should be pinned.
    ///   - computer: paired computer.
    /// - Returns: an error message, or nil on success.
    func setPinned(_ item: RemoteSession, pinned: Bool, computer: SavedComputer) async -> String? {
        do {
            let value = try await perform(pinned ? "workspace/pinSession" : "workspace/unpinSession",
                                          arguments: ["request": ["sessionId": item.sessionId]], computer: computer)
            if let value = value as? [String: Any], let ids = value["pinnedSessionIds"] as? [String] {
                pinnedSessionIds = ids
            } else {
                await load(computer: computer)
            }
            return nil
        } catch {
            return pinned ? "置顶失败，请重试" : "取消置顶失败，请重试"
        }
    }

    /// Archives one conversation, optionally stopping its running turn first.
    /// - Parameters:
    ///   - item: conversation to archive.
    ///   - stopActivity: whether the Host should stop a running turn.
    ///   - computer: paired computer.
    /// - Returns: an error message, or nil on success.
    func archive(_ item: RemoteSession, stopActivity: Bool, computer: SavedComputer) async -> String? {
        do {
            var request: [String: Any] = ["sessionId": item.sessionId]
            if stopActivity { request["stopActivity"] = true }
            _ = try await perform("workspace/archiveSession", arguments: ["request": request], computer: computer)
            await load(computer: computer)
            return nil
        } catch {
            return "归档失败，请重试"
        }
    }

    private func loadComposerSettings(session: URLSession, origin: URL, computerID: String) async {
        if let catalog = try? await rpc(session: session, origin: origin,
                                        method: "session/modelCatalog", args: [:]) {
            applyModelCatalog(catalog)
        }
        let revision = UUID()
        balanceRevision = revision
        let model = MobileModelPreference.read(computerID: computerID) ?? defaultModel
        let provider = model?.split(separator: "/").first.map(String.init)
        let value = await MobileBalanceSnapshot.load(provider: provider) { method, args in
            try await self.rpcValue(session: session, origin: origin, method: method, args: args)
        }
        guard revision == balanceRevision, fundsOrigin == computerID else { return }
        funds = value
    }

    private func applyModelCatalog(_ catalog: [String: Any]) {
        models = MobileModelCatalog.models(from: catalog).map { model in
            ComposerModel(provider: model.provider, model: model.model, name: model.name,
                          efforts: model.efforts, defaultEffort: model.defaultEffort)
        }
        if let fallback = MobileModelCatalog.defaultRoute(from: catalog) {
            defaultModel = fallback
        }
    }

    private static func formatBalance(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "¥\(formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0.00")"
    }

    private func readWorkspaces(session: URLSession, origin: URL) async throws -> WorkspaceBaseline {
        guard var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else {
            throw RemoteError.unavailable
        }
        components.scheme = MobileConnectionAddress.webSocketScheme(for: origin)
        components.path = "/api/remote.mux"
        guard let socketURL = components.url else { throw RemoteError.unavailable }
        var request = URLRequest(url: socketURL)
        let cookies = session.configuration.httpCookieStorage?.cookies(for: origin) ?? []
        request.setValue(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "),
                         forHTTPHeaderField: "Cookie")
        let socket = session.webSocketTask(with: request)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        let timeout = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer { timeout.cancel() }
        let streamId = UUID().uuidString
        let opening = try JSONSerialization.data(withJSONObject: [
            "type": "open", "streamId": streamId, "endpoint": "workspace/follow",
            "payload": ["args": [:]]
        ])
        guard let text = String(data: opening, encoding: .utf8) else { throw RemoteError.unavailable }
        try await socket.send(.string(text))
        for _ in 0..<4 {
            let message = try await socket.receive()
            let data: Data
            switch message {
            case .string(let text): data = Data(text.utf8)
            case .data(let bytes): data = bytes
            @unknown default: continue
            }
            let frame = try JSONDecoder().decode(WorkspaceFrame.self, from: data)
            if frame.streamId == streamId, frame.type == "item",
               frame.value?.type == "baseline", let baseline = frame.value?.value {
                return baseline
            }
        }
        throw RemoteError.unavailable
    }

    func start(text: String?, computer: SavedComputer, cwd: String? = nil,
               permission: String? = nil, model: ComposerModel? = nil, effort: String? = nil,
               attachments: [MobileDraftAttachment] = [], mode: MobileComposerMode = .message,
               existingSessionID: String? = nil, onCreated: ((String) -> Void)? = nil) async -> RemoteSession? {
        guard !starting, let origin = URL(string: computer.origin),
              let pairing = URL(string: computer.connectionURL) else { return nil }
        starting = true
        startError = nil
        defer { starting = false }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--dsh-mobile-test-sessions"),
           let index = arguments.firstIndex(of: "--dsh-mobile-test-start"),
           arguments.indices.contains(index + 1), arguments[index + 1] == "success" {
            let id = existingSessionID ?? UUID().uuidString
            onCreated?(id)
            return RemoteSession(sessionId: id, cwd: cwd, running: false,
                                 updatedAt: Date().timeIntervalSince1970 * 1000,
                                 projections: nil, draftTitle: "新对话测试")
        }
        if arguments.contains("--dsh-mobile-test-sessions"),
           let index = arguments.firstIndex(of: "--dsh-mobile-test-start"),
           arguments.indices.contains(index + 1), arguments[index + 1] == "delayed-failure" {
            try? await Task.sleep(for: .seconds(2))
            startError = "无法开始对话，请重试"
            return nil
        }
        #endif
        do {
            let configuration = URLSessionConfiguration.default
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpShouldSetCookies = true
            let cookies = await withCheckedContinuation { continuation in
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies {
                    continuation.resume(returning: $0)
                }
            }
            for cookie in cookies where cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == origin.host {
                configuration.httpCookieStorage?.setCookie(cookie)
            }
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            var pairingRequest = URLRequest(url: pairing)
            pairingRequest.timeoutInterval = 8
            let (_, response) = try await session.data(for: pairingRequest)
            if (response as? HTTPURLResponse)?.statusCode == 401 { throw RemoteError.pairingExpired }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RemoteError.unavailable }
            let workspaceId = workspaces.first(where: { $0.path == cwd })?.workspaceId
            let createRequest: [String: Any] = workspaceId.map { ["workspaceId": $0] }
                ?? cwd.map { ["cwd": $0] } ?? [:]
            let sessionId: String
            if let existingSessionID {
                sessionId = existingSessionID
            } else {
                let created = try await rpc(session: session, origin: origin,
                                            method: "session/create", args: ["request": createRequest])
                guard let id = created["sessionId"] as? String else { throw RemoteError.unavailable }
                sessionId = id
                onCreated?(id)
            }
            if let model {
                var selection: [String: Any] = ["sessionId": sessionId,
                                                "provider": model.provider, "model": model.model]
                if let effort { selection["reasoningEffort"] = effort }
                _ = try await rpc(session: session, origin: origin, method: "session/selectModel",
                                  args: ["request": selection])
            }
            if let permission {
                let result = try await rpc(session: session, origin: origin,
                                           method: "commands/execute", args: [
                                            "agentId": sessionId, "line": "/permission \(permission)",
                                            "submittedAttachments": []
                                           ])
                guard let command = result["result"] as? [String: Any],
                      command["kind"] as? String == "success" else { throw RemoteError.unavailable }
            }
            if let text {
                let candidate = MobilePendingSubmission(text: text, mode: mode, attachments: attachments)
                let submission = pendingStart?.matches(candidate) == true
                    ? MobilePendingSubmission(text: text, mode: mode, attachments: attachments,
                                              requestId: pendingStart?.requestId ?? candidate.requestId)
                    : candidate
                pendingStart = submission
                try await MobileComposerTransport(session: session, origin: origin)
                    .submit(text: text, attachments: attachments, mode: mode, sessionId: sessionId,
                            requestId: submission.requestId)
                pendingStart = nil
            }
            error = nil
            if let model { MobileModelPreference.save(model.id, effort: effort, computerID: computer.id) }
            return RemoteSession(sessionId: sessionId, cwd: cwd,
                                 running: text != nil, updatedAt: Date().timeIntervalSince1970 * 1000,
                                 projections: nil, draftTitle: text.flatMap { $0.isEmpty ? nil : String($0.prefix(40)) } ?? "新对话")
        } catch {
            self.error = "无法开始对话：\(error.localizedDescription)"
            if case RemoteError.pairingExpired = error {
                startError = "配对已过期，请从电脑重新扫码连接"
            } else if (error as? URLError)?.code == .timedOut {
                startError = "请求超时，未确认是否已发送；再次发送不会重复"
            } else if let failure = error as? MobileComposerFailure {
                startError = "草稿与附件已保留：\(failure.localizedDescription)"
            } else {
                startError = "无法开始对话，请重试"
            }
            return nil
        }
    }

    func listDirectories(computer: SavedComputer, path: String? = nil) async throws -> RemoteDirectoryListing {
        let (session, origin) = try await directorySession(computer: computer)
        defer { session.invalidateAndCancel() }
        let value = try await rpc(session: session, origin: origin,
                                  method: "directoryPicker/list", args: path.map { ["path": $0] } ?? [:])
        let data = try JSONSerialization.data(withJSONObject: value)
        return try JSONDecoder().decode(RemoteDirectoryListing.self, from: data)
    }

    func addDirectory(computer: SavedComputer, path: String) async throws -> String {
        let (session, origin) = try await directorySession(computer: computer)
        defer { session.invalidateAndCancel() }
        let value = try await rpc(session: session, origin: origin,
                                  method: "workspace/create", args: ["request": ["path": path]])
        guard let workspace = value["workspace"] as? [String: Any],
              let selectedPath = workspace["path"] as? String,
              let title = workspace["title"] as? String,
              let workspaceId = workspace["workspaceId"] as? String else { throw RemoteError.unavailable }
        if !workspaces.contains(where: { $0.path == selectedPath }) {
            workspaces.append(RemoteWorkspace(path: selectedPath, title: title, sessionIds: [],
                                              workspaceId: workspaceId))
        }
        return selectedPath
    }

    func createDirectory(computer: SavedComputer, parent: String, name: String) async throws -> String {
        let segment = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segment.isEmpty, segment != ".", segment != "..",
              !segment.contains("/"), !segment.contains("\\") else {
            throw RemoteError.server("文件夹名称只能是一段名称")
        }
        let (session, origin) = try await directorySession(computer: computer)
        defer { session.invalidateAndCancel() }
        guard let path = try await rpcValue(session: session, origin: origin,
                                            method: "directoryPicker/createDirectory",
                                            args: ["path": parent, "name": segment]) as? String else {
            throw RemoteError.unavailable
        }
        return path
    }

    private func directorySession(computer: SavedComputer) async throws -> (URLSession, URL) {
        guard let origin = URL(string: computer.origin), let pairing = URL(string: computer.connectionURL) else {
            throw RemoteError.unavailable
        }
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = true
        let session = URLSession(configuration: configuration)
        do {
            let (_, response) = try await session.data(from: pairing)
            if (response as? HTTPURLResponse)?.statusCode == 401 { throw RemoteError.pairingExpired }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RemoteError.unavailable }
            return (session, origin)
        } catch {
            session.invalidateAndCancel()
            throw error
        }
    }

    private func rpc(session: URLSession, origin: URL, method: String,
                     args: [String: Any]) async throws -> [String: Any] {
        guard let value = try await rpcValue(session: session, origin: origin, method: method,
                                              args: args) as? [String: Any] else {
            throw RemoteError.unavailable
        }
        return value
    }

    private func rpcValue(session: URLSession, origin: URL, method: String,
                          args: [String: Any]) async throws -> Any {
        var request = URLRequest(url: origin.appendingPathComponent("api/\(method)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": "client-request", "rpcId": UUID().uuidString,
            "method": method, "payload": ["args": args]
        ])
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = body["result"] as? [String: Any], result["ok"] as? Bool == true,
              let value = result["value"] else { throw RemoteError.unavailable }
        return value
    }

    private enum RemoteError: LocalizedError {
        case unavailable
        case pairingExpired
        case server(String)
        var errorDescription: String? {
            switch self {
            case .unavailable: return "连接已失效或服务器不可用"
            case .pairingExpired: return "配对已过期，请从这台 Mac 重新扫码连接"
            case .server(let message): return message
            }
        }
    }
}

struct RemoteHomeView: View {
    private enum SortMode {
        case priority
        case project
        case recent
    }

    @ObservedObject var connection: MobileConnection
    let computer: SavedComputer
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var sessions = RemoteSessions()
    @State private var showingComputers = false
    @State private var showingSettings = false
    @AppStorage(MobileNotifications.enabledKey) private var notificationsEnabled = false
    @State private var showingSearch = false
    @State private var search = ""
    @State private var selectedSession: RemoteSession?
    @State private var showingWorkspace = false
    /// Set when the conversation's new-draft button asks for a fresh composer after it closes.
    @State private var pendingNewConversation = false
    /// Project groups the reader folded on this visit.
    @State private var collapsedProjects: Set<String> = []
    @State private var renamingSession: RemoteSession?
    @State private var renameDraft = ""
    @State private var archivingSession: RemoteSession?
    @State private var sessionActionMessage: String?
    @State private var showingNewConversation = false
    @State private var showingFullWorkspace = false
    @State private var showingTopMenu = false
    @State private var showingConnect = false
    @State private var sortMode: SortMode = .project
    @State private var recentFirst = false
    @AppStorage("mobile.openRemoteOnLaunch") private var openRemoteOnLaunch = false
    @AppStorage("mobile.showContextUsage") private var showContextUsage = false
    @AppStorage("mobile.followUpQueue") private var followUpQueue = true

    private var visibleSessions: [RemoteSession] {
        let filtered = sessions.items.filter {
            search.isEmpty ||
            $0.title.localizedCaseInsensitiveContains(search) || $0.project.localizedCaseInsensitiveContains(search)
        }
        switch sortMode {
        case .project:
            return recentFirst ? filtered.sorted { $0.updatedAt > $1.updatedAt } : filtered
        case .recent:
            return filtered.sorted { $0.updatedAt > $1.updatedAt }
        case .priority:
            return filtered.sorted {
                if $0.running != $1.running { return $0.running }
                return $0.updatedAt > $1.updatedAt
            }
        }
    }

    private var projects: [String] {
        guard sortMode == .project else { return [] }
        var seen = Set<String>()
        return visibleSessions.compactMap { item in
            guard let cwd = item.cwd else { return nil }
            return seen.insert(cwd).inserted ? cwd : nil
        }
    }

    private var pinned: [RemoteSession] {
        sessions.pinnedSessionIds.compactMap { id in visibleSessions.first(where: { $0.id == id }) }
    }

    private func projectTitle(_ path: String) -> String {
        sessions.workspaces.first(where: { $0.path == path })?.title
            ?? URL(fileURLWithPath: path).lastPathComponent
    }

    private func open(_ item: RemoteSession) {
        selectedSession = item
        showingWorkspace = true
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button { showingTopMenu.toggle() } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 38, height: 38)
                            .mobileGlass(in: Circle(), interactive: true)
                    }
                    .accessibilityLabel("打开顶部菜单")
                    Spacer()
                    Button { showingComputers = true } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Text("远程").font(.system(size: 15, weight: .semibold))
                                Image(systemName: "chevron.down").font(.caption2)
                            }
                            HStack(spacing: 5) {
                                Circle().fill(sessions.lastConnectedAt == nil ? .orange : .green)
                                    .frame(width: 5, height: 5)
                                Text(computer.name).lineLimit(1)
                            }
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button { showingSearch.toggle() } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 38, height: 38)
                            .mobileGlass(in: Circle(), interactive: true)
                    }
                    .accessibilityLabel("搜索")
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)
                .frame(height: 62)
                computerShortcuts
                if showingSearch {
                    TextField("搜索项目或对话", text: $search)
                        .textFieldStyle(.roundedBorder).padding(.horizontal, 20).padding(.bottom, 8)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if sessions.loading && sessions.items.isEmpty {
                            ProgressView("正在读取 \(computer.name) 的对话…")
                                .frame(maxWidth: .infinity).padding(.top, 55)
                        } else if let error = sessions.error, sessions.items.isEmpty {
                            emptyState(error, symbol: "wifi.exclamationmark")
                            Button("重试") { Task { await loadSessions() } }
                                .frame(maxWidth: .infinity)
                        } else if visibleSessions.isEmpty {
                            emptyState(search.isEmpty ? "暂无对话" : "没有匹配的对话",
                                       symbol: "bubble.left")
                        }
                        if let error = sessions.error, !sessions.items.isEmpty {
                            HStack {
                                Text(error).font(.caption).foregroundStyle(.orange)
                                Spacer()
                                Button("重试") { Task { await loadSessions() } }
                            }
                        }
                        if !pinned.isEmpty {
                            sectionHeading("置顶")
                            ForEach(pinned) { item in sessionRow(item, indent: 0) }
                        }
                        if !projects.isEmpty { sectionHeading("项目") }
                        ForEach(projects, id: \.self) { project in
                            HStack(spacing: 9) {
                                Button {
                                    if collapsedProjects.contains(project) {
                                        collapsedProjects.remove(project)
                                    } else {
                                        collapsedProjects.insert(project)
                                    }
                                    MobileProjectCollapseStore.save(collapsedProjects, computerID: computer.id)
                                } label: {
                                    HStack(spacing: 9) {
                                        Image(systemName: collapsedProjects.contains(project) ? "folder" : "folder.fill")
                                            .font(.system(size: 15))
                                            .foregroundStyle(.secondary)
                                        Text(projectTitle(project)).font(.system(size: 14, weight: .semibold))
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .rotationEffect(.degrees(collapsedProjects.contains(project) ? -90 : 0))
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(collapsedProjects.contains(project)
                                    ? "展开\(projectTitle(project))"
                                    : "折叠\(projectTitle(project))")
                                .accessibilityValue(collapsedProjects.contains(project) ? "已折叠" : "已展开")
                                Button {
                                    Task {
                                        if let session = await sessions.start(text: nil, computer: computer, cwd: project) {
                                            open(session)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 13)).foregroundStyle(.secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .disabled(sessions.starting)
                                .accessibilityLabel("在\(projectTitle(project))新建对话")
                            }
                            .frame(minHeight: 44)
                            if !collapsedProjects.contains(project) {
                                ForEach(visibleSessions.filter { $0.cwd == project && !sessions.pinnedSessionIds.contains($0.id) }) { item in
                                    sessionRow(item, indent: 24)
                                }
                            }
                        }
                        if sortMode != .project, !visibleSessions.isEmpty {
                            sectionHeading(sortMode == .priority ? "优先级" : "最近")
                            ForEach(visibleSessions.filter { !sessions.pinnedSessionIds.contains($0.id) }) { item in
                                sessionRow(item, indent: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 21).padding(.bottom, 25)
                }
                .refreshable { await loadSessions() }
                homeComposer
            }
            .background(Color(uiColor: .systemBackground))
            .overlay {
                if showingTopMenu {
                    GeometryReader { geometry in
                        ZStack(alignment: .top) {
                            Color.black.opacity(0.13).ignoresSafeArea()
                                .onTapGesture { showingTopMenu = false }
                            topMenu
                                .frame(width: min(280, geometry.size.width - 60))
                                .padding(.top, 54)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: computer.connectionURL) {
                collapsedProjects = MobileProjectCollapseStore.load(computerID: computer.id)
                if computer.usingFallback {
                    _ = await connection.restorePreferredRouteIfReachable(computer)
                }
                await loadSessions()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    if Task.isCancelled { break }
                    if computer.usingFallback,
                       await connection.restorePreferredRouteIfReachable(computer) != nil { continue }
                    await loadSessions(quietly: true)
                }
            }
            .sheet(isPresented: $showingComputers) { computerSheet }
            .sheet(isPresented: $showingSettings) { settingsSheet }
            .sheet(isPresented: $showingConnect) { ConnectView(connection: connection) }
            .sheet(item: $renamingSession) { target in
                NavigationStack {
                    Form {
                        TextField("对话名称", text: $renameDraft)
                    }
                    .navigationTitle("重命名对话")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { renamingSession = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                let title = renameDraft
                                renamingSession = nil
                                Task {
                                    if let message = await sessions.rename(target, to: title, computer: computer) {
                                        sessionActionMessage = message
                                    }
                                }
                            }
                            .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .confirmationDialog("归档这个对话？", isPresented: Binding(
                get: { archivingSession != nil },
                set: { if !$0 { archivingSession = nil } }
            ), titleVisibility: .visible) {
                if let target = archivingSession {
                    if target.running {
                        // The Host refuses to archive active work unless the stop is requested with it.
                        Button("归档并停止运行中的任务", role: .destructive) {
                            archivingSession = nil
                            archiveSession(target, stopActivity: true)
                        }
                    } else {
                        Button("归档", role: .destructive) {
                            archivingSession = nil
                            archiveSession(target, stopActivity: false)
                        }
                    }
                }
                Button("取消", role: .cancel) { archivingSession = nil }
            } message: {
                Text("归档后从 iPhone 列表隐藏，可在电脑端恢复；不会删除历史。")
            }
            .alert("提示", isPresented: Binding(
                get: { sessionActionMessage != nil },
                set: { if !$0 { sessionActionMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(sessionActionMessage ?? "")
            }
            .sheet(isPresented: $showingFullWorkspace) {
                if let url = URL(string: computer.connectionURL) {
                    DshWebView(url: url, onUnauthorized: connection.expireActive)
                }
            }
            .navigationDestination(isPresented: $showingWorkspace) {
                if let selected = selectedSession {
                    RemoteChatView(connection: connection, computer: computer, sessionId: selected.sessionId,
                                   title: selected.title, project: selected.project,
                                   onUnauthorized: connection.expireActive,
                                   onNewConversation: { pendingNewConversation = true })
                }
            }
            .navigationDestination(isPresented: $showingNewConversation) {
                RemoteNewConversationView(connection: connection, computer: computer, sessions: sessions)
            }
            .onChange(of: showingNewConversation) { visible in
                if !visible { Task { await loadSessions() } }
            }
            // A hidden search must not keep filtering the list after its field closes.
            .onChange(of: showingSearch) { visible in
                if !visible { search = "" }
            }
            // The conversation's new-draft button closes the conversation first, then
            // opens a fresh composer with the previous draft restored by its own store.
            .onChange(of: showingWorkspace) { visible in
                guard !visible, pendingNewConversation else { return }
                pendingNewConversation = false
                // Push the composer after the pop settles so the navigation stack keeps both requests.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    showingNewConversation = true
                }
            }
        }
    }

    private var computerShortcuts: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(connection.computers) { item in
                        let selected = item.id == computer.id
                        Button {
                            if !selected { connection.select(item.id) }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "desktopcomputer")
                                Text(item.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 220)
                                if selected {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(selected ? .primary : .secondary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(selected ? Color(uiColor: .tertiarySystemFill) : .clear,
                                        in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                        .accessibilityIdentifier("computerShortcut-\(item.id)")
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 18)
            }
            .onAppear { proxy.scrollTo(computer.id, anchor: .center) }
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 23).padding(.bottom, 8)
    }

    private var topMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            topMenuRow("优先级", symbol: "bell", selected: sortMode == .priority) {
                sortMode = .priority
            }
            topMenuRow("按项目", symbol: "folder", selected: sortMode == .project) {
                sortMode = .project
            }
            topMenuRow("按时间倒序排列", symbol: "clock.arrow.circlepath", selected: sortMode == .recent) {
                sortMode = .recent
            }
            Divider().padding(.vertical, 8)
            topMenuRow("优先显示最近", symbol: "bubble.left", selected: recentFirst) {
                recentFirst.toggle()
            }
            Divider().padding(.vertical, 8)
            Text("管理")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 39).padding(.bottom, 4)
            topMenuRow("添加连接", symbol: "link") { showingConnect = true }
            topMenuRow("设置", symbol: "gearshape") { showingSettings = true }
            Divider().padding(.vertical, 8)
            Text("可用余额")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 39).padding(.bottom, 4)
            Text(sessions.balance ?? "—")
                .font(.system(size: 15, weight: .medium))
                .padding(.leading, 39).frame(height: 37)
        }
        .padding(12)
        .mobileGlass(in: RoundedRectangle(cornerRadius: 23, style: .continuous))
    }

    private func topMenuRow(_ title: String, symbol: String, selected: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button {
            showingTopMenu = false
            action()
        } label: {
            HStack(spacing: 11) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 14)
                } else {
                    Color.clear.frame(width: 14, height: 1)
                }
                Image(systemName: symbol)
                    .font(.system(size: 16))
                    .frame(width: 19)
                Text(title)
                    .font(.system(size: 15))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sessionRow(_ item: RemoteSession, indent: CGFloat) -> some View {
        Button { open(item) } label: {
            HStack(spacing: 7) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    if showsProjectContext(item) {
                        Text("\(item.project) · \(computer.name)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if item.running {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("运行中").font(.caption2).foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("正在运行")
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.leading, indent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title)，项目 \(item.project)\(item.running ? "，正在运行" : "")")
        .contextMenu {
            Button("重命名") { beginRename(item) }
            Button(isPinned(item) ? "取消置顶" : "置顶") {
                Task { await togglePinned(item) }
            }
            Button("复制会话 ID") {
                UIPasteboard.general.string = item.sessionId
                sessionActionMessage = "已复制会话 ID"
            }
            Button("归档…", role: .destructive) { archivingSession = item }
        }
        .accessibilityAction(named: "重命名对话") { beginRename(item) }
        .accessibilityAction(named: isPinned(item) ? "取消置顶" : "置顶") {
            Task { await togglePinned(item) }
        }
        .accessibilityAction(named: "复制会话 ID") {
            UIPasteboard.general.string = item.sessionId
        }
        .accessibilityAction(named: "归档对话") { archivingSession = item }
    }

    /// Whether this row needs its project and Mac shown as context.
    /// - Parameter item: listed conversation.
    /// - Returns: true for pinned rows and for titles shared by more than one conversation outside project groups.
    private func showsProjectContext(_ item: RemoteSession) -> Bool {
        if isPinned(item) { return true }
        guard sortMode != .project else { return false }
        return visibleSessions.filter { $0.title == item.title }.count > 1
    }

    /// Whether this conversation is currently pinned on the Host.
    /// - Parameter item: listed conversation.
    /// - Returns: true when the Host pinned it.
    private func isPinned(_ item: RemoteSession) -> Bool {
        sessions.pinnedSessionIds.contains(item.sessionId)
    }

    /// Opens the rename sheet with the current title filled in.
    /// - Parameter item: conversation to rename.
    private func beginRename(_ item: RemoteSession) {
        renameDraft = item.title
        renamingSession = item
    }

    /// Pins or unpins one conversation and reports a Host refusal.
    /// - Parameter item: conversation to change.
    private func togglePinned(_ item: RemoteSession) async {
        if let message = await sessions.setPinned(item, pinned: !isPinned(item), computer: computer) {
            sessionActionMessage = message
        }
    }

    /// Archives one conversation, reporting a Host refusal.
    /// - Parameters:
    ///   - item: conversation to archive.
    ///   - stopActivity: whether to stop a running turn first.
    private func archiveSession(_ item: RemoteSession, stopActivity: Bool) {
        Task {
            if let message = await sessions.archive(item, stopActivity: stopActivity, computer: computer) {
                sessionActionMessage = message
            }
        }
    }

    /// Loads the session list, switching to the fallback route when the preferred route is unreachable.
    /// - Parameter quietly: suppress the loading indicator for background refreshes.
    private func loadSessions(quietly: Bool = false) async {
        if await sessions.load(computer: computer, quietly: quietly) { return }
        guard sessions.transportUnreachable,
              let updated = connection.switchToFallback(computer) else { return }
        _ = await sessions.load(computer: updated, quietly: quietly)
    }

    private var homeComposer: some View {
        HStack(spacing: 9) {
            Button { showingNewConversation = true } label: {
                Image(systemName: "plus").font(.system(size: 18))
                    .frame(width: 26, height: 36)
            }
            .accessibilityLabel("新建对话")
            Button { showingNewConversation = true } label: {
                Text("向点点够提问")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel("新对话输入框")
            Button { showingNewConversation = true } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.blue, in: Circle())
            }
            .accessibilityLabel("打开新对话")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .mobileGlass(in: Capsule())
        .padding(.horizontal, 16).padding(.bottom, 10)
    }

    private var computerSheet: some View {
        NavigationStack {
            List {
                Section("已配对的 Mac") {
                    ForEach(connection.computers) { item in
                        Button {
                            connection.select(item.id)
                            showingComputers = false
                        } label: {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                VStack(alignment: .leading) {
                                    Text(item.name).font(.headline)
                                    Text(item.id).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if item.id == computer.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择电脑")
            .toolbar { Button("完成") { showingComputers = false } }
        }
    }

    private var settingsSheet: some View {
        ZStack {
            Color(red: 0.105, green: 0.105, blue: 0.115).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Color.clear.frame(width: 43, height: 43)
                        Spacer()
                        Text("远程控制").font(.system(size: 18, weight: .semibold))
                        Spacer()
                        Button { showingSettings = false } label: {
                            Image(systemName: "xmark").font(.system(size: 18))
                                .frame(width: 43, height: 43)
                                .background(.white.opacity(0.08), in: Circle())
                        }
                        .accessibilityLabel("关闭远程控制设置")
                    }
                    .padding(.bottom, 4)

                    Button {
                        showingSettings = false
                        showingFullWorkspace = true
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 27)).foregroundStyle(.secondary)
                            Text("个人资料").font(.system(size: 16, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(16).frame(height: 58)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
                    }

                    Toggle(isOn: $notificationsEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("完成与审批通知").font(.system(size: 16, weight: .medium))
                            Text("回合完成、等待批准或出错时提醒")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: notificationsEnabled) { enabled in
                        guard enabled else { return }
                        Task {
                            if !(await MobileNotifications.shared.requestAuthorization()) {
                                notificationsEnabled = false
                            }
                        }
                    }
                    .padding(16)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("账号余额 \(sessions.funds.account ?? "暂不可用")")
                        ForEach(sessions.funds.accountDetails, id: \.self) { Text($0).font(.caption) }
                        Text("API 余额 \(sessions.funds.providers["deepseek-official"] ?? "暂不可用")")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))

                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            Text("连接").foregroundStyle(.secondary)
                            Spacer()
                            Button("全部断开") { connection.leave() }
                                .foregroundStyle(.blue)
                        }.font(.system(size: 14, weight: .medium)).padding(.horizontal, 15)
                        VStack(spacing: 0) {
                            ForEach(connection.computers) { item in
                                HStack(spacing: 12) {
                                    Image(systemName: "desktopcomputer")
                                        .font(.system(size: 22)).foregroundStyle(.secondary)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("点点够桌面版").font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                        Text(item.name).font(.system(size: 16, weight: .medium))
                                        HStack(spacing: 5) {
                                            Circle().fill(item.id == connection.activeID
                                                ? (sessions.lastConnectedAt == nil ? .orange : .green) : .gray)
                                                .frame(width: 7, height: 7)
                                            Text(item.id == connection.activeID
                                                ? (sessions.lastConnectedAt == nil ? "连接待确认" : "已连接")
                                                : "已断开连接")
                                        }.font(.system(size: 12)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 4)
                                    SavedComputerActions(connection: connection, computer: item)
                                    Toggle(item.name, isOn: Binding(
                                        get: { connection.activeID == item.id },
                                        set: { enabled in
                                            if enabled { connection.select(item.id) }
                                            else if connection.activeID == item.id { connection.leave() }
                                        }
                                    )).labelsHidden().tint(.green)
                                }
                                .padding(.horizontal, 16).frame(height: 78)
                                if item.id != connection.computers.last?.id {
                                    Divider().overlay(.white.opacity(0.1)).padding(.leading, 56)
                                }
                            }
                            Divider().overlay(.white.opacity(0.1)).padding(.leading, 56)
                            Button {
                                showingSettings = false
                                showingConnect = true
                            } label: {
                                Label("添加连接", systemImage: "plus")
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 17).frame(height: 53)
                            }.foregroundStyle(.blue)
                        }
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("连接检查").font(.system(size: 14, weight: .medium))
                                Text(sessions.lastConnectedAt.map { "上次成功：\($0.formatted(date: .omitted, time: .shortened))" }
                                     ?? "尚未连通这台 Mac")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if sessions.loading { ProgressView().tint(.white) }
                            Button("检查") { Task { await loadSessions() } }
                                .disabled(sessions.loading)
                        }
                        .padding(16)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("自动打开远程控制", isOn: $openRemoteOnLaunch)
                            .padding(16)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
                        Text("打开应用时直接进入远程控制。")
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 15)
                    }
                    VStack(alignment: .leading, spacing: 13) {
                        Text("编写器").font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary).padding(.horizontal, 15)
                        VStack(spacing: 0) {
                            Toggle("显示上下文窗口使用情况", isOn: $showContextUsage).padding(16)
                            Divider().padding(.leading, 16)
                            HStack {
                                Text("后续行为")
                                Spacer()
                                Picker("后续行为", selection: $followUpQueue) {
                                    Text("排队").tag(true)
                                    Text("立即发送").tag(false)
                                }
                                .labelsHidden()
                                .tint(.gray)
                            }.padding(16)
                        }.background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
                    }

                }
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 32)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    private func emptyState(_ message: String, symbol: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 55)
    }
}

private struct RemoteNewConversationView: View {
    @ObservedObject var connection: MobileConnection
    let computer: SavedComputer
    @ObservedObject var sessions: RemoteSessions
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var inputFocused: Bool
    @State private var draft = ""
    @State private var draftSaveTask: Task<Void, Never>?
    @StateObject private var additions = MobileComposerAdditions()
    @State private var createdDraftID: String?
    @State private var selectedWorkspace: String?
    @State private var selectedPermission: String?
    @State private var selectedModelID: String?
    @State private var showingFullWorkspace = false
    @State private var showingProjectMenu = false
    @State private var showingDirectoryBrowser = false
    @State private var createdSession: RemoteSession?
    @State private var showingCreatedSession = false
    @State private var pendingNewConversation = false
    @StateObject private var voice = MobileVoiceInput()
    @State private var voiceBaseDraft = ""
    @State private var submitting = false

    /// Loads the session list, switching to the fallback route when the preferred route is unreachable.
    /// - Parameter quietly: suppress the loading indicator for background refreshes.
    private func loadSessions(quietly: Bool = false) async {
        if await sessions.load(computer: computer, quietly: quietly) { return }
        guard sessions.transportUnreachable,
              let updated = connection.switchToFallback(computer) else { return }
        _ = await sessions.load(computer: updated, quietly: quietly)
    }

    private var availableWorkspaces: [RemoteWorkspace] {
        if !sessions.workspaces.isEmpty { return sessions.workspaces }
        var seen = Set<String>()
        return sessions.items.compactMap { item in
            guard let path = item.cwd, seen.insert(path).inserted else { return nil }
            return RemoteWorkspace(path: path, title: item.project, sessionIds: [])
        }
    }

    private var workspaceTitle: String {
        guard let selectedWorkspace else { return "默认工作区" }
        return availableWorkspaces.first(where: { $0.path == selectedWorkspace })?.title
            ?? URL(fileURLWithPath: selectedWorkspace).lastPathComponent
    }

    private var currentModel: ComposerModel? {
        let lastUsed = selectedModelID ?? MobileModelPreference.read(computerID: computer.id)
        return sessions.models.first(where: { $0.id == lastUsed })
            ?? sessions.models.first(where: { $0.id == sessions.defaultModel })
            ?? sessions.models.first
    }

    /// The level this iPhone last confirmed for the current route, or that route's default.
    private var currentEffort: String? {
        guard let model = currentModel, !model.efforts.isEmpty else { return nil }
        let stored = MobileModelPreference.readEffort(computerID: computer.id)
        return model.efforts.first(where: { $0.id == stored })?.id ?? model.defaultEffort
    }

    /// The Host's label for the level the current route uses.
    private var currentEffortName: String? {
        guard let model = currentModel, let effort = currentEffort else { return nil }
        return model.efforts.first(where: { $0.id == effort })?.name ?? effort
    }

    /// Names one model the way the new-conversation menu shows it.
    /// - Parameter model: menu row route.
    /// - Returns: the display name, with the current level when it applies.
    private func composerModelLabel(_ model: ComposerModel) -> String {
        guard model.id == currentModel?.id, let name = currentEffortName else { return model.shortName }
        return "\(model.shortName) · \(name)"
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                conversationChoices
                    .frame(minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(.primary)
        .background(Color(uiColor: .systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if voice.recording || voice.starting {
                recordingComposer
            } else {
                composer
            }
        }
        .overlay {
            if showingProjectMenu {
                GeometryReader { geometry in
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.10).ignoresSafeArea()
                            .onTapGesture { showingProjectMenu = false }
                        projectMenu
                            .frame(width: min(280, geometry.size.width - 62))
                            .padding(.top, 55)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .mobileComposerActions(additions, computer: computer)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingDirectoryBrowser) {
            RemoteDirectoryBrowser(computer: computer, sessions: sessions) { path in
                selectedWorkspace = path
                showingDirectoryBrowser = false
            }
        }
        .sheet(isPresented: $showingFullWorkspace) {
            if let url = URL(string: computer.connectionURL) {
                DshWebView(url: url, onUnauthorized: connection.expireActive)
            }
        }
        .navigationDestination(isPresented: $showingCreatedSession) {
            if let createdSession {
                RemoteChatView(connection: connection, computer: computer, sessionId: createdSession.sessionId,
                               title: createdSession.title, project: createdSession.project,
                               onUnauthorized: connection.expireActive,
                               onNewConversation: { pendingNewConversation = true })
            }
        }
        .task {
            sessions.startError = nil
            selectedWorkspace = availableWorkspaces.first?.path
            restoreDraft()
            inputFocused = true
        }
        .onChange(of: draft) { _ in scheduleDraftSave() }
        .onChange(of: additions.mode) { _ in scheduleDraftSave() }
        .onChange(of: scenePhase) { phase in
            if phase != .active { saveDraftNow() }
        }
        .onDisappear {
            voice.cancel()
            saveDraftNow()
        }
        .onChange(of: showingCreatedSession) { visible in
            guard !visible, pendingNewConversation else { return }
            pendingNewConversation = false
            draft = ""
            MobileDraftStore.clear(key: newDraftKey)
            additions.mode = .message
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                inputFocused = true
            }
        }
        .onChange(of: selectedWorkspace) { _ in createdDraftID = nil }
        .onChange(of: sessions.workspaces.count) { _ in
            if selectedWorkspace == nil { selectedWorkspace = availableWorkspaces.first?.path }
        }
    }

    private var conversationChoices: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回远程首页")
            .padding(.leading, 17)
            .padding(.top, 8)
            Spacer(minLength: 45)
            VStack(alignment: .leading, spacing: 0) {
                Menu {
                    ForEach(connection.computers) { item in
                        Button(item.name) { connection.select(item.id) }
                    }
                } label: {
                    selectionRow("desktopcomputer", computer.name, selectable: true)
                }
                .disabled(submitting)
                Button {
                    showingProjectMenu = true
                    inputFocused = true
                } label: {
                    selectionRow("folder", workspaceTitle, selectable: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择项目目录")
                .disabled(submitting)
                selectionRow("laptopcomputer", "在这台 Mac 工作", selectable: false)
            }
            .padding(.horizontal, 26)
            Spacer(minLength: 35)
        }
    }

    private func selectionRow(_ symbol: String, _ title: String, selectable: Bool) -> some View {
        HStack(spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .frame(width: 25)
            Text(title).font(.subheadline.weight(.medium))
            if selectable {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .frame(minHeight: 49)
        .contentShape(Rectangle())
    }

    private var projectMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                selectedWorkspace = nil
                showingProjectMenu = false
            } label: {
                projectMenuRow("不在项目中工作", symbol: "bubble.left", selected: selectedWorkspace == nil)
            }
            Divider().padding(.vertical, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(availableWorkspaces, id: \.path) { workspace in
                        Button {
                            selectedWorkspace = workspace.path
                            showingProjectMenu = false
                        } label: {
                            projectMenuRow(workspace.title, symbol: "folder",
                                           selected: selectedWorkspace == workspace.path)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(availableWorkspaces.count) * 43, 300))
            Divider().padding(.vertical, 6)
            Button {
                showingProjectMenu = false
                showingDirectoryBrowser = true
            } label: {
                projectMenuRow("添加新文件夹", symbol: "plus", selected: false)
            }
        }
        .buttonStyle(.plain)
        .padding(12)
        .mobileGlass(in: RoundedRectangle(cornerRadius: 23, style: .continuous))
    }

    private func projectMenuRow(_ title: String, symbol: String, selected: Bool) -> some View {
        HStack(spacing: 11) {
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 14)
            } else {
                Color.clear.frame(width: 14, height: 1)
            }
            Image(systemName: symbol).font(.system(size: 16)).frame(width: 19)
            Text(title).font(.system(size: 15)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: 43)
        .contentShape(Rectangle())
    }

    /// Toggles dictation on the new-conversation page.
    private func toggleVoice() {
        if voice.starting {
            voice.cancel()
            return
        }
        if voice.recording {
            Task { draft = mergedVoiceDraft(await voice.stop()) }
            return
        }
        voiceBaseDraft = draft
        inputFocused = false
        Task { await voice.start() }
    }

    /// Keeps typed text ahead of the final dictation transcript.
    private func mergedVoiceDraft(_ transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return voiceBaseDraft }
        return voiceBaseDraft.isEmpty ? trimmed : voiceBaseDraft + "\n" + trimmed
    }

    private var recordingComposer: some View {
        MobileRecordingBar(
            voice: voice,
            onCancel: {
                voice.cancel()
                draft = voiceBaseDraft
            },
            onStop: {
                Task { draft = mergedVoiceDraft(await voice.stop()) }
            },
            onSend: {
                Task {
                    draft = mergedVoiceDraft(await voice.stop())
                    startDraft()
                }
            })
            .padding(.horizontal, 14).padding(.bottom, 9)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 14) {
            MobileComposerAttachmentStrip(additions: additions)
            if submitting {
                Text("正在创建对话…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("newConversationProgress")
            } else if let voiceError = voice.error {
                Text(voiceError).font(.footnote).foregroundStyle(.orange)
            } else if let error = sessions.startError {
                HStack(alignment: .center, spacing: 8) {
                    Text(error).font(.footnote).foregroundStyle(.red)
                        .accessibilityIdentifier("newConversationError")
                    Spacer(minLength: 0)
                    Button { startDraft() } label: {
                        Text("重试")
                            .font(.footnote)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("newConversationRetry")
                }
            }
            TextField("向点点够提问", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(.subheadline)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { startDraft() }
                .disabled(submitting)
                .accessibilityIdentifier("newConversationInput")
            composerToolbar
        }
        .padding(.horizontal, 17).padding(.vertical, 14)
        .mobileGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 14).padding(.bottom, 9)
    }

    private var composerMetadata: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(sessions.models) { model in
                    Button {
                        selectedModelID = model.id
                        let stored = MobileModelPreference.readEffort(computerID: computer.id)
                        let effort = model.efforts.first(where: { $0.id == stored })?.id ?? model.defaultEffort
                        MobileModelPreference.save(model.id, effort: effort, computerID: computer.id)
                        Task { await loadSessions() }
                    } label: {
                        if currentModel?.id == model.id {
                            Label(composerModelLabel(model), systemImage: "checkmark")
                        } else {
                            Text(model.shortName)
                        }
                    }
                }
            } label: {
                Text(currentModel.map(composerModelLabel)
                     ?? (sessions.loading ? "正在读取模型…" : "模型不可用"))
            }
            .accessibilityIdentifier("newConversationModel")
            if currentModel != nil {
                Text("余额 \(sessions.funds.available(provider: currentModel?.provider) ?? "暂不可用")")
                    .accessibilityIdentifier("newConversationBalance")
                    .layoutPriority(1)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var composerToolbar: some View {
        HStack(spacing: 0) {
            MobileComposerAddButton(additions: additions) {
                inputFocused = false
                showingProjectMenu = false
            }
            .disabled(submitting || additions.importing)
            Menu {
                Button("仅可查看") { selectedPermission = "read-only" }
                Button("工作区内修改") { selectedPermission = "workspace-write" }
                Button("完全权限") { selectedPermission = "danger-full-access" }
            } label: {
                Image(systemName: selectedPermission == nil ? "shield.lefthalf.filled" : "shield.checkered")
                    .font(.system(size: 17))
                    .foregroundStyle(.orange)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(submitting)
            .accessibilityLabel("访问权限")
            composerMetadata.frame(maxWidth: .infinity, alignment: .leading)
            MobileVoiceButton(voice: voice, action: toggleVoice)
                .disabled(submitting || voice.recording)
            Button { startDraft() } label: {
                ZStack {
                    Circle().fill(.blue).frame(width: 34, height: 34)
                    if submitting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .disabled((draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !additions.hasAttachments)
                      || submitting || sessions.starting || additions.importing
                      || (additions.mode == .goal && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            .accessibilityLabel(submitting ? "正在创建对话" : "发送新对话")
            .accessibilityIdentifier("newConversationSend")
        }
    }

    /// Storage key for this computer's new-conversation draft.
    private var newDraftKey: String {
        MobileDraftStore.newConversationKey(computerID: computer.id)
    }

    /// Restores an unsent new-conversation draft once, without overwriting newer typing.
    private func restoreDraft() {
        guard draft.isEmpty, additions.mode == .message,
              let stored = MobileDraftStore.load(key: newDraftKey) else { return }
        draft = stored.text
        additions.mode = stored.mode
    }

    /// Debounces one draft write so typing does not touch defaults on every key.
    private func scheduleDraftSave() {
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            saveDraftNow()
        }
    }

    /// Writes the current draft, clearing the key when the composer is empty.
    private func saveDraftNow() {
        draftSaveTask?.cancel()
        draftSaveTask = nil
        MobileDraftStore.save(MobileDraft(text: draft, mode: additions.mode), key: newDraftKey)
    }

    private func startDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || additions.hasAttachments), !submitting, !sessions.starting,
              !additions.importing, additions.mode != .goal || !text.isEmpty else { return }
        let submittedDraft = draft
        let submittedAttachments = additions.attachments
        let submittedMode = additions.mode
        submitting = true
        showingProjectMenu = false
        additions.showingMenu = false
        Task {
            defer { submitting = false }
            if let session = await sessions.start(text: text, computer: computer,
                                                  cwd: selectedWorkspace, permission: selectedPermission,
                                                  model: currentModel, effort: currentEffort,
                                                  attachments: submittedAttachments,
                                                  mode: submittedMode, existingSessionID: createdDraftID,
                                                  onCreated: { createdDraftID = $0 }) {
                inputFocused = false
                if draft == submittedDraft {
                    draft = ""
                    MobileDraftStore.clear(key: newDraftKey)
                }
                let delivered = Set(submittedAttachments.map(\.id))
                additions.attachments.removeAll { delivered.contains($0.id) }
                if additions.mode == submittedMode { additions.mode = .message }
                createdDraftID = nil
                createdSession = session
                showingCreatedSession = true
            }
        }
    }
}

private struct RemoteDirectoryBrowser: View {
    let computer: SavedComputer
    @ObservedObject var sessions: RemoteSessions
    let onSelected: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var listing: RemoteDirectoryListing?
    @State private var loading = false
    @State private var error: String?
    @State private var showingCreate = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if let listing {
                    Section("位置") {
                        Menu {
                            ForEach(listing.crumbs) { crumb in
                                Button(crumb.name) { Task { await load(path: crumb.path) } }
                            }
                        } label: {
                            Label(listing.path, systemImage: "folder")
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Section("文件夹") {
                        ForEach(listing.entries.filter { !$0.hidden }) { entry in
                            Button { Task { await load(path: entry.path) } } label: {
                                HStack {
                                    Label(entry.name, systemImage: "folder")
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                            }
                        }
                        if listing.truncated {
                            Text("此目录项目过多，仅显示部分文件夹")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else if loading {
                    ProgressView("正在读取 Mac 文件夹…")
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("重试") { Task { await load(path: listing?.path) } }
                    }
                }
            }
            .navigationTitle("添加项目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button("新建文件夹") {
                        newName = ""
                        showingCreate = true
                    }
                    .disabled(listing == nil || loading)
                    Button("使用此文件夹") {
                        if let path = listing?.path { Task { await add(path: path) } }
                    }
                    .disabled(listing == nil || loading)
                }
            }
            .alert("新建文件夹", isPresented: $showingCreate) {
                TextField("文件夹名称", text: $newName)
                Button("取消", role: .cancel) {}
                Button("创建并添加") {
                    if let parent = listing?.path { Task { await create(parent: parent) } }
                }
            } message: {
                Text("在当前 Mac 目录下新建文件夹，并加入项目列表")
            }
        }
        .task { await load(path: nil) }
    }

    private func load(path: String?) async {
        loading = true
        defer { loading = false }
        do {
            listing = try await sessions.listDirectories(computer: computer, path: path)
            error = nil
        } catch {
            self.error = "无法浏览这台 Mac 的文件夹，请重试"
        }
    }

    private func add(path: String) async {
        loading = true
        defer { loading = false }
        do {
            let selected = try await sessions.addDirectory(computer: computer, path: path)
            onSelected(selected)
        } catch {
            self.error = "无法将此文件夹添加为项目，请重试"
        }
    }

    private func create(parent: String) async {
        loading = true
        defer { loading = false }
        do {
            let path = try await sessions.createDirectory(computer: computer,
                                                           parent: parent, name: newName)
            let selected = try await sessions.addDirectory(computer: computer, path: path)
            onSelected(selected)
        } catch {
            self.error = "无法新建项目文件夹：\(error.localizedDescription)"
        }
    }
}

struct RemoteLandingView: View {
    @ObservedObject var connection: MobileConnection
    @State private var showingConnect = false

    var body: some View {
        VStack(spacing: 0) {
            MobileWelcomeBrand()
                .padding(.horizontal, 32)
                .padding(.top, 44)
                .padding(.bottom, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !connection.computers.isEmpty {
                        Text("已配对的电脑").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(connection.computers) { computer in
                            Button { connection.select(computer.id) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "desktopcomputer")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(computer.name).font(.headline)
                                        Text(computer.id).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption)
                                }
                                .foregroundStyle(.primary)
                                .padding(.vertical, 10)
                            }
                        }
                    } else {
                        MobileWelcomeMessage()
                            .padding(.top, 100)
                        Text("在电脑应用中打开“连接手机”，扫码或粘贴链接后即可查看项目和对话")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Button { showingConnect = true } label: {
                        Label("连接电脑", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .foregroundStyle(Color(uiColor: .systemBackground))
                            .background(Color.primary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $showingConnect) { ConnectView(connection: connection) }
    }
}
