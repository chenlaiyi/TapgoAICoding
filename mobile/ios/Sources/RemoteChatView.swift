import SwiftUI
import PhotosUI
import WebKit
import os

private struct ChatLine: Identifiable, Equatable {
    let id: Int
    let role: String
    var text: String
    var reasoning: String?
    var activities: [ChatActivity] = []
    var turn: Int?
    var startedAt: TimeInterval?
    var endedAt: TimeInterval?
    var mergedEventIds: Set<Int> = []

    init(id: Int, role: String, text: String, reasoning: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.reasoning = reasoning
    }
}

private struct ChatActivity: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let category: String
    var finished = false
    var failed = false
}

private struct RemoteModel: Identifiable {
    let id: String
    let provider: String
    let model: String
    let name: String
}

private struct RemotePermission: Identifiable {
    let id: String
    let name: String
    let description: String
}

@MainActor
private final class RemoteChat: ObservableObject {
    private let connectionLog = Logger(subsystem: "com.devtools.terminalSimple", category: "remote-chat")
    @Published var lines: [ChatLine] = []
    @Published var loading = true
    @Published var sending = false
    #if DEBUG
    @Published var testSendPending = false
    private var testSendCompletion: CheckedContinuation<Bool, Never>?

    func completeTestSend() {
        let succeeds = ProcessInfo.processInfo.arguments.contains("controlled-success")
        testSendCompletion?.resume(returning: succeeds)
        testSendCompletion = nil
        testSendPending = false
    }

