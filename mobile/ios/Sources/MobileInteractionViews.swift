import SwiftUI
import WebKit

/// Owns pending Host confirmations for the whole mobile connection, including the remote home.
@MainActor
final class MobileInteractionCenter: ObservableObject {
    struct PendingApproval: Identifiable {
        let id: String
        let agentId: String
        let prompt: RemoteApproval
    }
    struct PendingQuestion: Identifiable {
        let id: String
        let agentId: String
        let prompt: RemoteQuestion
    }

    @Published var approvals: [PendingApproval] = []
    @Published var questions: [PendingQuestion] = []
    @Published var error: String?
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var clientId: String?
    private var origin: URL?
    private var generation = UUID()
    private let heartbeat = MobileSocketHeartbeat()
    private var retryTask: Task<Void, Never>?
    private var retryCount = 0
    #if DEBUG
    private var fixture = false
    #endif

    func connect(computer: SavedComputer?, reconnect: Bool = false) async {
        disconnect(resetRetry: !reconnect)
        guard let computer, let origin = URL(string: computer.id),
              let pairing = URL(string: computer.url) else { return }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--dsh-mobile-test-global-approval"),
           arguments.indices.contains(index + 1),
           let data = arguments[index + 1].data(using: .utf8),
           let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let eventId = item["eventId"] as? String,
           let agentId = item["agentId"] as? String,
           let toolName = item["toolName"] as? String {
            fixture = true
            approvals = [PendingApproval(id: eventId, agentId: agentId,
                prompt: RemoteApproval(id: eventId, toolName: toolName,
                                       reason: item["reason"] as? String))]
            return
        }
        if let index = arguments.firstIndex(of: "--dsh-mobile-test-global-question"),
           arguments.indices.contains(index + 1),
           let data = arguments[index + 1].data(using: .utf8),
           let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let eventId = item["eventId"] as? String,
           let agentId = item["agentId"] as? String {
            let items = (item["questions"] as? [[String: Any]] ?? [])
                .compactMap(RemoteQuestionItem.init(wire:))
            fixture = true
            questions = [PendingQuestion(id: eventId, agentId: agentId,
                prompt: RemoteQuestion(id: eventId, items: items))]
            return
        }
        #endif
        let current = generation
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
        self.origin = origin
        do {
            let (_, response) = try await session.data(from: pairing)
            if (response as? HTTPURLResponse)?.statusCode == 401 {
                error = "配对已过期，请从这台 Mac 重新扫码连接"
                session.invalidateAndCancel()
                self.session = nil
                return
            }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            guard current == generation,
                  var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else { return }
            components.scheme = "wss"
            components.path = "/api/remote.mux"
            guard let url = components.url else { return }
            var request = URLRequest(url: url)
            let cookieHeader = configuration.httpCookieStorage?.cookies(for: origin)?
                .map { "\($0.name)=\($0.value)" }.joined(separator: "; ") ?? ""
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            let socket = session.webSocketTask(with: request)
            self.socket = socket
            socket.resume()
            let streamId = UUID().uuidString
            let opening: [String: Any] = ["type": "open", "streamId": streamId,
                "endpoint": "$events", "payload": ["args": [:]]]
            let data = try JSONSerialization.data(withJSONObject: opening)
            try await socket.send(.string(String(decoding: data, as: UTF8.self)))
            heartbeat.start(socket: socket) { [weak self, weak socket] in
                guard let self, let socket, self.generation == current,
                      self.socket === socket else { return }
                socket.cancel(with: .goingAway, reason: nil)
            }
            while current == generation {
                let message = try await socket.receive()
                let bytes: Data
                switch message {
                case .string(let text): bytes = Data(text.utf8)
                case .data(let data): bytes = data
                @unknown default: continue
                }
                guard let frame = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                      frame["streamId"] as? String == streamId else { continue }
                if frame["type"] as? String == "error" { throw URLError(.networkConnectionLost) }
                if frame["type"] as? String == "item",
                   let value = frame["value"] as? [String: Any] { receive(value) }
            }
        } catch {
            if current == generation {
                scheduleRetry(computer: computer, generation: current)
            }
        }
    }

