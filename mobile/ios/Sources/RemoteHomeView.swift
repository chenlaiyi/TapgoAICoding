import SwiftUI
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
    var id: String { "\(provider)/\(model)" }
    var shortName: String { mobileModelDisplayName(name, modelID: model) }
}

func mobileModelDisplayName(_ name: String, modelID: String) -> String {
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

enum MobileModelPreference {
    static func read(computerID: String) -> String? {
        UserDefaults.standard.string(forKey: "dsh.mobile.last-model.\(computerID)")
    }

    static func save(_ modelID: String, computerID: String) {
        UserDefaults.standard.set(modelID, forKey: "dsh.mobile.last-model.\(computerID)")
    }
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
    @Published var models: [ComposerModel] = []
    @Published var defaultModel: String?
    @Published var balance: String?
    private var loadInFlight = false
    private var consecutiveFailures = 0

    func load(computer: SavedComputer, quietly: Bool = false) async {
        if loadInFlight { return }
        loadInFlight = true
        defer { loadInFlight = false }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--dsh-mobile-test-sessions"),
           arguments.indices.contains(index + 1),
           let data = arguments[index + 1].data(using: .utf8),
           let fixture = try? JSONDecoder().decode([RemoteSession].self, from: data) {
            items = fixture
            applyModelCatalog(["groups": [["id": "deepseek", "models": [
                ["id": "deepseek-v41-flash", "name": "DeepSeek Official V41 Flash"]
            ]]], "default": ["provider": "deepseek", "model": "deepseek-v41-flash"]])
            if let index = arguments.firstIndex(of: "--dsh-mobile-test-balance"),
               arguments.indices.contains(index + 1) {
                let recharge = Decimal(string: arguments[index + 1]) ?? 0
                let bonus = arguments.firstIndex(of: "--dsh-mobile-test-bonus")
                    .flatMap { arguments.indices.contains($0 + 1) ? Decimal(string: arguments[$0 + 1]) : nil } ?? 0
                balance = Self.formatBalance(recharge + bonus)
            }
            if let pinsIndex = arguments.firstIndex(of: "--dsh-mobile-test-pins"),
               arguments.indices.contains(pinsIndex + 1) {
                pinnedSessionIds = arguments[pinsIndex + 1].split(separator: ",").map(String.init)
            }
            error = nil
            lastConnectedAt = .now
            return
        }
        #endif
        guard let url = URL(string: computer.url), let origin = URL(string: computer.id) else { return }
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
            guard !Task.isCancelled else { return }
            items = value.items.filter { $0.cwd != nil }
            error = nil
            consecutiveFailures = 0
            lastConnectedAt = .now
            let baseline = try? await readWorkspaces(session: session, origin: origin)
            guard !Task.isCancelled else { return }
            if let baseline {
                workspaces = baseline.items
                pinnedSessionIds = baseline.pinnedSessionIds
            }
            await loadComposerSettings(session: session, origin: origin)
        } catch {
            guard !Task.isCancelled else { return }
            consecutiveFailures += 1
            if !quietly || consecutiveFailures >= 2 {
                lastConnectedAt = nil
                self.error = "无法读取这台电脑的对话：\(error.localizedDescription)"
            }
        }
    }

    private func loadComposerSettings(session: URLSession, origin: URL) async {
        let catalog = try? await rpc(session: session, origin: origin,
                                     method: "session/modelCatalog", args: [:])
        guard !Task.isCancelled else { return }
        if let catalog {
            applyModelCatalog(catalog)
        } else {
            models = []
            defaultModel = nil
        }
        let metadata: [String: Any] = ["version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "", "locale": Locale.current.identifier,
                                       "timezoneOffsetSeconds": TimeZone.current.secondsFromGMT()]
        if let account = try? await rpc(session: session, origin: origin,
                                        method: "account/getBalance", args: ["client": metadata]),
           account["status"] as? String == "ready" {
            guard !Task.isCancelled else { return }
            let wallets = (account["value"] as? [[String: Any]] ?? [])
                + (account["bonusWallets"] as? [[String: Any]] ?? [])
            let total = wallets.reduce(Decimal.zero) { partial, wallet in
                guard wallet["currency"] as? String == "CNY",
                      let amount = wallet["balance"] as? String,
                      let value = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) else {
                    return partial
                }
                return partial + value
            }
            balance = wallets.contains(where: { $0["currency"] as? String == "CNY" })
                ? Self.formatBalance(total) : nil
        } else {
            guard !Task.isCancelled else { return }
            balance = nil
        }
    }

    private func applyModelCatalog(_ catalog: [String: Any]) {
        models = (catalog["groups"] as? [[String: Any]] ?? []).flatMap { group -> [ComposerModel] in
            guard let provider = group["id"] as? String else { return [] }
            return (group["models"] as? [[String: Any]] ?? []).compactMap { item in
                guard let model = item["id"] as? String else { return nil }
                return ComposerModel(provider: provider, model: model,
                                     name: item["name"] as? String ?? model)
            }
        }
        if let fallback = catalog["default"] as? [String: Any],
           let provider = fallback["provider"] as? String,
           let model = fallback["model"] as? String {
            defaultModel = "\(provider)/\(model)"
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
        components.scheme = "wss"
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
            do { try await Task.sleep(nanoseconds: 5_000_000_000) }
            catch { return }
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
               permission: String? = nil, model: ComposerModel? = nil) async -> RemoteSession? {
        guard let origin = URL(string: computer.id), let pairing = URL(string: computer.url) else { return nil }
        starting = true
        defer { starting = false }
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
            let (_, response) = try await session.data(from: pairing)
            if (response as? HTTPURLResponse)?.statusCode == 401 { throw RemoteError.pairingExpired }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RemoteError.unavailable }
            let workspaceId = workspaces.first(where: { $0.path == cwd })?.workspaceId
            let createRequest: [String: Any] = workspaceId.map { ["workspaceId": $0] }
                ?? cwd.map { ["cwd": $0] } ?? [:]
            let created = try await rpc(session: session, origin: origin,
                                        method: "session/create", args: ["request": createRequest])
            guard let sessionId = created["sessionId"] as? String else { throw RemoteError.unavailable }
            if let model {
                _ = try await rpc(session: session, origin: origin, method: "session/selectModel",
                                  args: ["request": ["sessionId": sessionId,
                                                     "provider": model.provider, "model": model.model]])
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
                _ = try await rpc(session: session, origin: origin,
                                  method: "session/prompt", args: ["request": [
                                    "requestId": UUID().uuidString,
                                    "sessionId": sessionId,
                                    "mode": "queue",
                                    "content": [["type": "text", "text": text]],
                                    "clientTimeZone": TimeZone.current.identifier
                                  ]])
            }
            error = nil
            if let model { MobileModelPreference.save(model.id, computerID: computer.id) }
            return RemoteSession(sessionId: sessionId, cwd: cwd,
                                 running: text != nil, updatedAt: Date().timeIntervalSince1970 * 1000,
                                 projections: nil, draftTitle: text.map { String($0.prefix(40)) } ?? "新对话")
        } catch {
            self.error = "无法开始对话：\(error.localizedDescription)"
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
        guard let origin = URL(string: computer.id), let pairing = URL(string: computer.url) else {
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
            case .pairingExpired: return "配对已过期，请从这台电脑重新扫码连接"
            case .server(let message): return message
            }
        }
    }
}