    func appendTestReply() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--dsh-mobile-test-append"),
              arguments.indices.contains(index + 1),
              let data = arguments[index + 1].data(using: .utf8),
              let replies = try? JSONDecoder().decode([String].self, from: data),
              let reply = replies.first else { return }
        liveActive = true
        liveText += reply
    }
    #endif
    @Published var error: String?
    @Published var models: [RemoteModel] = []
    @Published var selectedModel: String?
    @Published var permissions: [RemotePermission] = []
    @Published var selectedPermission: String?
    @Published var balance: String?
    @Published var balanceDetails: [String] = []
    @Published var tokenUsage: String?
    @Published var contextBudget: String?
    @Published var settingsLoading = false
    @Published var liveText = ""
    @Published var liveReasoning = ""
    @Published var liveActive = false
    @Published var cancelling = false
    @Published var reconnecting = false
    @Published var connected = false
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private let heartbeat = MobileSocketHeartbeat()
    private var generation = UUID()
    private var retryCount = 0
    private var origin: URL?
    private var sessionId: String?

    var running: Bool {
        liveActive || lines.last(where: { $0.role == "turn" })?.endedAt == nil
            && lines.contains(where: { $0.role == "turn" })
    }

    func connect(computer: SavedComputer, sessionId: String, reconnect: Bool = false) async {
        self.sessionId = sessionId
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--dsh-mobile-test-messages"),
           arguments.indices.contains(index + 1),
           let data = arguments[index + 1].data(using: .utf8),
           let fixture = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            lines = fixture.compactMap { item in
                guard let id = item["id"] as? Int,
                      let role = item["role"] as? String,
                      let text = item["text"] as? String else { return nil }
                return ChatLine(id: id, role: role, text: text,
                                reasoning: item["reasoning"] as? String)
            }
            loading = false
            connected = true
            return
        }
        if let index = arguments.firstIndex(of: "--dsh-mobile-test-events"),
           arguments.indices.contains(index + 1),
           let data = arguments[index + 1].data(using: .utf8),
           let fixture = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            var projected: [ChatLine] = []
            for event in fixture { Self.consume(event, into: &projected) }
            lines = projected
            if let streamIndex = arguments.firstIndex(of: "--dsh-mobile-test-stream"),
               arguments.indices.contains(streamIndex + 1),
               let streamData = arguments[streamIndex + 1].data(using: .utf8),
               let stream = try? JSONSerialization.jsonObject(with: streamData) as? [[String: Any]] {
                for frame in stream { receiveStream(frame) }
            }
            loading = false
            connected = true
            return
        }
        #endif
        guard let origin = URL(string: computer.id), let pairing = URL(string: computer.url) else { return }
        disconnect()
        self.origin = origin
        connected = false
        reconnecting = reconnect
        if !reconnect {
            lines = []
            liveActive = false
            liveText = ""
            liveReasoning = ""
            retryCount = 0
            loading = true
            error = nil
        }
        let current = generation
        do {
            let configuration = URLSessionConfiguration.default
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpShouldSetCookies = true
            let cookies = await withCheckedContinuation { continuation in
                WKWebsiteDataStore.default().httpCookieStore.getAllCookies {
                    continuation.resume(returning: $0)
                }
            }
            guard current == generation else { return }
            for cookie in cookies where cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == origin.host {
                configuration.httpCookieStorage?.setCookie(cookie)
            }
            let session = URLSession(configuration: configuration)
            self.session = session
            let (_, response) = try await session.data(from: pairing)
            if (response as? HTTPURLResponse)?.statusCode == 401 { throw ChatFailure.pairingExpired }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ChatFailure.unavailable }
            guard var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else {
                throw ChatFailure.unavailable
            }
            components.scheme = "wss"
            components.path = "/api/remote.mux"
            guard let socketURL = components.url else { throw ChatFailure.unavailable }
            var request = URLRequest(url: socketURL)
            let availableCookies = configuration.httpCookieStorage?.cookies(for: origin) ?? []
            request.setValue(availableCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "),
                             forHTTPHeaderField: "Cookie")
            let socket = session.webSocketTask(with: request)
            socket.maximumMessageSize = 32 * 1_024 * 1_024
            self.socket = socket
            socket.resume()
            let streamId = UUID().uuidString
            let opening: [String: Any] = [
                "type": "open", "streamId": streamId, "endpoint": "session/follow",
                "payload": ["args": ["request": ["address": ["kind": "session", "sessionId": sessionId],
                                                   "assistantStream": true]]]
            ]
            let serialized = try JSONSerialization.data(withJSONObject: opening)
            guard let text = String(data: serialized, encoding: .utf8) else { throw ChatFailure.unavailable }
            try await socket.send(.string(text))
            heartbeat.start(socket: socket) { [weak self, weak socket] in
                guard let self, let socket, self.generation == current,
                      self.socket === socket else { return }
                self.scheduleRetry(computer: computer, generation: current)
            }
            receiveTask = Task { [weak self] in
                guard let self else { return }
                await self.receive(socket: socket, streamId: streamId, computer: computer, generation: current)
            }
        } catch {
            guard current == generation else { return }
            let failure = error as NSError
            connectionLog.error("Connection setup failed: \(failure.domain, privacy: .public) \(failure.code)")
            if let failure = error as? ChatFailure, failure == .pairingExpired {
                loading = false
                reconnecting = false
                self.error = failure.localizedDescription
                return
            }
            scheduleRetry(computer: computer, generation: current)
        }
    }

    private func receive(socket: URLSessionWebSocketTask, streamId: String,
                         computer: SavedComputer, generation current: UUID) async {
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                guard current == generation else { return }
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let bytes): data = bytes
                @unknown default: continue
                }
                guard let frame = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let frameStream = frame["streamId"] as? String else { continue }
                guard frameStream == streamId else { continue }
                if frame["type"] as? String == "error" { throw ChatFailure.unavailable }
                guard frame["type"] as? String == "item",
                      let value = frame["value"] as? [String: Any] else { continue }
                if value["type"] as? String == "snapshot" {
                    let records = value["records"] as? [[String: Any]] ?? []
                    var projected: [ChatLine] = []
                    for record in records {
                        if let event = record["event"] as? [String: Any] {
                            Self.consume(event, into: &projected)
                        }
                    }
                    lines = projected
                    let activeAttempt = (value["assistantStream"] as? [String: Any])?["activeAttempt"] as? [String: Any]
                    liveActive = activeAttempt != nil
                    liveText = ""
                    liveReasoning = ""
                    if let stream = activeAttempt?["stream"] as? [[String: Any]] {
                        liveText = Self.streamText(stream, kind: "text")
                        liveReasoning = Self.streamText(stream, kind: "reasoning")
                    }
                    loading = false
                    connected = true
                    reconnecting = false
                    error = nil
                    retryCount = 0
                    if let values = (value["projections"] as? [String: Any])?["values"] as? [String: Any] {
                        if let selection = values["modelSelection"] as? [String: Any],
                           let next = selection["next"] as? [String: Any],
                           let provider = next["provider"] as? String,
                           let model = next["model"] as? String {
                            selectedModel = "\(provider)/\(model)"
                        }
                        if let selection = values["permissions"] as? [String: Any] {
                            selectedPermission = selection["currentValue"] as? String
                        }
                        if let usage = values["tokenUsage"] as? [String: Any] {
                            let total = ["uncachedInputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens"]
                                .compactMap { usage[$0] as? Int }.reduce(0, +)
                            tokenUsage = "本会话已使用 \(total.formatted()) tokens"
                        }
                        if let pressure = values["contextPressure"] as? [String: Any],
                           let window = pressure["contextWindow"] as? Int,
                           let projected = pressure["projectedTokens"] as? Int {
                            contextBudget = "上下文可用约 \(max(0, window - projected).formatted()) / \(window.formatted()) tokens"
                        }
                    }
                } else if value["type"] as? String == "assistant-stream",
                          let stream = value["frame"] as? [String: Any] {
                    receiveStream(stream)
                } else if let event = value["event"] as? [String: Any] {
                    var projected = lines
                    Self.consume(event, into: &projected)
                    lines = projected
                    if event["type"] as? String == "assistant/message" {
                        liveText = ""
                        liveReasoning = ""
                        liveActive = false
                    }
                    if event["type"] as? String == "turn/end" {
                        liveActive = false
                        liveText = ""
                        liveReasoning = ""
                        cancelling = false
                    }
                }
            }
        } catch {
            if !Task.isCancelled && current == generation && self.socket === socket {
                let failure = error as NSError
                connectionLog.error("WebSocket receive failed: \(failure.domain, privacy: .public) \(failure.code); close code: \(socket.closeCode.rawValue)")
                scheduleRetry(computer: computer, generation: current)
            }
        }
    }

    private func scheduleRetry(computer: SavedComputer, generation current: UUID) {
        guard current == generation else { return }
        heartbeat.stop()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
        loading = false
        connected = false
        reconnecting = true
        retryCount = min(retryCount + 1, 6)
        error = "对话连接中断，正在重连"
        let seconds = min(30, 1 << min(retryCount - 1, 5))
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.generation == current,
                  let sessionId = self.sessionId else { return }
            self.retryTask = nil
            await self.connect(computer: computer, sessionId: sessionId, reconnect: true)
        }
    }

    func retry(computer: SavedComputer, sessionId: String) async {
        retryCount = 0
        reconnecting = true
        error = "正在重连"
        await connect(computer: computer, sessionId: sessionId, reconnect: true)
    }

    private func receiveStream(_ frame: [String: Any]) {
        switch frame["type"] as? String {
        case "start":
            liveText = ""
            liveReasoning = ""
            liveActive = true
        case "chunk":
            guard let chunk = frame["chunk"] as? [String: Any],
                  let text = chunk["text"] as? String else { return }
            if chunk["type"] as? String == "text-delta" { liveText += text }
            if chunk["type"] as? String == "reasoning-delta" { liveReasoning += text }
        case "end":
            if (frame["outcome"] as? [String: Any])?["kind"] as? String == "abandoned" {
                liveText = ""
                liveReasoning = ""
                liveActive = false
            }
        default: break
        }
    }

    private static func consume(_ event: [String: Any], into lines: inout [ChatLine]) {
        guard let type = event["type"] as? String,
              let seq = event["seq"] as? Int,
              let data = event["data"] as? [String: Any] else { return }
        if lines.contains(where: { $0.id == seq }) { return }
        if type == "turn/start", let turn = data["turn"] as? Int {
            var line = ChatLine(id: seq, role: "turn", text: "", reasoning: nil)
            line.turn = turn
            line.startedAt = event["time"] as? TimeInterval
            lines.append(line)
            return
        }
        if type == "turn/end", let turn = data["turn"] as? Int {
            if let index = lines.lastIndex(where: { $0.role == "turn" && $0.turn == turn }) {
                lines[index].endedAt = event["time"] as? TimeInterval ?? 0
            }
            return
        }
        if type == "assistant/attempt" {
            if let index = lines.lastIndex(where: { $0.role == "turn" }),
               lines[index].mergedEventIds.insert(seq).inserted {
                let reasoning = streamText(data["stream"] as? [[String: Any]] ?? [], kind: "reasoning")
                if !reasoning.isEmpty {
                    let previous = lines[index].reasoning ?? ""
                    lines[index].reasoning = previous.isEmpty ? reasoning : previous + "\n\n" + reasoning
                }
            }
            return
        }
        if type == "tool/call", let name = data["name"] as? String,
           let callId = data["callId"] as? String {
            let arguments = (data["arguments"] as? String).flatMap {
                try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
            } ?? [:]
            let detail = ["title", "description", "command", "cmd", "file_path", "path", "query", "pattern"]
                .compactMap { arguments[$0] as? String }.first ?? name
            let activity = ChatActivity(id: callId, name: name, detail: String(detail.prefix(120)),
                                        category: activityCategory(name))
            if let index = lines.lastIndex(where: { $0.role == "turn" }) {
                if !lines[index].activities.contains(where: { $0.id == callId }) {
                    lines[index].activities.append(activity)
                }
                return
            }
            if let index = lines.indices.last, lines[index].role == "activity" {
                lines[index].activities.append(activity)
            } else {
                var line = ChatLine(id: seq, role: "activity", text: "", reasoning: nil)
                line.activities = [activity]
                lines.append(line)
            }
            return
        }
        if type == "tool/result" {
            let message = data["message"] as? [String: Any] ?? [:]
            let callId = (message["source"] as? [String: Any])?["callId"] as? String
                ?? message["toolCallId"] as? String
            guard let callId else { return }
            for index in lines.indices.reversed() {
                guard let activity = lines[index].activities.firstIndex(where: { $0.id == callId }) else { continue }
                lines[index].activities[activity].finished = true
                let blocks = message["content"] as? [[String: Any]] ?? []
                lines[index].activities[activity].failed = message["isError"] as? Bool == true
                    || blocks.contains { $0["isError"] as? Bool == true }
                return
            }
            return
        }
        guard type == "user/message" || type == "assistant/message" else { return }
        if type == "user/message",
           let source = data["source"] as? [String: Any], source["kind"] as? String != "user" {
            return
        }
        let message: [String: Any] = type == "user/message" ? data : (data["message"] as? [String: Any] ?? [:])
        let blocks = message["content"] as? [[String: Any]] ?? []
        let text = blocks.compactMap { block in
            block["type"] as? String == "text" ? block["text"] as? String : nil
        }.joined(separator: "\n\n")
        let blockReasoning = blocks.compactMap { block in
            block["type"] as? String == "reasoning" ? block["text"] as? String : nil
        }.joined(separator: "\n\n")
        let streamReasoning = Self.streamText(data["stream"] as? [[String: Any]] ?? [], kind: "reasoning")
        let reasoning = streamReasoning.isEmpty ? blockReasoning : streamReasoning
        guard !text.isEmpty || !reasoning.isEmpty else { return }
        if type == "assistant/message", !reasoning.isEmpty,
           let turnIndex = lines.lastIndex(where: { $0.role == "turn" }) {
            if lines[turnIndex].mergedEventIds.insert(seq).inserted {
                let previous = lines[turnIndex].reasoning ?? ""
                lines[turnIndex].reasoning = previous.isEmpty ? reasoning : previous + "\n\n" + reasoning
            }
        }
        if type == "assistant/message", text.isEmpty { return }
        if type == "assistant/message", !text.isEmpty,
           let turnIndex = lines.lastIndex(where: { $0.role == "turn" }),
           let assistantIndex = lines.indices.dropFirst(turnIndex + 1).last(where: { lines[$0].role == "assistant" }) {
            if lines[assistantIndex].mergedEventIds.insert(seq).inserted {
                lines[assistantIndex].text += "\n\n" + text
            }
            return
        }
        var line = ChatLine(id: seq, role: type == "user/message" ? "user" : "assistant",
                            text: text, reasoning: nil)
        if type == "assistant/message" { line.mergedEventIds.insert(seq) }
        if type == "user/message", lines.last?.role == "turn" {
            lines.insert(line, at: lines.count - 1)
        } else {
            lines.append(line)
        }
    }

    private static func streamText(_ stream: [[String: Any]], kind: String) -> String {
        stream.map { record in
            if record["type"] as? String == "\(kind)-chunks" {
                return (record["texts"] as? [String] ?? []).joined()
            }
            if record["type"] as? String == "chunk",
               let chunk = record["chunk"] as? [String: Any],
               chunk["type"] as? String == "\(kind)-delta" {
                return chunk["text"] as? String ?? ""
            }
            return ""
        }.joined()
    }

    private static func activityCategory(_ name: String) -> String {
        if name == "read" || name == "read_image" { return "读取文件" }
        if name == "grep" || name == "glob" || name.hasSuffix("_inspect") { return "搜索代码" }
        if name == "write" || name == "edit" || name == "apply_patch" { return "修改文件" }
        if ["bash", "pwsh", "exec_command", "write_stdin"].contains(name) || name.hasPrefix("terminal_") {
            return "运行命令"
        }
        if name == "run_code" { return "运行代码" }
        if name == "web_search" || name == "web_fetch" { return "访问网页" }
        return "调用工具"
    }

    func send(_ text: String, image: Data?, computer: SavedComputer, sessionId: String) async -> Bool {
        guard !sending, connected, !text.isEmpty || image != nil else { return false }
        sending = true
        defer { sending = false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--dsh-mobile-test-send") {
            let delivered = await withCheckedContinuation { continuation in
                testSendCompletion = continuation
                testSendPending = true
            }
            error = delivered ? nil : "发送失败，草稿已保留，请再次发送"
            return delivered
        }
        #endif
        guard let session, let origin = URL(string: computer.id) else { return false }
        do {
            var request = URLRequest(url: origin.appendingPathComponent("api/session/prompt"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var content: [[String: Any]] = []
            if !text.isEmpty { content.append(["type": "text", "text": text]) }
            if let image { content.append(["type": "image", "mediaType": "image/jpeg",
                                           "data": image.base64EncodedString()]) }
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "type": "client-request", "rpcId": UUID().uuidString,
                "method": "session/prompt", "payload": ["args": ["request": [
                    "requestId": UUID().uuidString, "sessionId": sessionId,
                    "mode": "queue", "content": content,
                    "clientTimeZone": TimeZone.current.identifier
                ]]]
            ])
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = body["result"] as? [String: Any], result["ok"] as? Bool == true else {
                throw ChatFailure.unavailable
            }
            error = nil
            return true
        } catch {
            self.error = "发送失败，草稿已保留，请再次发送"
            return false
        }
    }

    func cancel(computer: SavedComputer, sessionId: String) async {
        guard !cancelling else { return }
        cancelling = true
        do {
            _ = try await call("session/cancel", arguments: ["request": ["sessionId": sessionId]], computer: computer)
            error = nil
        } catch {
            cancelling = false
            self.error = "停止失败，请重试"
        }
    }

    private func call(_ method: String, arguments: [String: Any], computer: SavedComputer) async throws -> Any {
        guard let session, let origin = URL(string: computer.id) else { throw ChatFailure.unavailable }
        var request = URLRequest(url: origin.appendingPathComponent("api/\(method)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": "client-request", "rpcId": UUID().uuidString,
            "method": method, "payload": ["args": arguments]
        ])
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = body["result"] as? [String: Any], result["ok"] as? Bool == true,
              let value = result["value"] else { throw ChatFailure.unavailable }
        return value
    }

    func loadSettings(computer: SavedComputer) async {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--dsh-mobile-test-balance"),
           arguments.indices.contains(index + 1) {
            let recharge = arguments[index + 1]
            let bonus = arguments.firstIndex(of: "--dsh-mobile-test-bonus")
                .flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            let wallets: [[String: Any]] = [["balance": recharge, "currency": "CNY"]]
            let bonusWallets: [[String: Any]] = bonus.map { [["balance": $0, "currency": "CNY"]] } ?? []
            balance = Self.availableBalance(wallets + bonusWallets)
            balanceDetails = Self.balanceRows(wallets, label: "充值余额")
                + Self.balanceRows(bonusWallets, label: "赠金余额")
            models = [RemoteModel(id: "deepseek/deepseek-v41-flash", provider: "deepseek",
                                  model: "deepseek-v41-flash", name: "DeepSeek V41 Flash")]
            selectedModel = "deepseek/deepseek-v41-flash"
            permissions = [
                RemotePermission(id: "read-only", name: "仅可查看", description: "只能读取，不允许修改文件"),
                RemotePermission(id: "workspace-write", name: "工作区内修改", description: "可修改工作区文件"),
                RemotePermission(id: "danger-full-access", name: "完全权限", description: "可访问整台电脑")
            ]
            selectedPermission = "danger-full-access"
            return
        }
        #endif
        settingsLoading = true
        defer { settingsLoading = false }
        do {
            async let modelValue = call("session/modelCatalog", arguments: [:], computer: computer)
            async let permissionValue = call("permissionPresets/catalog", arguments: [:], computer: computer)
            if let catalog = try await modelValue as? [String: Any] {
                models = (catalog["groups"] as? [[String: Any]] ?? []).flatMap { group -> [RemoteModel] in
                    guard let provider = group["id"] as? String else { return [] }
                    return (group["models"] as? [[String: Any]] ?? []).compactMap { item in
                        guard let model = item["id"] as? String else { return nil }
                        return RemoteModel(id: "\(provider)/\(model)", provider: provider,
                                           model: model, name: item["name"] as? String ?? model)
                    }
                }
                if selectedModel == nil, let fallback = catalog["default"] as? [String: Any],
                   let provider = fallback["provider"] as? String,
                   let model = fallback["model"] as? String {
                    selectedModel = "\(provider)/\(model)"
                }
            }
            if let catalog = try await permissionValue as? [String: Any] {
                permissions = (catalog["options"] as? [[String: Any]] ?? []).compactMap { item in
                    guard let id = item["value"] as? String else { return nil }
                    let labels: [String: (String, String)] = [
                        "read-only": ("仅可查看", "只能读取，不允许修改文件"),
                        "workspace-write": ("工作区内修改", "可修改工作区文件，超出范围需确认"),
                        "danger-full-access": ("完全权限", "可访问整台电脑，不再逐项请求批准"),
                        "auto": ("自动审核", "由模型审核工具操作，部分操作仍需你确认")
                    ]
                    let display = labels[id]
                    return RemotePermission(id: id, name: display?.0 ?? (item["name"] as? String ?? id),
                                            description: display?.1 ?? (item["description"] as? String ?? ""))
                }
            }
            let metadata: [String: Any] = ["version": "1.0.45", "locale": Locale.current.identifier,
                                           "timezoneOffsetSeconds": TimeZone.current.secondsFromGMT()]
            if let response = try? await call("account/getBalance", arguments: ["client": metadata], computer: computer),
               let result = response as? [String: Any], result["status"] as? String == "ready" {
                let wallets = result["value"] as? [[String: Any]] ?? []
                let bonusWallets = result["bonusWallets"] as? [[String: Any]] ?? []
                balance = Self.availableBalance(wallets + bonusWallets)
                balanceDetails = Self.balanceRows(wallets, label: "充值余额")
                    + Self.balanceRows(bonusWallets, label: "赠金余额")
            } else {
                balance = nil
                balanceDetails = []
            }
            error = nil
        } catch {
            self.error = "无法读取模型或权限设置，请重试"
        }
    }

    private static func availableBalance(_ wallets: [[String: Any]]) -> String? {
        var amounts: [String: Decimal] = [:]
        for wallet in wallets {
            guard let amount = wallet["balance"] as? String,
                  let currency = wallet["currency"] as? String,
                  let value = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) else { continue }
            amounts[currency, default: 0] += value
        }
        guard let currency = amounts["CNY"] == nil ? amounts.keys.sorted().first : "CNY",
              let amount = amounts[currency] else { return nil }
        return formatBalance(NSDecimalNumber(decimal: amount).stringValue, currency: currency)
    }

    private static func balanceRows(_ wallets: [[String: Any]], label: String) -> [String] {
        wallets.compactMap { wallet in
            guard let amount = wallet["balance"] as? String,
                  let currency = wallet["currency"] as? String else { return nil }
            return "\(label) \(formatBalance(amount, currency: currency))"
        }
    }

    private static func formatBalance(_ amount: String, currency: String) -> String {
        let symbol = currency == "CNY" ? "¥" : currency == "USD" ? "$" : "\(currency) "
        guard let value = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) else {
            return "\(symbol)\(amount)"
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "\(symbol)\(formatter.string(from: NSDecimalNumber(decimal: value)) ?? amount)"
    }

    func selectModel(_ model: RemoteModel, computer: SavedComputer, sessionId: String) async {
        do {
            _ = try await call("session/selectModel", arguments: ["request": ["sessionId": sessionId,
                "provider": model.provider, "model": model.model]], computer: computer)
            selectedModel = model.id
            MobileModelPreference.save(model.id, computerID: computer.id)
            error = nil
        } catch { self.error = "模型切换失败，请重试" }
    }

    func selectPermission(_ permission: RemotePermission, computer: SavedComputer, sessionId: String) async {
        do {
            let value = try await call("commands/execute", arguments: ["agentId": sessionId,
                "line": "/permission \(permission.id)", "submittedAttachments": []], computer: computer)
            guard let response = value as? [String: Any],
                  let result = response["result"] as? [String: Any],
                  result["kind"] as? String == "success" else { throw ChatFailure.unavailable }
            selectedPermission = permission.id
            error = nil
        } catch { self.error = "访问权限切换失败，请重试" }
    }

    func disconnect() {
        #if DEBUG
        testSendCompletion?.resume(returning: false)
        testSendCompletion = nil
        testSendPending = false
        #endif
        generation = UUID()
        heartbeat.stop()
        retryTask?.cancel()
        retryTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
        origin = nil
        cancelling = false
        connected = false
        reconnecting = false
    }

    private enum ChatFailure: LocalizedError, Equatable {
        case unavailable
        case pairingExpired
        var errorDescription: String? {
            switch self {
            case .unavailable: "连接已失效或服务器不可用"
            case .pairingExpired: "配对已过期，请从这台 Mac 重新扫码连接"
            }
        }
    }
}