    private func receive(_ value: [String: Any]) {
        switch value["type"] as? String {
        case "ready":
            clientId = value["clientId"] as? String
            retryCount = 0
            error = nil
        case "cancel":
            guard let id = value["eventId"] as? String else { return }
            approvals.removeAll { $0.id == id }
            questions.removeAll { $0.id == id }
        case "waterfall":
            guard let id = value["eventId"] as? String,
                  let agentId = value["agentId"] as? String,
                  let event = value["event"] as? String,
                  let request = value["request"] as? [String: Any] else { return }
            if event == "approval/request", let toolName = request["toolName"] as? String {
                guard !approvals.contains(where: { $0.id == id }) else { return }
                let localized = (request["displayReason"] as? [String: String])?["zh"]
                approvals.append(PendingApproval(id: id, agentId: agentId,
                    prompt: RemoteApproval(id: id, toolName: toolName,
                                           reason: localized ?? request["reason"] as? String)))
            } else if event == "user-questions/request" {
                let items = (request["questions"] as? [[String: Any]] ?? [])
                    .compactMap(RemoteQuestionItem.init(wire:))
                guard !items.isEmpty, !questions.contains(where: { $0.id == id }) else { return }
                questions.append(PendingQuestion(id: id, agentId: agentId,
                    prompt: RemoteQuestion(id: id, items: items)))
            }
        default: break
        }
    }

    func answer(_ pending: PendingApproval, allowed: Bool) async {
        let outcome: [String: Any] = ["kind": "result", "value": allowed ? "allowed-once" : "rejected"]
        if await send(id: pending.id, outcome: outcome) {
            approvals.removeAll { $0.id == pending.id }
        }
    }

    func answer(_ pending: PendingQuestion, answers: [RemoteQuestionAnswer]) async {
        let encoded: [[String: Any]] = answers.map { answer in
            var item: [String: Any] = ["id": answer.id, "selected": answer.selected]
            if let custom = answer.custom { item["custom"] = custom }
            return item
        }
        if await send(id: pending.id, outcome: ["kind": "result", "value": ["answers": encoded]]) {
            questions.removeAll { $0.id == pending.id }
        }
    }

    func delegate(_ id: String) async {
        if await send(id: id, outcome: ["kind": "next"]) {
            approvals.removeAll { $0.id == id }
            questions.removeAll { $0.id == id }
        }
    }

    private func send(id: String, outcome: [String: Any]) async -> Bool {
        #if DEBUG
        if fixture { return true }
        #endif
        guard let session, let origin, let clientId else {
            error = "确认尚未连接，请重试"
            return false
        }
        var request = URLRequest(url: origin.appendingPathComponent("api/$events/result"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "type": "client-request", "rpcId": UUID().uuidString, "method": "$events/result",
                "payload": ["args": ["clientId": clientId, "eventId": id, "outcome": outcome]]
            ])
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = body["result"] as? [String: Any],
                  result["ok"] as? Bool == true else {
                error = "确认未能送达电脑，请重试"
                return false
            }
            error = nil
            return true
        } catch {
            self.error = "确认未能送达电脑，请重试"
            return false
        }
    }

    private func scheduleRetry(computer: SavedComputer, generation current: UUID) {
        guard current == generation else { return }
        heartbeat.stop()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
        clientId = nil
        error = "确认连接中断，正在重连"
        retryCount = min(retryCount + 1, 6)
        let seconds = min(30, 1 << min(retryCount - 1, 5))
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.generation == current else { return }
            self.retryTask = nil
            await self.connect(computer: computer, reconnect: true)
        }
    }

    private func disconnect(resetRetry: Bool = true) {
        generation = UUID()
        heartbeat.stop()
        retryTask?.cancel()
        retryTask = nil
        if resetRetry { retryCount = 0 }
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
        clientId = nil
        origin = nil
        approvals = []
        questions = []
        error = nil
        #if DEBUG
        fixture = false
        #endif
    }
}