struct RemoteHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    private enum SortMode {
        case priority
        case project
        case recent
    }

    @ObservedObject var connection: MobileConnection
    let computer: SavedComputer
    @StateObject private var sessions = RemoteSessions()
    @State private var showingComputers = false
    @State private var showingSettings = false
    @State private var showingSearch = false
    @State private var search = ""
    @State private var showingRename = false
    @State private var renamed = ""
    @State private var selectedSession: RemoteSession?
    @State private var showingWorkspace = false
    @State private var showingNewConversation = false
    @State private var showingFullWorkspace = false
    @State private var showingTopMenu = false
    @State private var showingConnect = false
    @State private var sortMode: SortMode = .project
    @State private var recentFirst = false
    @AppStorage("mobile.openRemoteOnLaunch") private var openRemoteOnLaunch = true
    @AppStorage("mobile.showContextUsage") private var showContextUsage = false
    @AppStorage("mobile.followUpQueue") private var followUpQueue = true
    @State private var editingConnections = false

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
                            .background(Color(uiColor: .secondarySystemBackground), in: Circle())
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
                            .background(Color(uiColor: .secondarySystemBackground), in: Circle())
                    }
                    .accessibilityLabel("搜索")
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)
                .frame(height: 62)
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
                            Button("重试") { Task { await sessions.load(computer: computer) } }
                                .frame(maxWidth: .infinity)
                        } else if visibleSessions.isEmpty {
                            emptyState(search.isEmpty ? "暂无对话" : "没有匹配的对话",
                                       symbol: "bubble.left")
                        }
                        if let error = sessions.error, !sessions.items.isEmpty {
                            HStack {
                                Text(error).font(.caption).foregroundStyle(.orange)
                                Spacer()
                                Button("重试") { Task { await sessions.load(computer: computer) } }
                            }
                        }
                        if !pinned.isEmpty {
                            sectionHeading("置顶")
                            ForEach(pinned) { item in sessionRow(item, indent: 0) }
                        }
                        if !projects.isEmpty { sectionHeading("项目") }
                        ForEach(projects, id: \.self) { project in
                            HStack(spacing: 9) {
                                Image(systemName: "folder").font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                                Text(projectTitle(project)).font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Button {
                                    Task {
                                        if let session = await sessions.start(text: nil, computer: computer, cwd: project) {
                                            open(session)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 13)).foregroundStyle(.secondary)
                                }
                                .disabled(sessions.starting)
                                .accessibilityLabel("在\(projectTitle(project))新建对话")
                            }
                            .frame(height: 36)
                            ForEach(visibleSessions.filter { $0.cwd == project && !sessions.pinnedSessionIds.contains($0.id) }) { item in
                                sessionRow(item, indent: 24)
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
                .refreshable { await sessions.load(computer: computer) }
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
            .task(id: scenePhase == .active ? computer.url : nil) {
                guard scenePhase == .active else { return }
                await sessions.load(computer: computer)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    if Task.isCancelled { break }
                    await sessions.load(computer: computer, quietly: true)
                }
            }
            .sheet(isPresented: $showingComputers) { computerSheet }
            .sheet(isPresented: $showingSettings) { settingsSheet }
            .sheet(isPresented: $showingConnect) { ConnectView(connection: connection) }
            .sheet(isPresented: $showingFullWorkspace) {
                if let url = URL(string: computer.url) {
                    DshWebView(url: url, onUnauthorized: connection.expireActive)
                }
            }
            .alert("电脑名称", isPresented: $showingRename) {
                TextField("电脑名称", text: $renamed)
                Button("取消", role: .cancel) {}
                Button("保存") { connection.renameActive(renamed) }
            } message: { Text("只修改这台 iPhone 上显示的名称") }
            .navigationDestination(isPresented: $showingWorkspace) {
                if let selected = selectedSession {
                    RemoteChatView(computer: computer, sessionId: selected.sessionId,
                                   title: selected.title, project: selected.project,
                                   onUnauthorized: connection.expireActive)
                }
            }
            .navigationDestination(isPresented: $showingNewConversation) {
                RemoteNewConversationView(connection: connection, computer: computer, sessions: sessions)
            }
            .onChange(of: showingNewConversation) { visible in
                if !visible { Task { await sessions.load(computer: computer) } }
            }
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 23))
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 22, y: 12)
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
                Text(item.title).lineLimit(1)
                Spacer(minLength: 4)
                if item.running { ProgressView().controlSize(.mini) }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.leading, indent)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        .padding(.horizontal, 16).padding(.bottom, 10)
    }

    private var computerSheet: some View {
        NavigationStack {
            List {
                Section("已配对的电脑") {
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
                        Button(editingConnections ? "完成" : "编辑") { editingConnections.toggle() }
                            .padding(.horizontal, 18).frame(height: 43)
                            .background(.white.opacity(0.08), in: Capsule())
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
                                    if editingConnections {
                                        Button(role: .destructive) { connection.remove(item.id) } label: {
                                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                        }.accessibilityLabel("移除\(item.name)")
                                    } else {
                                        Toggle(item.name, isOn: Binding(
                                            get: { connection.activeID == item.id },
                                            set: { enabled in
                                                if enabled { connection.select(item.id) }
                                                else if connection.activeID == item.id { connection.leave() }
                                            }
                                        )).labelsHidden().tint(.green)
                                    }
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
                                     ?? "尚未连通这台电脑")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if sessions.loading { ProgressView().tint(.white) }
                            Button("检查") { Task { await sessions.load(computer: computer) } }
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
                    Button("重命名当前电脑") {
                        showingSettings = false
                        renamed = computer.name
                        showingRename = true
                    }.padding(.horizontal, 15)
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
    @FocusState private var inputFocused: Bool
    @State private var draft = ""
    @State private var selectedWorkspace: String?
    @State private var selectedPermission: String?
    @State private var showingFullWorkspace = false
    @State private var showingProjectMenu = false
    @State private var showingDirectoryBrowser = false
    @State private var createdSession: RemoteSession?
    @State private var showingCreatedSession = false

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
        let lastUsed = MobileModelPreference.read(computerID: computer.id)
        return sessions.models.first(where: { $0.id == lastUsed })
            ?? sessions.models.first(where: { $0.id == sessions.defaultModel })
            ?? sessions.models.first
    }

    var body: some View {
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
                Button {
                    showingProjectMenu = true
                    inputFocused = true
                } label: {
                    selectionRow("folder", workspaceTitle, selectable: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择项目目录")
                selectionRow("laptopcomputer", "在这台电脑工作", selectable: false)
                selectionRow("point.3.connected.trianglepath.dotted", "当前分支", selectable: false)
            }
            .padding(.horizontal, 26)
            Spacer(minLength: 35)
        }
        .foregroundStyle(.primary)
        .background(Color(uiColor: .systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
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
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingDirectoryBrowser) {
            RemoteDirectoryBrowser(computer: computer, sessions: sessions) { path in
                selectedWorkspace = path
                showingDirectoryBrowser = false
            }
        }
        .sheet(isPresented: $showingFullWorkspace) {
            if let url = URL(string: computer.url) {
                DshWebView(url: url, onUnauthorized: connection.expireActive)
            }
        }
        .navigationDestination(isPresented: $showingCreatedSession) {
            if let createdSession {
                RemoteChatView(computer: computer, sessionId: createdSession.sessionId,
                               title: createdSession.title, project: createdSession.project,
                               onUnauthorized: connection.expireActive)
            }
        }
        .task {
            selectedWorkspace = availableWorkspaces.first?.path
            inputFocused = true
        }
        .onChange(of: sessions.workspaces.count) { _ in
            if selectedWorkspace == nil { selectedWorkspace = availableWorkspaces.first?.path }
        }
    }

    private func selectionRow(_ symbol: String, _ title: String, selectable: Bool) -> some View {
        HStack(spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .frame(width: 25)
            Text(title).font(.system(size: 15, weight: .medium)).lineLimit(1)
            if selectable {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .frame(height: 49)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 23))
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 22, y: 12)
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

    private var composer: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("向点点够提问", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 16))
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { startDraft() }
                .accessibilityIdentifier("newConversationInput")
            HStack(spacing: 10) {
                Button { showingFullWorkspace = true } label: {
                    Image(systemName: "plus").font(.system(size: 22))
                }
                .accessibilityLabel("打开完整工作区")
                Menu {
                    Button("仅可查看") { selectedPermission = "read-only" }
                    Button("工作区内修改") { selectedPermission = "workspace-write" }
                    Button("完全权限") { selectedPermission = "danger-full-access" }
                } label: {
                    Image(systemName: selectedPermission == nil ? "shield.lefthalf.filled" : "shield.checkered")
                        .font(.system(size: 17))
                        .foregroundStyle(.orange)
                }
                .accessibilityLabel("访问权限")
                Text(currentModel?.shortName ?? (sessions.loading ? "正在读取模型…" : "模型不可用"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityIdentifier("newConversationModel")
                if let balance = sessions.balance {
                    Text("余额 \(balance)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityIdentifier("newConversationBalance")
                }
                Spacer()
                if inputFocused {
                    Button { inputFocused = false } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 17))
                    }
                    .accessibilityLabel("收起键盘")
                }
                Button { startDraft() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.blue, in: Circle())
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sessions.starting)
                .accessibilityLabel("发送新对话")
            }
        }
        .padding(.horizontal, 17).padding(.vertical, 14)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.black.opacity(0.04)))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .padding(.horizontal, 14).padding(.bottom, 9)
    }

    private func startDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sessions.starting else { return }
        Task {
            if let session = await sessions.start(text: text, computer: computer,
                                                  cwd: selectedWorkspace, permission: selectedPermission,
                                                  model: currentModel) {
                inputFocused = false
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
                    ProgressView("正在读取电脑文件夹…")
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
                Text("在当前电脑目录下新建文件夹，并加入项目列表")
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
            self.error = "无法浏览这台电脑的文件夹，请重试"
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