struct RemoteChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    let computer: SavedComputer
    let sessionId: String
    let title: String
    let project: String
    let onUnauthorized: () -> Void
    @StateObject private var chat = RemoteChat()
    @State private var draft = ""
    @State private var showingWorkspace = false
    @State private var showingSettings = false
    @State private var showingModels = false
    @State private var showingAddActions = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var attachedImage: Data?
    @State private var pendingPermission: RemotePermission?
    @FocusState private var composerFocused: Bool
    @State private var followingLatest = true
    @State private var bottomVisible = true
    @State private var bottomPosition = CGFloat.infinity
    @State private var draggingTranscript = false
    @State private var scrollRequestCount = 0
    private let bottomAnchor = "chat-bottom"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("返回")
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    Text("\(project) · \(computer.name)")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "square.and.pencil").font(.system(size: 19))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("新建对话")
                Menu {
                    Button("模型、权限与额度") { showingSettings = true }
                    Button("完整工作区") { showingWorkspace = true }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 20, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("更多")
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            ScrollViewReader { reader in
                GeometryReader { viewport in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                if chat.loading { ProgressView().frame(maxWidth: .infinity).padding(.top, 60) }
                                ForEach(chat.lines) { line in
                                    chatRow(line)
                                        .id(line.id)
                                }
                            }
                            if chat.liveActive {
                                if chat.liveText.isEmpty, !chat.lines.contains(where: { $0.role == "turn" }) {
                                    Label("正在思考", systemImage: "sparkle")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else if !chat.liveText.isEmpty {
                                    AssistantMessageView(text: chat.liveText, reasoning: nil, showCopy: false)
                                }
                            }
                            Color.clear.frame(height: 1)
                                .id(bottomAnchor)
                                .background {
                                    GeometryReader { anchor in
                                        Color.clear.preference(key: ChatBottomPreference.self,
                                                               value: anchor.frame(in: .named("chatTranscript")))
                                    }
                                }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 16)
                    }
                    .coordinateSpace(name: "chatTranscript")
                    .accessibilityIdentifier("chatTranscript")
                    .scrollDismissesKeyboard(.interactively)
                    .onPreferenceChange(ChatBottomPreference.self) { frame in
                        guard !frame.isNull, !frame.isEmpty else { return }
                        let movedTowardBottom = frame.minY < bottomPosition
                        bottomPosition = frame.minY
                        bottomVisible = frame.minY <= viewport.size.height && frame.maxY >= 0
                        if bottomVisible && movedTowardBottom && !draggingTranscript { followingLatest = true }
                        if followingLatest && !bottomVisible { reader.scrollTo(bottomAnchor, anchor: .bottom) }
                    }
                    .simultaneousGesture(DragGesture().onChanged { _ in
                        draggingTranscript = true
                        followingLatest = false
                    }.onEnded { gesture in
                        draggingTranscript = false
                        if gesture.translation.height < 0 && bottomVisible { followingLatest = true }
                    })
                    .onChange(of: chat.lines) { _ in
                        if followingLatest { reader.scrollTo(bottomAnchor, anchor: .bottom) }
                    }
                    .onChange(of: chat.liveText) { _ in
                        if followingLatest { reader.scrollTo(bottomAnchor, anchor: .bottom) }
                    }
                    .onChange(of: chat.loading) { loading in
                        if !loading && followingLatest { reader.scrollTo(bottomAnchor, anchor: .bottom) }
                    }
                    .onChange(of: viewport.size.height) { _ in
                        if followingLatest { reader.scrollTo(bottomAnchor, anchor: .bottom) }
                    }
                    .onChange(of: scrollRequestCount) { _ in
                        followingLatest = true
                        withAnimation { reader.scrollTo(bottomAnchor, anchor: .bottom) }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !bottomVisible && !followingLatest && !chat.loading {
                            Button {
                                followingLatest = true
                                withAnimation { reader.scrollTo(bottomAnchor, anchor: .bottom) }
                            } label: {
                                Label("回到最新", systemImage: "arrow.down")
                                    .font(.subheadline)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 44)
                                    .background(.regularMaterial, in: Capsule())
                                    .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                            }
                            .accessibilityIdentifier("chatJumpToLatest")
                            .padding(12)
                        }
                    }
                }
            }
            if let error = chat.error {
                HStack(spacing: 8) {
                    Text(error).font(.caption).foregroundStyle(.orange)
                    if !chat.reconnecting && !chat.connected {
                        Button("重试") {
                            Task { await chat.retry(computer: computer, sessionId: sessionId) }
                        }
                        .font(.caption)
                        .frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, 16)
            }
            VStack(alignment: .leading, spacing: 8) {
                if attachedImage != nil {
                    HStack {
                        Label("已添加图片", systemImage: "photo")
                            .font(.caption)
                        Spacer()
                        Button("移除") { attachedImage = nil }.font(.caption)
                    }
                }
                HStack(spacing: 8) {
                    modelBadge
                    balanceBadge
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        if !composerFocused { addMenu }
                        composerInput
                            .padding(.leading, composerFocused ? 7 : 0)
                        if !composerFocused { sendButton }
                    }
                    if composerFocused {
                        HStack(spacing: 8) {
                            addMenu
                            permissionButton
                            Spacer(minLength: 0)
                            Button { composerFocused = false } label: {
                                Image(systemName: "keyboard.chevron.compact.down")
                                    .font(.system(size: 17))
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("收起键盘")
                            sendButton
                        }
                    }
                }
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: composerFocused ? 23 : 30))
                .overlay(RoundedRectangle(cornerRadius: composerFocused ? 23 : 30).stroke(Color(uiColor: .separator).opacity(0.3)))
                .shadow(color: .black.opacity(0.07), radius: 14, y: 5)
            }
            .padding(.horizontal, 15).padding(.bottom, 10)
        }
        .background(Color(uiColor: .systemBackground))
        .toolbar(.hidden, for: .navigationBar)
        .task(id: sessionId) {
            await chat.connect(computer: computer, sessionId: sessionId)
            await chat.loadSettings(computer: computer)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && !chat.connected && !chat.loading {
                Task { await chat.retry(computer: computer, sessionId: sessionId) }
            }
        }
        .onChange(of: selectedPhoto) { item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data)?.jpegData(compressionQuality: 0.8) {
                    attachedImage = image
                }
            }
        }
        .onDisappear { chat.disconnect() }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            HStack {
                if chat.testSendPending {
                    Button("完成测试发送") { chat.completeTestSend() }
                }
                if ProcessInfo.processInfo.arguments.contains("--dsh-mobile-test-append") {
                    Button("追加测试回复") { chat.appendTestReply() }
                }
            }
            .font(.caption).padding(.top, 66)
        }
        #endif
        .sheet(isPresented: $showingWorkspace) {
            if let url = URL(string: computer.url) {
                DshWebView(url: url, sessionId: sessionId, onUnauthorized: onUnauthorized)
            }
        }
        .sheet(isPresented: $showingAddActions) {
            NavigationStack {
                List {
                    Button("选择模型与权限", systemImage: "slider.horizontal.3") {
                        showingAddActions = false
                        showingSettings = true
                    }
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("添加图片", systemImage: "photo")
                    }
                    Button("添加文件", systemImage: "paperclip") {
                        showingAddActions = false
                        showingWorkspace = true
                    }
                    Button("完整工作区", systemImage: "rectangle.on.rectangle") {
                        showingAddActions = false
                        showingWorkspace = true
                    }
                }
                .navigationTitle("添加到对话")
                .toolbar { Button("完成") { showingAddActions = false } }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingModels) {
            NavigationStack {
                List {
                    if chat.models.isEmpty {
                        Text("暂无可选模型").foregroundStyle(.secondary)
                    }
                    ForEach(chat.models) { model in
                        Button {
                            showingModels = false
                            Task { await chat.selectModel(model, computer: computer, sessionId: sessionId) }
                        } label: {
                            HStack {
                                Text(shortModelName(model.name)).foregroundStyle(.primary)
                                Spacer()
                                if chat.selectedModel == model.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
                .navigationTitle("选择模型")
                .toolbar { Button("完成") { showingModels = false } }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                Form {
                    Section("模型") {
                        if chat.models.isEmpty { Text("暂无可选模型").foregroundStyle(.secondary) }
                        ForEach(chat.models) { model in
                            Button {
                                Task { await chat.selectModel(model, computer: computer, sessionId: sessionId) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(model.name).foregroundStyle(.primary)
                                        Text(model.provider).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if chat.selectedModel == model.id { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                    Section("访问权限") {
                        if chat.permissions.isEmpty { Text("暂无权限选项").foregroundStyle(.secondary) }
                        ForEach(chat.permissions) { permission in
                            Button {
                                pendingPermission = permission
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(permission.name).foregroundStyle(.primary)
                                        if !permission.description.isEmpty {
                                            Text(permission.description).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if chat.selectedPermission == permission.id { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                    Section("模型额度") {
                        Text(chat.balance ?? "当前账号未提供可用余额")
                        ForEach(Array(chat.balanceDetails.enumerated()), id: \.offset) { _, detail in
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                        if let budget = chat.contextBudget { Text(budget).font(.caption).foregroundStyle(.secondary) }
                        if let usage = chat.tokenUsage { Text(usage).font(.caption).foregroundStyle(.secondary) }
                    }
                    if chat.settingsLoading { ProgressView() }
                }
                .navigationTitle("会话设置")
                .toolbar { Button("完成") { showingSettings = false } }
                .confirmationDialog("切换访问权限", isPresented: Binding(
                    get: { pendingPermission != nil },
                    set: { if !$0 { pendingPermission = nil } }
                ), titleVisibility: .visible) {
                    if let permission = pendingPermission {
                        Button("切换为 \(permission.name)") {
                            Task { await chat.selectPermission(permission, computer: computer, sessionId: sessionId) }
                            pendingPermission = nil
                        }
                    }
                    Button("取消", role: .cancel) { pendingPermission = nil }
                } message: {
                    Text(pendingPermission?.description ?? "此设置会影响当前会话的工具访问范围")
                }
            }
            .task { await chat.loadSettings(computer: computer) }
        }
    }

    private var composerInput: some View {
        TextField("在 \(computer.name) 上工作", text: $draft, axis: .vertical)
            .font(.body)
            .lineLimit(1...5)
            .focused($composerFocused)
            .accessibilityIdentifier("chatComposerInput")
    }

    private var modelBadge: some View {
        Button {
            composerFocused = false
            showingModels = true
        } label: {
            HStack(spacing: 4) {
                Text(selectedModelName)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.down").font(.system(size: 9))
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("选择模型")
    }

    private var selectedModelName: String {
        guard let selectedModel = chat.selectedModel else { return "选择模型" }
        let model = chat.models.first { $0.id == selectedModel }
        let modelID = model?.model ?? selectedModel.split(separator: "/").last.map(String.init) ?? selectedModel
        return mobileModelDisplayName(model?.name ?? modelID, modelID: modelID)
    }

    private func shortModelName(_ name: String) -> String {
        let modelID = chat.models.first(where: { $0.name == name })?.model ?? name
        return mobileModelDisplayName(name, modelID: modelID)
    }

    @ViewBuilder private var balanceBadge: some View {
        if let balance = chat.balance, !balance.isEmpty {
            Text("余额 \(balance)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("availableBalance")
        }
    }

    private var permissionButton: some View {
        Menu {
            Picker("访问权限", selection: Binding(
                get: { chat.selectedPermission ?? "" },
                set: { id in
                    if let permission = chat.permissions.first(where: { $0.id == id }),
                       chat.selectedPermission != id {
                        Task { await chat.selectPermission(permission, computer: computer, sessionId: sessionId) }
                    }
                }
            )) {
                ForEach(Array(chat.permissions.filter {
                    ["read-only", "workspace-write", "danger-full-access"].contains($0.id)
                }.reversed())) { permission in
                    Label(permission.name, systemImage: permissionSymbol(permission.id))
                        .tag(permission.id)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "shield.lefthalf.filled")
                Text(chat.permissions.first { $0.id == chat.selectedPermission }?.name ?? "访问权限")
                    .lineLimit(1)
                Image(systemName: "chevron.up").font(.system(size: 9))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .tint(Color(uiColor: .secondaryLabel))
        .accessibilityLabel("访问权限")
    }

    private func permissionSymbol(_ id: String) -> String {
        switch id {
        case "read-only": "eye"
        case "workspace-write": "pencil.line"
        default: "shield.lefthalf.filled"
        }
    }

    private var addMenu: some View {
        Button { showingAddActions = true } label: {
            Image(systemName: "plus").font(.system(size: 22, weight: .light))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("添加与会话设置")
    }

    private var sendButton: some View {
        let busy = chat.sending || chat.cancelling
        let enabled = chat.running ? (!busy && chat.connected) :
            ((!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachedImage != nil)
             && !chat.sending && !chat.loading && chat.connected)
        return Button {
            if chat.running {
                Task { await chat.cancel(computer: computer, sessionId: sessionId) }
                return
            }
            let submittedDraft = draft
            let submittedImage = attachedImage
            let text = submittedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            scrollRequestCount += 1
            Task {
                if await chat.send(text, image: submittedImage, computer: computer, sessionId: sessionId) {
                    if draft == submittedDraft { draft = "" }
                    if attachedImage == submittedImage { attachedImage = nil }
                }
            }
        } label: {
            Group {
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: chat.running ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 34, height: 34)
            .background(enabled || busy ? Color.blue : Color(uiColor: .tertiaryLabel), in: Circle())
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .accessibilityLabel(chat.sending ? "正在发送" : chat.cancelling ? "正在停止" : chat.running ? "停止运行" : "发送")
    }

    private func chatRow(_ line: ChatLine) -> some View {
        HStack(alignment: .top) {
            if line.role == "user" { Spacer(minLength: 45) }
            if line.role == "activity" {
                ActivityGroupView(activities: line.activities)
            } else if line.role == "turn" {
                TurnProcessView(startedAt: line.startedAt, endedAt: line.endedAt,
                                activities: line.activities, reasoning: line.reasoning,
                                liveReasoning: chat.lines.last(where: { $0.role == "turn" })?.id == line.id
                                    ? chat.liveReasoning : "")
            } else if line.role == "assistant" {
                AssistantMessageView(text: line.text, reasoning: line.reasoning,
                    showCopy: isLastAssistantInTurn(line.id))
            } else {
                Text(line.text)
                    .font(.system(size: 16, weight: .medium)).lineSpacing(5)
                    .foregroundStyle(colorScheme == .dark ? .white : Color(red: 0.05, green: 0.42, blue: 0.76))
                    .textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(colorScheme == .dark ? Color(red: 0.02, green: 0.29, blue: 0.53)
                                : Color(red: 0.88, green: 0.95, blue: 1),
                                in: RoundedRectangle(cornerRadius: 20))
            }
            if line.role != "user" { Spacer(minLength: 20) }
        }
    }

    private func isLastAssistantInTurn(_ id: Int) -> Bool {
        guard let index = chat.lines.firstIndex(where: { $0.id == id }) else { return true }
        for later in chat.lines.dropFirst(index + 1) {
            if later.role == "user" || later.role == "turn" { break }
            if later.role == "assistant" { return false }
        }
        return true
    }
}

private struct ActivityGroupView: View {
    let activities: [ChatActivity]

    private var title: String {
        if let running = activities.last(where: { !$0.finished }) {
            return "正在\(running.category)"
        }
        let categories = Array(Set(activities.map(\.category))).sorted { first, second in
            let left = activities.firstIndex(where: { $0.category == first }) ?? 0
            let right = activities.firstIndex(where: { $0.category == second }) ?? 0
            return left < right
        }
        let labels = categories.prefix(2).map { category in
            let count = activities.filter { $0.category == category }.count
            switch category {
            case "读取文件": return "已读取 \(count) 个文件"
            case "搜索代码": return "已搜索 \(count) 次"
            case "修改文件": return "已修改 \(count) 个文件"
            case "运行命令": return "已运行 \(count) 条命令"
            case "运行代码": return "已运行 \(count) 次代码"
            case "访问网页": return "已访问 \(count) 个网页"
            default: return "已调用 \(count) 次工具"
            }
        }
        return labels.joined(separator: "，")
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(activities) { activity in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: activity.failed ? "exclamationmark.circle" :
                                activity.finished ? "checkmark.circle" : "circle.dotted")
                            .foregroundStyle(activity.failed ? Color.orange : Color(uiColor: .secondaryLabel))
                        Text(activity.detail).lineLimit(3)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text(title)
            }
            .font(.system(size: 13))
            .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .tint(Color(uiColor: .secondaryLabel))
    }
}

private struct TurnProcessView: View {
    let startedAt: TimeInterval?
    let endedAt: TimeInterval?
    let activities: [ChatActivity]
    let reasoning: String?
    let liveReasoning: String
    @State private var expanded = false

    private var processSummary: String {
        let count = activities.count
        let failed = activities.filter(\.failed).count
        if count == 0 { return endedAt == nil ? "正在思考" : "查看过程" }
        return failed == 0 ? "过程 · \(count) 项操作" : "过程 · \(count) 项操作，\(failed) 项失败"
    }

    private func title(now: Date) -> String {
        guard let startedAt, startedAt > 0 else {
            return endedAt == nil ? "正在处理" : "已完成工作"
        }
        let end = endedAt ?? now.timeIntervalSince1970 * 1000
        let seconds = max(0, Int((end - startedAt) / 1000))
        let duration = seconds < 60 ? "\(seconds) 秒" : "\(seconds / 60) 分 \(seconds % 60) 秒"
        return endedAt == nil ? "已运行 \(duration)" : "用时 \(duration)"
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 10) {
                Text(title(now: context.date))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Divider()
                DisclosureGroup(isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        let processText = [reasoning, liveReasoning.isEmpty ? nil : liveReasoning]
                            .compactMap { $0 }.joined(separator: "\n\n")
                        if !processText.isEmpty {
                            Text(processText)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        ForEach(activities) { activity in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: activity.failed ? "exclamationmark.circle" :
                                        activity.finished ? "checkmark.circle" : "circle.dotted")
                                Text(activity.detail)
                                    .lineLimit(3)
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(activity.failed ? Color.orange : Color(uiColor: .secondaryLabel))
                        }
                    }
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label(processSummary, systemImage: "list.bullet.clipboard")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                .tint(Color(uiColor: .secondaryLabel))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ChatBottomPreference: PreferenceKey {
    static var defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