/// Displays pending confirmations above every native mobile route.
struct MobileInteractionOverlay: View {
    @ObservedObject var center: MobileInteractionCenter
    let computer: SavedComputer?

    var body: some View {
        if let approval = center.approvals.first {
            prompt {
                Text("来自 \(computer?.name ?? "Mac") 的开发确认")
                    .font(.caption).foregroundStyle(.secondary)
                ApprovalPromptCard(approval: approval.prompt,
                    onAllow: { Task { await center.answer(approval, allowed: true) } },
                    onReject: { Task { await center.answer(approval, allowed: false) } },
                    onDelegate: { Task { await center.delegate(approval.id) } })
            }
        } else if let question = center.questions.first {
            prompt {
                Text("来自 \(computer?.name ?? "Mac") 的问题")
                    .font(.caption).foregroundStyle(.secondary)
                QuestionPromptCard(question: question.prompt,
                    onSubmit: { answers in Task { await center.answer(question, answers: answers) } },
                    onDelegate: { Task { await center.delegate(question.id) } })
            }
        }
    }

    private func prompt<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                    if let error = center.error {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(16)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: 520)
        }
        .accessibilityIdentifier("mobileInteractionOverlay")
    }
}

/// One pending `approval/request` the Host forwarded to this Remote Client.
struct RemoteApproval: Identifiable {
    /// Host correlation id answered back through `$events/result`.
    let id: String
    /// Tool whose operation needs the decision.
    let toolName: String
    /// The asker's human-readable reason, when it supplied one.
    let reason: String?
}

/// One question of a pending `user-questions/request`.
struct RemoteQuestionItem: Identifiable {
    let id: String
    let question: String
    let detail: String?
    let header: String?
    let options: [String]
    let multiSelect: Bool
    /// Option label a declared `plan-review` intent approves with.
    let approveLabel: String?

    /**
     Parse one question object carried by the forwarded request.
     @param wire - the question as the Host serialized it.
     @returns nil when the object carries no stable id or question text.
     */
    init?(wire: [String: Any]) {
        guard let id = wire["id"] as? String, let question = wire["question"] as? String else { return nil }
        self.id = id
        self.question = question
        detail = wire["detail"] as? String
        header = wire["header"] as? String
        options = (wire["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }
        multiSelect = wire["multiSelect"] as? Bool == true
        approveLabel = (wire["intent"] as? [String: Any])?["approve"] as? String
    }
}

/// One pending `user-questions/request` the Host forwarded to this Remote Client.
struct RemoteQuestion: Identifiable {
    /// Host correlation id answered back through `$events/result`.
    let id: String
    let items: [RemoteQuestionItem]
}

/// One question's answer, encoded for `AskUserQuestionAnswerItem`.
struct RemoteQuestionAnswer {
    let id: String
    let selected: [String]
    let custom: String?
}

/// Local answer state of one question while the prompt card is open.
private struct QuestionDraft {
    var selected: [String] = []
    var custom = ""
    var skipped = false

    var answered: Bool {
        !selected.isEmpty || !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var completed: Bool { answered || skipped }
}

/// The decision the active prompt card is asking for.
private struct InteractionCard<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .semibold))
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.35)))
    }
}

/// Approval prompt: one tool operation waits for a decision only this phone can give.
struct ApprovalPromptCard: View {
    let approval: RemoteApproval
    let onAllow: () -> Void
    let onReject: () -> Void
    let onDelegate: () -> Void

    var body: some View {
        InteractionCard(title: "需要你的确认", symbol: "hand.raised.fill") {
            VStack(alignment: .leading, spacing: 4) {
                Text(approval.toolName).font(.system(size: 15, weight: .medium))
                if let reason = approval.reason, !reason.isEmpty {
                    Text(reason).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button(action: onReject) {
                    Text("拒绝").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                Button(action: onAllow) {
                    Text("允许一次").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .font(.system(size: 15, weight: .medium))
            Button("改在电脑上确认", action: onDelegate)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

/// Question prompt: `ask_user_question` and plan review wait for this phone's answer.
struct QuestionPromptCard: View {
    let question: RemoteQuestion
    let onSubmit: ([RemoteQuestionAnswer]) -> Void
    let onDelegate: () -> Void
    @State private var drafts: [String: QuestionDraft] = [:]

    private var completed: Bool {
        question.items.allSatisfy { drafts[$0.id]?.completed == true }
    }

    private var title: String {
        question.items.contains { $0.approveLabel != nil } ? "计划待审" : "需要你的回答"
    }

    var body: some View {
        InteractionCard(title: title, symbol: "questionmark.bubble.fill") {
            ForEach(question.items) { item in
                QuestionItemView(item: item, draft: drafts[item.id] ?? QuestionDraft()) { draft in
                    drafts[item.id] = draft
                }
            }
            if !completed {
                Text("请回答每一题，或选择跳过")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Button {
                onSubmit(answers())
            } label: {
                Text("提交回答").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .font(.system(size: 15, weight: .medium))
            .disabled(!completed)
            .accessibilityIdentifier("questionSubmit")
            Button("改在电脑上确认", action: onDelegate)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    /// Encode every question's draft the way the Host's answerer reads it.
    private func answers() -> [RemoteQuestionAnswer] {
        question.items.map { item in
            let draft = drafts[item.id] ?? QuestionDraft()
            if draft.skipped { return RemoteQuestionAnswer(id: item.id, selected: [], custom: nil) }
            let custom = draft.custom.trimmingCharacters(in: .whitespacesAndNewlines)
            return RemoteQuestionAnswer(
                id: item.id,
                selected: custom.isEmpty || item.multiSelect ? draft.selected : [],
                custom: custom.isEmpty ? nil : custom)
        }
    }
}

/// One question with its options, "other" answer, and skip.
private struct QuestionItemView: View {
    let item: RemoteQuestionItem
    let draft: QuestionDraft
    let onChange: (QuestionDraft) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header = item.header, !header.isEmpty {
                Text(header)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(item.question).font(.system(size: 15, weight: .medium))
            if let detail = item.detail, !detail.isEmpty { detailView(detail) }
            ForEach(item.options, id: \.self) { option in
                optionRow(option)
            }
            TextField("其他答案", text: customBinding, axis: .vertical)
                .font(.system(size: 14))
                .lineLimit(1...4)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("questionCustomAnswer")
            Button {
                onChange(QuestionDraft(selected: [], custom: "", skipped: !draft.skipped))
            } label: {
                Label(draft.skipped ? "已跳过此题" : "跳过此题",
                      systemImage: draft.skipped ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func detailView(_ detail: String) -> some View {
        if item.approveLabel == nil {
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
        } else {
            DisclosureGroup("查看计划") {
                ScrollView {
                    AssistantMessageView(text: detail, reasoning: nil)
                }
                .frame(maxHeight: 240)
                .padding(.top, 6)
            }
            .font(.system(size: 13))
        }
    }

    private func optionRow(_ option: String) -> some View {
        let selected = draft.selected.contains(option)
        let approved = option == item.approveLabel
        return Button {
            var next = draft
            next.skipped = false
            if item.multiSelect {
                next.selected = selected
                    ? draft.selected.filter { $0 != option }
                    : draft.selected + [option]
            } else {
                next.selected = [option]
                next.custom = ""
            }
            onChange(next)
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: selected
                      ? (item.multiSelect ? "checkmark.square.fill" : "largecircle.fill.circle")
                      : (item.multiSelect ? "square" : "circle"))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option).font(.system(size: 15)).foregroundStyle(.primary)
                    if approved {
                        Text("同意执行").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var customBinding: Binding<String> {
        Binding(
            get: { draft.custom },
            set: { value in
                var next = draft
                next.custom = value
                next.skipped = false
                if !item.multiSelect { next.selected = [] }
                onChange(next)
            })
    }
}
