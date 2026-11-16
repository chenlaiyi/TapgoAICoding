import SwiftUI
import UIKit
import WebKit
import os

private struct ChatLine: Identifiable, Equatable {
    let id: Int
    let role: String
    var text: String
    var reasoning: String?
    var attachments: [MobileMessageAttachment] = []
    var activities: [MobileChatActivity] = []
    var turn: Int?
    var startedAt: TimeInterval?
    var endedAt: TimeInterval?
    var endReason: String?
    var mergedEventIds: Set<Int> = []
    var messageID: String?
    var timestamp: Double?
    var changesSequence: Int?
    var endSequence: Int?
    var step: Int?
    var lastActivityAt: TimeInterval?
    var live = false
    var interrupted = false
    var presentationID: String {
        if role == "assistant", let turn, let step { return "assistant-\(turn)-\(step)" }
        return "event-\(id)"
    }

    init(id: Int, role: String, text: String, reasoning: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.reasoning = reasoning
    }
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
    @Published var nextPrompts = MobileNextPrompts()
    @Published var toolOutputs: [String: MobileToolOutput] = [:]
    @Published var toolOutputUnavailable = false
    @Published var feedbackItems: [String: MobileMessageFeedback] = [:]
    @Published var feedbackLoaded = false
    @Published var feedbackPending: String?
    @Published var feedbackPendingRating: MobileMessageFeedback.Rating?
    @Published var feedbackError: String?
    @Published var feedbackIssueMessageID: String?
    @Published var forkPending: Int?
    @Published var forkUnknown: Set<Int> = []
    private var feedbackLoading = false
    private var feedbackTouched: Set<String> = []
    private var jobStreams: [String: String] = [:]
    private var issuedJobStreams: Set<String> = []
    private var visibleJobs: [String: String] = [:]
    private var toolOutputOrder: [String] = []
    @Published var loading = true
    @Published var isFork = false
    @Published var sending = false
    #if DEBUG
    @Published var testSendPending = false
    private var testSendCompletion: CheckedContinuation<Bool, Never>?
    @Published var testModelPending = false
    private var testModelCompletion: CheckedContinuation<Bool, Never>?

    private var testOutputBatch = 0
    private var testReplyIndex = 0
    private var testStreamStep = 0
    private var testAssistantBatch = 0
    private var testFeedbackRecords: [String: [String: Any]] = [:]

    func appendTestToolOutput() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--dsh-mobile-test-tool-output"), arguments.indices.contains(index + 1),
              let data = arguments[index + 1].data(using: .utf8),
              let batches = try? JSONSerialization.jsonObject(with: data) as? [[[String: Any]]],
              batches.indices.contains(testOutputBatch), let owner = sessionId else { return }
        let bindings = Set(lines.flatMap { $0.activities.flatMap(\.jobIDs) })
        for item in batches[testOutputBatch] {
            guard let id = item["jobId"] as? String, bindings.contains(id), let frame = item["frame"] as? [String: Any] else { continue }
            if toolOutputs[id] == nil { toolOutputs[id] = MobileToolOutput(id: id, owner: owner) }
            toolOutputs[id]?.receive(frame)
        }
        testOutputBatch += 1
    }

    func completeTestModelSelection() {
        let success = ProcessInfo.processInfo.arguments.contains("model-success")
        testModelCompletion?.resume(returning: success)
        testModelCompletion = nil
        testModelPending = false
    }

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
              replies.indices.contains(testReplyIndex) else { return }
        if !liveActive { receiveStream(["type": "start"]) }
        receiveStream(["type": "chunk", "chunk": ["type": "text-delta", "text": replies[testReplyIndex]]])
        testReplyIndex += 1
    }

    func appendTestAssistantBatch() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--dsh-mobile-test-assistant-batches"), arguments.indices.contains(index + 1),
              let data = arguments[index + 1].data(using: .utf8),
              let batches = try? JSONSerialization.jsonObject(with: data) as? [[[String: Any]]],
              batches.indices.contains(testAssistantBatch) else { return }
        for item in batches[testAssistantBatch] {
            if let frame = item["stream"] as? [String: Any] { receiveStream(frame) }
            if let event = item["event"] as? [String: Any] {
                if assistantStream.matches(event), let seq = event["seq"] as? Int {
                    pendingAssistantEvents[seq] = event
                } else {
                    var projected = lines
                    Self.consume(event, into: &projected, owner: sessionId)
                    lines = projected
                    if let seq = event["seq"] as? Int, ["assistant/message", "assistant/attempt"].contains(event["type"] as? String ?? "") {
                        seenAssistantSettlements.insert(seq)
                    }
                    if event["type"] as? String == "turn/end" {
                        assistantStream.retire()
                        publishStream(immediate: true)
                    }
                }
            }
        }
        testAssistantBatch += 1
    }

    private static func debugQueueState() -> MobileQueueState? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--dsh-mobile-test-state"),
              arguments.indices.contains(index + 1),
              let data = arguments[index + 1].data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return MobileQueueState.decode(value)
    }
    #endif
    @Published var error: String?
    @Published var models: [MobileModel] = []
    @Published var selectedModel: String?
    @Published var selectedEffort: String?
    @Published var selectingModelID: String?
    @Published var modelSelectionError: String?
    @Published var permissions: [RemotePermission] = []
    @Published var selectedPermission: String?
    @Published var funds = MobileBalanceSnapshot()
    private var balanceRevision = UUID()
    var balance: String? { funds.available(provider: selectedModel?.split(separator: "/").first.map(String.init)) }
    var balanceDetails: [String] { funds.accountDetails }
    @Published var tokenUsage: String?
    @Published var contextBudget: String?
    @Published var settingsLoading = false
    @Published var liveText = ""
    @Published var liveReasoning = ""
    @Published var liveActive = false
    private var assistantStream = MobileAssistantStream()
    private var pendingAssistantEvents: [Int: [String: Any]] = [:]
    private var seenAssistantSettlements: Set<Int> = []
    private var streamPublication: Task<Void, Never>?
    private var streamNeedsResync = false
    var displayLines: [ChatLine] {
        var visible = lines
        if liveActive, !liveText.isEmpty {
            var line = ChatLine(id: -1, role: "assistant", text: liveText)
            line.turn = assistantStream.turn
            line.step = assistantStream.step
            line.live = true
            if !visible.contains(where: { $0.presentationID == line.presentationID }) { visible.append(line) }
        }
        return visible
    }
    @Published var cancelling = false
    @Published var reconnecting = false
    @Published var connected = false
    @Published var lastFrameAt: Date?
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private let heartbeat = MobileSocketHeartbeat()
    private var generation = UUID()
    private var retryCount = 0
    private var origin: URL?
    @Published private var composerState = MobileComposerState()
    @Published var composerStatusError: String?
    @Published var queuedItems: [MobileQueuedItem] = []
    @Published var queueRunning = false
    @Published var queueCursor: Int?
    @Published var queueUnavailable = false
    var imageLimits: MobileImageLimits { composerState.imageLimits }
    var sessionTitle: String? { composerState.sessionTitle }
    var planActive: Bool { composerState.planActive }
    var goalObjective: String? { composerState.goalObjective }
    var goalPhase: String? { composerState.goalPhase }
    private var sessionId: String?
    /// The submission the Host may already have accepted, so a resend of the same draft reuses its request id.
    private var pendingSubmission: MobilePendingSubmission?
    /// Pairing needed to read attachment bytes through the Host.
    private var computer: SavedComputer?
    @Published private var attachmentImages: [String: UIImage] = [:]
    @Published private var failedAttachments: Set<String> = []
    private var loadingAttachments: Set<String> = []
    private var attachmentOrder: [String] = []
    /// Transcript thumbnails kept in memory; older ones are dropped first.
    private static let attachmentImageLimit = 24

    var running: Bool {
        liveActive || lines.last(where: { $0.role == "turn" })?.endedAt == nil
            && lines.contains(where: { $0.role == "turn" })
    }

    func connect(computer: SavedComputer, sessionId: String, reconnect: Bool = false) async {
        self.sessionId = sessionId
        self.computer = computer
        #if DEBUG
        isFork = sessionId == "fixture-fork"
        let queueFixture = Self.debugQueueState()
        if let queueFixture { applyQueue(queueFixture) }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--dsh-mobile-test-composer-projections"),
           arguments.indices.contains(index + 1), let data = arguments[index + 1].data(using: .utf8),
           let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            composerState.restore(value)
        }
        if let index = arguments.firstIndex(of: "--dsh-mobile-test-messages"),
           arguments.indices.contains(index + 1),
           let data = arguments[index + 1].data(using: .utf8),
           let fixture = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            lines = fixture.compactMap { item in
                guard let id = item["id"] as? Int,
                      let role = item["role"] as? String,
                      let text = item["text"] as? String else { return nil }
                var line = ChatLine(id: id, role: role, text: text,
                                    reasoning: item["reasoning"] as? String)
                line.messageID = item["messageId"] as? String
                line.timestamp = item["time"] as? Double
                return line
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
            for event in fixture {
                Self.consume(event, into: &projected, owner: sessionId)
                nextPrompts.consume(event)
            }
            lines = projected
            appendTestToolOutput()
            if let streamIndex = arguments.firstIndex(of: "--dsh-mobile-test-stream"),
               arguments.indices.contains(streamIndex + 1),
               let streamData = arguments[streamIndex + 1].data(using: .utf8),
               let stream = try? JSONSerialization.jsonObject(with: streamData) as? [[String: Any]] {
                for frame in stream { receiveStream(frame) }
            }
            appendTestAssistantBatch()
            loading = false
            connected = true
            return
        }
        #endif
        guard let origin = URL(string: computer.id), let pairing = URL(string: computer.url) else { return }
        disconnect()
        pendingAssistantEvents = [:]
        streamNeedsResync = false
        feedbackLoading = false
        feedbackPending = nil
        feedbackPendingRating = nil
        forkPending = nil
        self.origin = origin
        connected = false
        reconnecting = reconnect
        if !reconnect {
            lines = []
            seenAssistantSettlements = []
            toolOutputs = [:]
            toolOutputOrder = []
            toolOutputUnavailable = false
            feedbackItems = [:]
            feedbackLoaded = false
            feedbackError = nil
            feedbackIssueMessageID = nil
            feedbackLoading = false
            feedbackPending = nil
            feedbackTouched = []
            forkUnknown = []
            queuedItems = []
            queueRunning = false
            queueCursor = nil
            queueUnavailable = false
            lastFrameAt = nil
            pendingSubmission = nil
            attachmentImages = [:]
            failedAttachments = []
            loadingAttachments = []
            attachmentOrder = []
            liveActive = false
            liveText = ""
            liveReasoning = ""
            assistantStream = MobileAssistantStream()
            retryCount = 0
            loading = true
            error = nil
        }
        #if DEBUG
        if let queueFixture { applyQueue(queueFixture) }
        #endif
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
                                                   "assistantStream": true, "maxMessages": 200,
                                                   "turnWindow": ["minMessages": 1, "minTurns": 1]]]]
            ]
            let serialized = try JSONSerialization.data(withJSONObject: opening)
            guard let text = String(data: serialized, encoding: .utf8) else { throw ChatFailure.unavailable }
            let projectionOpening: [String: Any] = [
                "type": "open", "streamId": streamId + "-composer", "endpoint": "session/observeProjections",
                "payload": ["args": ["request": ["sessionId": sessionId]]]
            ]
            let projectionData = try JSONSerialization.data(withJSONObject: projectionOpening)
            guard let projectionText = String(data: projectionData, encoding: .utf8) else { throw ChatFailure.unavailable }
            composerState = MobileComposerState()
            composerStatusError = nil
            try await socket.send(.string(projectionText))
            try await socket.send(.string(text))
            let stateOpening: [String: Any] = ["type": "open", "streamId": streamId + "-state",
                "endpoint": "session/observeState",
                "payload": ["args": ["request": ["sessionId": sessionId]]]]
            let stateData = try JSONSerialization.data(withJSONObject: stateOpening)
            try await socket.send(.string(String(decoding: stateData, as: UTF8.self)))
            let jobsOpening: [String: Any] = ["type": "open", "streamId": streamId + "-jobs", "endpoint": "job/list",
                "payload": ["args": ["request": ["sessionId": sessionId]]]]
            let jobsData = try JSONSerialization.data(withJSONObject: jobsOpening)
            try await socket.send(.string(String(decoding: jobsData, as: UTF8.self)))
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
                lastFrameAt = .now
                if frameStream == streamId + "-jobs" {
                    if frame["type"] as? String == "error" { toolOutputUnavailable = true }
                    if let value = frame["value"] as? [String: Any], value["type"] as? String == "rows",
                       let jobs = value["jobs"] as? [[String: Any]] {
                        visibleJobs = jobs.reduce(into: [:]) { result, job in
                            if job["owner"] as? String == self.sessionId, let id = job["id"] as? String,
                               let status = job["status"] as? String { result[id] = status }
                        }
                        toolOutputUnavailable = false
                        issuedJobStreams.formIntersection(visibleJobs.keys)
                        for id in toolOutputs.keys where toolOutputs[id]?.phase == .disconnected && visibleJobs[id] == nil {
                            toolOutputs[id]?.unavailable()
                        }
                        try await openToolOutputs(socket: socket, generation: current)
                        guard current == generation, self.socket === socket else { return }
                    }
                    continue
                }
                if let jobID = jobStreams[frameStream] {
                    if let value = frame["value"] as? [String: Any] { toolOutputs[jobID]?.receive(value) }
                    if frame["type"] as? String == "error" {
                        toolOutputs[jobID]?.unavailable()
                        jobStreams.removeValue(forKey: frameStream)
                    }
                    if frame["type"] as? String == "end" {
                        if toolOutputs[jobID]?.active == true { toolOutputs[jobID]?.unavailable() }
                        jobStreams.removeValue(forKey: frameStream)
                    }
                    trimToolOutputs()
                    continue
                }
                if frameStream == streamId + "-state" {
                    if frame["type"] as? String == "error" {
                        queueUnavailable = true
                        Task { await self.refreshQueue(computer: computer) }
                        continue
                    }
                    if let value = frame["value"] as? [String: Any],
                       let state = MobileQueueState.decode(value) {
                        applyQueue(state)
                    }
                    continue
                }
                if frameStream == streamId + "-composer" {
                    if frame["type"] as? String == "error" {
                        composerState = MobileComposerState()
                        composerStatusError = "此电脑无法同步方案与目标状态，请更新电脑端"
                        continue
                    }
                    if let value = frame["value"] as? [String: Any] {
                        if value["type"] as? String == "ready", let sessionId {
                            do {
                                let baseline = try await call("session/projections", arguments: ["request": ["sessionId": sessionId]], computer: computer)
                                guard self.generation == current else { return }
                                if let baseline = baseline as? [String: Any] { composerState.restore(baseline) }
                            } catch {
                                guard self.generation == current else { return }
                                composerStatusError = "无法读取方案与目标状态，请重新打开对话"
                            }
                        } else if value["type"] as? String == "projection" {
                            composerState.consume(value)
                        }
                    }
                    continue
                }
                guard frameStream == streamId else { continue }
                if frame["type"] as? String == "error" { throw ChatFailure.unavailable }
                guard frame["type"] as? String == "item",
                      let value = frame["value"] as? [String: Any] else { continue }
                if value["type"] as? String == "snapshot" {
                    isFork = (value["header"] as? [String: Any])?["isSeeded"] as? Bool == true
                    let records = value["records"] as? [[String: Any]] ?? []
                    var projected: [ChatLine] = []
                    seenAssistantSettlements = []
                    nextPrompts = MobileNextPrompts()
                    for record in records {
                        if let event = record["event"] as? [String: Any] {
                            if let seq = event["seq"] as? Int,
                               ["assistant/message", "assistant/attempt"].contains(event["type"] as? String ?? "") {
                                seenAssistantSettlements.insert(seq)
                            }
                            Self.consume(event, into: &projected, owner: sessionId)
                            nextPrompts.consume(event)
                        }
                    }
                    lines = projected
                    try await openToolOutputs(socket: socket, generation: current)
                    guard current == generation, self.socket === socket else { return }
                    pendingAssistantEvents = [:]
                    guard assistantStream.restore(value["assistantStream"] as? [String: Any]) else {
                        scheduleRetry(computer: computer, generation: current)
                        error = "回复流不完整，正在重新同步"
                        return
                    }
                    publishStream(immediate: true)
                    loading = false
                    connected = true
                    reconnecting = false
                    lastFrameAt = .now
                    error = nil
                    retryCount = 0
                    Task { await self.loadFeedback(computer: computer) }
                    if let values = (value["projections"] as? [String: Any])?["values"] as? [String: Any] {
                        nextPrompts.restore(values["nextPrompts"] as? [String: Any], running: running)
                        if let baseline = value["projections"] as? [String: Any] { composerState.restore(baseline) }
                        if let selection = values["modelSelection"] as? [String: Any],
                           let next = selection["next"] as? [String: Any],
                           let provider = next["provider"] as? String,
                           let model = next["model"] as? String {
                            let route = "\(provider)/\(model)"
                            let effort = next["reasoningEffort"] as? String
                            modelSelectionError = nil
                            if selectedModel != route || selectedEffort != effort {
                                selectedModel = route
                                selectedEffort = effort
                                funds.providers.removeAll()
                                Task { await self.refreshBalances(computer: computer) }
                            }
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
                    if streamNeedsResync {
                        scheduleRetry(computer: computer, generation: current)
                        error = "回复流不完整，正在重新同步"
                        return
                    }
                } else if let event = value["event"] as? [String: Any] {
                    if assistantStream.matches(event), let seq = event["seq"] as? Int {
                        pendingAssistantEvents[seq] = event
                        continue
                    }
                    consumeFeedback(event)
                    if let seq = event["seq"] as? Int,
                       ["assistant/message", "assistant/attempt"].contains(event["type"] as? String ?? "") {
                        seenAssistantSettlements.insert(seq)
                    }
                    var projected = lines
                    Self.consume(event, into: &projected, owner: sessionId)
                    nextPrompts.consume(event)
                    lines = projected
                    try await openToolOutputs(socket: socket, generation: current)
                    guard current == generation, self.socket === socket else { return }
                    if event["type"] as? String == "model/selection",
                       let data = event["data"] as? [String: Any],
                       let provider = data["provider"] as? String, let model = data["model"] as? String {
                        selectedModel = "\(provider)/\(model)"
                        selectedEffort = data["reasoningEffort"] as? String
                        funds.providers.removeAll()
                        Task { await self.refreshBalances(computer: computer) }
                    }
                    if event["type"] as? String == "turn/end" {
                        if !pendingAssistantEvents.isEmpty {
                            scheduleRetry(computer: computer, generation: current)
                            error = "回复流正在确认最终内容"
                            return
                        }
                        assistantStream.retire()
                        publishStream(immediate: true)
                        cancelling = false
                        Task { await self.refreshBalances(computer: computer) }
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

    private func disconnectToolOutputs() {
        for id in toolOutputs.keys { toolOutputs[id]?.disconnect() }
        jobStreams = [:]
        issuedJobStreams = []
        visibleJobs = [:]
    }

    private func openToolOutputs(socket: URLSessionWebSocketTask, generation current: UUID) async throws {
        guard generation == current, self.socket === socket, let sessionId else { return }
        let bindings = Set(lines.flatMap { $0.activities.flatMap(\.jobIDs) })
        for id in bindings.sorted() {
            guard let status = visibleJobs[id], !issuedJobStreams.contains(id),
                  status == "running" || status == "stopping" || toolOutputs[id]?.active == true else { continue }
            if toolOutputs[id] == nil { toolOutputOrder.append(id) }
            var output = toolOutputs[id] ?? MobileToolOutput(id: id, owner: sessionId)
            output.begin()
            toolOutputs[id] = output
            issuedJobStreams.insert(id)
            let streamID = "tool-output-" + UUID().uuidString
            jobStreams[streamID] = id
            let opening: [String: Any] = ["type": "open", "streamId": streamID, "endpoint": "job/follow",
                "payload": ["args": ["request": ["sessionId": sessionId, "jobId": id, "from": output.nextOffset]]]]
            let data = try JSONSerialization.data(withJSONObject: opening)
            try await socket.send(.string(String(decoding: data, as: UTF8.self)))
            guard generation == current, self.socket === socket else { return }
        }
        trimToolOutputs()
    }

    private func trimToolOutputs() {
        let inactive = toolOutputOrder.filter { toolOutputs[$0]?.active == false }
        if inactive.count > 32 {
            for id in inactive.prefix(inactive.count - 32) { toolOutputs.removeValue(forKey: id) }
            toolOutputOrder.removeAll { toolOutputs[$0] == nil }
        }
    }

    /// Applies one complete queue state reported by the Host.
    /// - Parameter state: queue items and the current run state.
    private func applyQueue(_ state: MobileQueueState) {
        queuedItems = state.items
        queueRunning = state.running
        queueCursor = state.cursor
        queueUnavailable = false
    }

    /// Reports how long the socket has been silent during a running turn.
    /// - Parameter now: current clock used by the view timeline.
    /// - Returns: whole seconds since the last frame, or nil when connected traffic is recent.
    func silentSeconds(now: Date = Date()) -> Int? {
        guard connected, !reconnecting, running, let lastFrameAt else { return nil }
        let seconds = Int(now.timeIntervalSince(lastFrameAt))
        return seconds >= 90 ? seconds : nil
    }

    /// Reads the queue once when the state stream is unavailable on this Host.
    /// - Parameter computer: pairing used for the authenticated request.
    func refreshQueue(computer: SavedComputer) async {
        guard let sessionId else { return }
        do {
            let value = try await call("session/state", arguments: ["request": ["sessionId": sessionId]],
                                       computer: computer)
            guard let value = value as? [String: Any], let state = MobileQueueState.decode(value) else { return }
            applyQueue(state)
        } catch {
            queueUnavailable = true
        }
    }

    /// A decoded transcript thumbnail for one durable image, when it has already loaded.
    /// - Parameter reference: image block reference from the transcript.
    /// - Returns: the cached thumbnail, or nil while loading or after a failure.
    func attachmentImage(_ reference: MobileImageRef) -> UIImage? {
        attachmentImages[reference.attachmentID]
    }

    /// Whether the last thumbnail fetch for one image failed.
    /// - Parameter reference: image block reference from the transcript.
    /// - Returns: `true` when the tile must offer a retry.
    func attachmentFailed(_ reference: MobileImageRef) -> Bool {
        failedAttachments.contains(reference.attachmentID)
    }

    /// Clears one failed fetch so its tile can try again.
    /// - Parameter reference: image block reference from the transcript.
    func retryAttachment(_ reference: MobileImageRef) {
        failedAttachments.remove(reference.attachmentID)
    }

    /// Reads one durable image through the Host and keeps only a small transcript thumbnail.
    /// - Parameter reference: image block reference from the transcript.
    func loadAttachmentImage(_ reference: MobileImageRef) async {
        let id = reference.attachmentID
        guard attachmentImages[id] == nil, !loadingAttachments.contains(id),
              let computer, let sessionId else { return }
        loadingAttachments.insert(id)
        defer { loadingAttachments.remove(id) }
        do {
            let value = try await call("session/attachment", arguments: ["request": [
                "sessionId": sessionId, "attachment": reference.wire]], computer: computer)
            guard let value = value as? [String: Any], let encoded = value["data"] as? String,
                  let data = Data(base64Encoded: encoded),
                  let thumbnail = MobileImageThumbnail.make(from: data) else { throw ChatFailure.unavailable }
            attachmentImages[id] = UIImage(cgImage: thumbnail)
            failedAttachments.remove(id)
            rememberAttachment(id)
        } catch {
            failedAttachments.insert(id)
        }
    }

    /// Tracks insertion order so the in-memory thumbnail cache stays bounded.
    /// - Parameter id: attachment identity that just loaded.
    private func rememberAttachment(_ id: String) {
        attachmentOrder.removeAll { $0 == id }
        attachmentOrder.append(id)
        while attachmentOrder.count > Self.attachmentImageLimit {
            attachmentImages.removeValue(forKey: attachmentOrder.removeFirst())
        }
    }

    private func scheduleRetry(computer: SavedComputer, generation current: UUID) {
        guard current == generation else { return }
        heartbeat.stop()
        disconnectToolOutputs()
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

    private func publishStream(immediate: Bool) {
        if !immediate {
            guard streamPublication == nil else { return }
            let current = generation
            streamPublication = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(33))
                guard !Task.isCancelled, let self, self.generation == current else { return }
                self.streamPublication = nil
                self.publishStream(immediate: true)
            }
            return
        }
        streamPublication?.cancel()
        streamPublication = nil
        liveText = assistantStream.text
        liveReasoning = assistantStream.reasoning
        liveActive = assistantStream.active
    }

    private func receiveStream(_ incoming: [String: Any]) {
        var frame = incoming
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--dsh-mobile-test-url") {
            if frame["type"] as? String == "start" {
                testStreamStep += 1
                if frame["attemptId"] == nil { frame["attemptId"] = UUID().uuidString }
                if frame["turn"] == nil { frame["turn"] = lines.last(where: { $0.role == "turn" })?.turn ?? 1 }
                if frame["step"] == nil { frame["step"] = testStreamStep }
                if frame["startedAfterSeq"] == nil { frame["startedAfterSeq"] = lines.map(\.id).max() ?? -1 }
            } else {
                if frame["attemptId"] == nil { frame["attemptId"] = assistantStream.attemptID }
                if frame["index"] == nil { frame["index"] = assistantStream.nextIndex }
            }
            if frame["revision"] == nil { frame["revision"] = assistantStream.revision + 1 }
            if var chunk = frame["chunk"] as? [String: Any], chunk["index"] == nil {
                chunk["index"] = 0
                frame["chunk"] = chunk
            }
        }
        #endif
        switch assistantStream.receive(frame) {
        case .ignored: break
        case .updated:
            publishStream(immediate: frame["type"] as? String == "start")
        case .abandoned:
            if !pendingAssistantEvents.isEmpty {
                streamPublication?.cancel()
                streamPublication = nil
                streamNeedsResync = true
                return
            }
            publishStream(immediate: true)
        case .resync:
            streamPublication?.cancel()
            streamPublication = nil
            streamNeedsResync = true
        case .committed(let sequence, let eventType):
            if let event = pendingAssistantEvents.removeValue(forKey: sequence), event["type"] as? String == eventType {
                var projected = lines
                Self.consume(event, into: &projected, owner: sessionId)
                lines = projected
                seenAssistantSettlements.insert(sequence)
            } else if !seenAssistantSettlements.contains(sequence) {
                streamPublication?.cancel()
                streamPublication = nil
                streamNeedsResync = true
                return
            }
            assistantStream.retire()
            publishStream(immediate: true)
        }
    }

    private static func consume(_ event: [String: Any], into lines: inout [ChatLine], owner: String?) {
        guard let type = event["type"] as? String,
              let seq = event["seq"] as? Int,
              let data = event["data"] as? [String: Any] else { return }
        if lines.contains(where: { $0.id == seq }) { return }
        if let turn = data["turn"] as? Int, let time = event["time"] as? TimeInterval,
           let index = lines.lastIndex(where: { $0.role == "turn" && $0.turn == turn }) {
            lines[index].lastActivityAt = time
        }
        if type == "turn/start", let turn = data["turn"] as? Int {
            if let index = lines.lastIndex(where: { $0.role == "turn" && $0.turn == turn && $0.id < 0 }) {
                lines[index].startedAt = event["time"] as? TimeInterval
                lines[index].lastActivityAt = event["time"] as? TimeInterval
                return
            }
            var line = ChatLine(id: seq, role: "turn", text: "", reasoning: nil)
            line.turn = turn
            line.startedAt = event["time"] as? TimeInterval
            line.lastActivityAt = event["time"] as? TimeInterval
            lines.append(line)
            return
        }
        if type == "turn/end", let turn = data["turn"] as? Int {
            if let index = lines.lastIndex(where: { $0.role == "turn" && $0.turn == turn }) {
                lines[index].endSequence = seq
                lines[index].endedAt = event["time"] as? TimeInterval ?? 0
                lines[index].endReason = (data["reason"] as? [String: Any])?["kind"] as? String
            }
            return
        }
        if type == "workspace/changes", let turn = data["turn"] as? Int {
            if let index = lines.lastIndex(where: { $0.role == "turn" && $0.turn == turn }) {
                lines[index].changesSequence = seq
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
        if type == "job/registered", data["owner"] as? String == owner,
           let jobID = data["jobId"] as? String,
           let call = data["toolCall"] as? [String: Any], let callID = call["rootCallId"] as? String {
            for index in lines.indices.reversed() {
                if let activity = lines[index].activities.firstIndex(where: { $0.id == callID }) {
                    if !lines[index].activities[activity].jobIDs.contains(jobID) {
                        lines[index].activities[activity].jobIDs.append(jobID)
                    }
                    break
                }
            }
            return
        }
        if type == "tool/call", let name = data["name"] as? String,
           let callId = data["callId"] as? String {
            if let turn = data["turn"] as? Int {
                Self.ensureTurn(turn: turn, seq: seq, time: event["time"] as? TimeInterval, into: &lines)
            }
            let arguments = (data["arguments"] as? String).flatMap {
                try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
            } ?? [:]
            let detail = ["title", "description", "command", "cmd", "file_path", "path", "query", "pattern"]
                .compactMap { arguments[$0] as? String }.first ?? name
            let activity = MobileChatActivity(id: callId, name: name, detail: String(detail.prefix(120)),
                                        category: activityCategory(name), arguments: data["arguments"] as? String ?? "")
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
                lines[index].activities[activity].receive(data)
                return
            }
            return
        }
        guard type == "user/message" || type == "assistant/message" else { return }
        if type == "user/message",
           let source = data["source"] as? [String: Any], source["kind"] as? String != "user" {
            return
        }
        if let turn = data["turn"] as? Int {
            Self.ensureTurn(turn: turn, seq: seq, time: event["time"] as? TimeInterval, into: &lines)
        }
        let message: [String: Any] = type == "user/message" ? data : (data["message"] as? [String: Any] ?? [:])
        let blocks = message["content"] as? [[String: Any]] ?? []
        let content = MobileMessageContent.parse(blocks: blocks)
        let text = content.text
        let streamReasoning = Self.streamText(data["stream"] as? [[String: Any]] ?? [], kind: "reasoning")
        let reasoning = streamReasoning.isEmpty ? content.reasoning : streamReasoning
        guard !text.isEmpty || !reasoning.isEmpty || !content.attachments.isEmpty else { return }
        if type == "assistant/message", !reasoning.isEmpty,
           let turnIndex = lines.lastIndex(where: { $0.role == "turn" }) {
            if lines[turnIndex].mergedEventIds.insert(seq).inserted {
                let previous = lines[turnIndex].reasoning ?? ""
                lines[turnIndex].reasoning = previous.isEmpty ? reasoning : previous + "\n\n" + reasoning
            }
        }
        if type == "assistant/message", text.isEmpty, content.attachments.isEmpty { return }
        var line = ChatLine(id: seq, role: type == "user/message" ? "user" : "assistant",
                            text: text, reasoning: nil)
        line.attachments = content.attachments
        line.messageID = message["id"] as? String
        line.timestamp = event["time"] as? Double
        line.turn = data["turn"] as? Int ?? lines.last(where: { $0.role == "turn" })?.turn
        line.step = data["step"] as? Int
        line.interrupted = data["interrupted"] as? Bool == true
        if type == "assistant/message" { line.mergedEventIds.insert(seq) }
        if type == "user/message", lines.last?.role == "turn" {
            lines.insert(line, at: lines.count - 1)
        } else {
            lines.append(line)
        }
    }

    /// Creates a turn header when a bounded snapshot starts inside a long turn.
    /// - Parameters:
    ///   - turn: durable turn number from the event.
    ///   - seq: event sequence used for a stable negative identity.
    ///   - time: event time in milliseconds.
    ///   - lines: projected transcript to update.
    private static func ensureTurn(turn: Int, seq: Int, time: TimeInterval?, into lines: inout [ChatLine]) {
        guard !lines.contains(where: { $0.role == "turn" && $0.turn == turn }) else { return }
        var line = ChatLine(id: -1_000_000 - seq, role: "turn", text: "", reasoning: nil)
        line.turn = turn
        line.startedAt = time
        line.lastActivityAt = time
        lines.append(line)
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

    func send(_ text: String, attachments: [MobileDraftAttachment], mode: MobileComposerMode,
              computer: SavedComputer, sessionId: String) async -> Bool {
        guard !sending, connected, !text.isEmpty || !attachments.isEmpty else { return false }
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
        let candidate = MobilePendingSubmission(text: text, mode: mode, attachments: attachments)
        let submission = pendingSubmission?.matches(candidate) == true
            ? MobilePendingSubmission(text: text, mode: mode, attachments: attachments,
                                      requestId: pendingSubmission?.requestId ?? candidate.requestId)
            : candidate
        pendingSubmission = submission
        do {
            try await MobileComposerTransport(session: session, origin: origin)
                .submit(text: text, attachments: attachments, mode: mode, sessionId: sessionId,
                        requestId: submission.requestId)
            pendingSubmission = nil
            error = nil
            if queueUnavailable { await refreshQueue(computer: computer) }
            return true
        } catch {
            if (error as? URLError)?.code == .timedOut {
                self.error = "请求超时，未确认是否送达；再次发送不会重复"
                return false
            }
            self.error = "发送失败，草稿与附件已保留：\(error.localizedDescription)"
            return false
        }
    }

    func composerCommand(_ line: String, computer: SavedComputer, sessionId: String) async {
        guard !sending else { return }
        guard connected, let session, let origin = URL(string: computer.id) else {
            error = "当前未连接到电脑，请重连后再操作"
            return
        }
        sending = true
        defer { sending = false }
        do {
            try await MobileComposerTransport(session: session, origin: origin)
                .execute(line: line, sessionId: sessionId)
            error = nil
        } catch { self.error = "操作失败：\(error.localizedDescription)" }
    }

    func cancel(computer: SavedComputer, sessionId: String) async {
        guard !cancelling else { return }
        cancelling = true
        do {
            _ = try await call("session/cancel", arguments: ["request": ["sessionId": sessionId]], computer: computer)
            error = nil
            if queueUnavailable { await refreshQueue(computer: computer) }
        } catch {
            cancelling = false
            self.error = "停止失败，请重试"
        }
    }

    private func call(_ method: String, arguments: [String: Any], computer: SavedComputer) async throws -> Any {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--dsh-mobile-test-reply-actions"),
           method.hasPrefix("messageFeedback/") || method == "session/fork" {
            return try replyActionFixture(method, arguments: arguments)
        }
        #endif
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

    private func decodeReplyValue<Value: Decodable>(_ value: Any, as type: Value.Type) throws -> Value {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value))
    }

    private func consumeFeedback(_ event: [String: Any]) {
        guard let type = event["type"] as? String, let data = event["data"] as? [String: Any],
              data["sessionId"] as? String == sessionId else { return }
        if type == "feedback/message-put", let value = data["item"],
           let item = try? decodeReplyValue(value, as: MobileMessageFeedback.self),
           !item.messageId.isEmpty, !item.version.isEmpty {
            feedbackItems[item.messageId] = item
            feedbackTouched.insert(item.messageId)
        } else if type == "feedback/message-delete", let id = data["messageId"] as? String {
            feedbackItems.removeValue(forKey: id)
            feedbackTouched.insert(id)
        }
    }

    func loadFeedback(computer: SavedComputer) async {
        guard !feedbackLoading, let owner = sessionId else { return }
        let current = generation
        feedbackLoading = true
        feedbackTouched = []
        defer { if current == generation { feedbackLoading = false } }
        do {
            guard let result = try await call("messageFeedback/list", arguments: ["request": ["sessionId": owner]],
                                             computer: computer) as? [String: Any],
                  result["ok"] as? Bool == true, let value = result["value"] as? [String: Any],
                  let raw = value["items"] else { throw MobileReplyFailure.unavailable }
            let items = try decodeReplyValue(raw, as: [MobileMessageFeedback].self)
            guard items.allSatisfy({ !$0.messageId.isEmpty && !$0.version.isEmpty }) else { throw MobileReplyFailure.invalidData }
            guard current == generation, sessionId == owner else { return }
            var loaded: [String: MobileMessageFeedback] = [:]
            for item in items { loaded[item.messageId] = item }
            for id in feedbackTouched {
                if let item = feedbackItems[id] { loaded[id] = item }
                else { loaded.removeValue(forKey: id) }
            }
            feedbackItems = loaded
            feedbackLoaded = true
            feedbackError = nil
            feedbackIssueMessageID = nil
        } catch {
            if current == generation, sessionId == owner {
                feedbackLoaded = false
                feedbackError = "暂时无法读取回复反馈"
                feedbackIssueMessageID = lines.last(where: { $0.role == "assistant" })?.messageID
            }
        }
    }

    func rateReply(_ id: String, rating: MobileMessageFeedback.Rating, computer: SavedComputer) async {
        guard feedbackLoaded, feedbackPending == nil, let owner = sessionId else { return }
        let current = generation
        let observed = feedbackItems[id]
        let retract = observed?.rating == rating
        feedbackPending = id
        feedbackPendingRating = rating
        feedbackError = nil
        defer {
            if current == generation {
                feedbackPending = nil
                feedbackPendingRating = nil
            }
        }
        var request: [String: Any] = ["sessionId": owner, "messageId": id]
        if let observed { request["ifVersion"] = observed.version }
        else { request["ifVersion"] = NSNull() }
        if !retract {
            request["rating"] = rating.rawValue
            if let note = observed?.note { request["note"] = note }
            if let category = observed?.category { request["category"] = category }
        }
        do {
            guard let result = try await call(retract ? "messageFeedback/delete" : "messageFeedback/put",
                                             arguments: ["request": request], computer: computer) as? [String: Any] else {
                throw MobileReplyFailure.invalidData
            }
            guard current == generation, sessionId == owner else { return }
            if result["ok"] as? Bool == true {
                if retract {
                    guard (result["value"] as? [String: Any])?["absent"] as? Bool == true else {
                        throw MobileReplyFailure.invalidData
                    }
                    feedbackItems.removeValue(forKey: id)
                }
                else {
                    guard let raw = result["value"] else { throw MobileReplyFailure.invalidData }
                    let item = try decodeReplyValue(raw, as: MobileMessageFeedback.self)
                    guard item.messageId == id, !item.version.isEmpty else { throw MobileReplyFailure.invalidData }
                    feedbackItems[id] = item
                }
                feedbackTouched.insert(id)
            } else {
                if let failure = result["error"] as? [String: Any], failure["code"] as? String == "version-conflict" {
                    if let raw = failure["current"], !(raw is NSNull),
                       let item = try? decodeReplyValue(raw, as: MobileMessageFeedback.self), item.messageId == id {
                        feedbackItems[id] = item
                    } else { feedbackItems.removeValue(forKey: id) }
                    feedbackError = "反馈已在其他设备更新，请确认后重试"
                    feedbackTouched.insert(id)
                } else { feedbackError = "反馈未保存，请稍后重试" }
                feedbackIssueMessageID = id
            }
        } catch {
            guard current == generation, sessionId == owner else { return }
            await loadFeedback(computer: computer)
            guard current == generation, sessionId == owner else { return }
            feedbackError = "提交结果未确认，已尝试刷新当前反馈"
            feedbackIssueMessageID = id
        }
    }

    func forkReply(at sequence: Int, computer: SavedComputer) async -> String? {
        guard forkPending == nil, !forkUnknown.contains(sequence), let owner = sessionId else { return nil }
        let current = generation
        forkPending = sequence
        defer { if current == generation { forkPending = nil } }
        do {
            guard let result = try await call("session/fork", arguments: ["request": ["sessionId": owner, "atSeq": sequence]],
                                             computer: computer) as? [String: Any],
                  let id = result["sessionId"] as? String, !id.isEmpty else { throw MobileReplyFailure.invalidData }
            guard current == generation, sessionId == owner else { return nil }
            return id
        } catch {
            if current == generation, sessionId == owner {
                forkUnknown.insert(sequence)
                self.error = "分支创建结果未确认，请回到会话列表查看；此处不会重复创建"
            }
            return nil
        }
    }

    private func replyDocument(_ path: String, sequence: Int, index: Int? = nil, computer: SavedComputer) async throws -> Data {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let flag = index == nil ? "--dsh-mobile-test-change-summary" : "--dsh-mobile-test-change-diff"
        if let position = arguments.firstIndex(of: flag), arguments.indices.contains(position + 1),
           let data = arguments[position + 1].data(using: .utf8) {
            if arguments[position + 1] == "__expired__" { throw MobileReplyFailure.expired }
            return data
        }
        #endif
        guard let session, let owner = sessionId,
              var parts = URLComponents(string: computer.id) else { throw MobileReplyFailure.unavailable }
        let current = generation
        parts.path = path
        parts.queryItems = [URLQueryItem(name: "sessionId", value: owner), URLQueryItem(name: "seq", value: String(sequence))]
        if let index { parts.queryItems?.append(URLQueryItem(name: "index", value: String(index))) }
        guard let url = parts.url else { throw MobileReplyFailure.unavailable }
        let (data, response) = try await session.data(from: url)
        guard current == generation, sessionId == owner else { throw MobileReplyFailure.unavailable }
        if (response as? HTTPURLResponse)?.statusCode == 404 { throw MobileReplyFailure.expired }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MobileReplyFailure.unavailable }
        return data
    }

    func changesSummary(_ sequence: Int, computer: SavedComputer) async throws -> MobileChangesSummary {
        let data = try await replyDocument("/api/changes.summary", sequence: sequence, computer: computer)
        guard let value = try? JSONDecoder().decode(MobileChangesSummary.self, from: data) else {
            throw MobileReplyFailure.invalidData
        }
        guard value.valid else { throw MobileReplyFailure.invalidData }
        return value
    }

    func fileDiff(_ sequence: Int, index: Int, computer: SavedComputer) async throws -> MobileFileDiff {
        let data = try await replyDocument("/api/changes.diff", sequence: sequence, index: index, computer: computer)
        guard let value = try? JSONDecoder().decode(MobileFileDiff.self, from: data) else {
            throw MobileReplyFailure.invalidData
        }
        guard !value.path.isEmpty, !value.display.isEmpty,
              value.kind != .text || value.before != nil && value.after != nil && value.coarse != nil
                && value.hunks?.allSatisfy({ hunk in
                  hunk.oldStart >= 1 && hunk.newStart >= 1 && hunk.oldLines >= 0 && hunk.newLines >= 0
                    && hunk.lines.allSatisfy { $0.hasPrefix("+") || $0.hasPrefix("-") || $0.hasPrefix(" ") }
              }) == true else { throw MobileReplyFailure.invalidData }
        return value
    }

    #if DEBUG
    private func replyActionFixture(_ method: String, arguments: [String: Any]) throws -> Any {
        if method == "session/fork" {
            guard (arguments["request"] as? [String: Any])?["atSeq"] as? Int == 3 else { throw ChatFailure.unavailable }
            if ProcessInfo.processInfo.arguments.contains("fork-response-lost") { throw ChatFailure.unavailable }
            return ["sessionId": "fixture-fork"]
        }
        if method == "messageFeedback/list" { return ["ok": true, "value": ["items": Array(testFeedbackRecords.values)]] }
        let request = arguments["request"] as? [String: Any] ?? [:]
        guard let id = request["messageId"] as? String else { throw ChatFailure.unavailable }
        let mode = ProcessInfo.processInfo.arguments
        if mode.contains("feedback-rejected") { return ["ok": false, "error": ["code": "message-not-found"]] }
        if let observed = testFeedbackRecords[id] {
            if request["ifVersion"] as? String != observed["version"] as? String {
                return ["ok": false, "error": ["code": "version-conflict", "current": observed]]
            }
        } else if !(request["ifVersion"] is NSNull) {
            return ["ok": false, "error": ["code": "version-conflict", "current": NSNull()]]
        }
        if method == "messageFeedback/delete" {
            testFeedbackRecords.removeValue(forKey: id)
            return ["ok": true, "value": ["absent": true]]
        }
        let item: [String: Any] = ["messageId": id, "rating": request["rating"] ?? "positive", "version": UUID().uuidString]
        testFeedbackRecords[id] = item
        if mode.contains("feedback-response-lost") { throw ChatFailure.unavailable }
        return ["ok": true, "value": item]
    }
    #endif

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
            funds.account = Self.availableBalance(wallets + bonusWallets)
            funds.accountDetails = Self.balanceRows(wallets, label: "充值余额")
                + Self.balanceRows(bonusWallets, label: "赠金余额")
            models = [MobileModel(provider: "deepseek-account", model: "deepseek-v41-flash",
                                  name: "DeepSeek V41 Flash")]
            selectedModel = "deepseek-account/deepseek-v41-flash"
            if let index = arguments.firstIndex(of: "--dsh-mobile-test-api-balance"), arguments.indices.contains(index + 1) {
                funds.providers["deepseek-official"] = "¥" + arguments[index + 1]
                models.append(MobileModel(provider: "deepseek-official", model: "deepseek-chat",
                                          name: "DeepSeek V41 Flash"))
            }
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
                models = MobileModelCatalog.models(from: catalog)
                if selectedModel == nil, let fallback = MobileModelCatalog.defaultRoute(from: catalog) {
                    selectedModel = fallback
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
            await refreshBalances(computer: computer)
            error = nil
        } catch {
            self.error = "无法读取模型或权限设置，请重试"
        }
    }

    func refreshBalances(computer: SavedComputer) async {
        let revision = UUID()
        balanceRevision = revision
        let provider = selectedModel?.split(separator: "/").first.map(String.init)
        let value = await MobileBalanceSnapshot.load(provider: provider) { method, args in
            try await self.call(method, arguments: args, computer: computer)
        }
        guard revision == balanceRevision else { return }
        funds = value
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

    /// Applies one model route and reasoning level to the current Session.
    /// - Parameters:
    ///   - model: route the user chose.
    ///   - effort: reasoning level id; `nil` keeps the model's default level.
    ///   - computer: pairing used for the authenticated request.
    ///   - sessionId: Session receiving the selection.
    /// - Returns: `true` when the Host confirmed the selection.
    func selectModel(_ model: MobileModel, effort: String?, computer: SavedComputer,
                     sessionId: String) async -> Bool {
        guard selectingModelID == nil else { return false }
        guard MobileModelCatalog.requiresSelection(currentModel: selectedModel, currentEffort: selectedEffort,
                                                   model: model, effort: effort) else { return true }
        selectingModelID = model.id
        modelSelectionError = nil
        defer { selectingModelID = nil }
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--dsh-mobile-test-model-selection") {
                let success = await withCheckedContinuation { continuation in
                    testModelCompletion = continuation
                    testModelPending = true
                }
                guard success else {
                    modelSelectionError = "模型切换被拒绝，请重试"
                    return false
                }
                selectedModel = model.id
                selectedEffort = effort ?? model.defaultEffort
                return true
            }
            if ProcessInfo.processInfo.arguments.contains("--dsh-mobile-test-api-balance") {
                selectedModel = model.id
                selectedEffort = effort ?? model.defaultEffort
                return true
            }
            #endif
            var request: [String: Any] = ["sessionId": sessionId, "provider": model.provider, "model": model.model]
            if let effort { request["reasoningEffort"] = effort }
            _ = try await call("session/selectModel", arguments: ["request": request], computer: computer)
            selectedModel = model.id
            selectedEffort = effort ?? model.defaultEffort
            funds.providers.removeAll()
            Task { await refreshBalances(computer: computer) }
            MobileModelPreference.save(model.id, effort: selectedEffort, computerID: computer.id)
            return true
        } catch {
            modelSelectionError = "未确认模型切换结果，正在重新读取当前模型"
            await retry(computer: computer, sessionId: sessionId)
            return false
        }
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
        testModelCompletion?.resume(returning: false)
        testModelCompletion = nil
        testModelPending = false
        #endif
        generation = UUID()
        streamPublication?.cancel()
        streamPublication = nil
        disconnectToolOutputs()
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

private struct MobileForkTarget: Identifiable { let id: String }

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
    @State private var recommendationDraft = MobileRecommendationDraft()
    @State private var showingWorkspace = false
    @State private var showingSettings = false
    @State private var showingModels = false
    @State private var modelPickerDetent: PresentationDetent = .large
    @State private var effortTarget: MobileModel?
    @State private var effortDismissPicker = false
    @StateObject private var additions = MobileComposerAdditions()
    @State private var pendingPermission: RemotePermission?
    @State private var confirmingGoalClear = false
    @FocusState private var composerFocused: Bool
    @State private var followingLatest = true
    @State private var bottomVisible = true
    @State private var bottomPosition = CGFloat.infinity
    @State private var readingComposer = false
    @State private var forkTarget: MobileForkTarget?
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
                .mobileGlass(in: Circle(), interactive: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chatTitle).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    Text("\(project) · \(computer.name)")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
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
                .mobileGlass(in: Capsule(), interactive: true)
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
                                ForEach(chat.displayLines, id: \.presentationID) { line in
                                    chatRow(line)
                                        .id(line.presentationID)
                                }
                            }
                            if chat.liveActive && chat.liveText.isEmpty && !chat.lines.contains(where: { $0.role == "turn" }) {
                                Label("正在思考", systemImage: "sparkle")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    .simultaneousGesture(DragGesture().onChanged { gesture in
                        draggingTranscript = true
                        if abs(gesture.translation.height) > 12 && abs(gesture.translation.height) > abs(gesture.translation.width) {
                            readingComposer = true
                        }
                        followingLatest = false
                    }.onEnded { gesture in
                        draggingTranscript = false
                        if readingComposer { composerFocused = false }
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
                if let statusError = chat.composerStatusError {
                    Text(statusError).font(.caption).foregroundStyle(.orange)
                }
                if chat.planActive && additions.mode != .plan {
                    HStack {
                        Label("方案模式", systemImage: "list.bullet")
                        Spacer()
                        Button("退出方案模式") {
                            Task { await chat.composerCommand("/plan off", computer: computer, sessionId: sessionId) }
                        }
                        .disabled(chat.sending)
                    }
                    .font(.caption).frame(minHeight: 44)
                }
                if let objective = chat.goalObjective {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("目标：\(objective)").font(.caption).lineLimit(2)
                        HStack {
                            Text(chat.goalPhase == "active" ? "进行中" : chat.goalPhase == "complete" ? "已完成" : "已暂停或阻塞")
                            Spacer()
                            if chat.goalPhase != "complete" {
                                Button(chat.goalPhase == "active" ? "暂停目标" : "继续目标") {
                                    let line = chat.goalPhase == "active" ? "/goal pause" : "/goal resume"
                                    Task { await chat.composerCommand(line, computer: computer, sessionId: sessionId) }
                                }
                                .disabled(chat.sending)
                            }
                            Button("清除目标") { confirmingGoalClear = true }.disabled(chat.sending)
                        }
                        .font(.caption).frame(minHeight: 44)
                    }
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let seconds = chat.silentSeconds(now: context.date) {
                        HStack(spacing: 8) {
                            Text(MobileSilenceLabel.text(seconds: seconds))
                                .font(.caption).foregroundStyle(.orange)
                            Spacer(minLength: 8)
                            Button("停止") {
                                Task { await chat.cancel(computer: computer, sessionId: sessionId) }
                            }
                            .font(.caption).foregroundStyle(.secondary).frame(minHeight: 44)
                            Button("重新同步") {
                                Task { await chat.retry(computer: computer, sessionId: sessionId) }
                            }
                            .font(.caption).frame(minHeight: 44)
                            .accessibilityIdentifier("resyncSilentChat")
                        }
                    }
                }
                if chat.toolOutputUnavailable && chat.running {
                    HStack {
                        Text("实时输出服务暂不可用，工具最终结果仍会显示")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("重新连接") { Task { await chat.retry(computer: computer, sessionId: sessionId) } }
                            .font(.caption).frame(minHeight: 44)
                    }
                }
                MobileComposerAttachmentStrip(additions: additions)
                composerCard
            }
            .padding(.horizontal, 15).padding(.bottom, 10)
        }
        .background(Color(uiColor: .systemBackground))
        .toolbar(.hidden, for: .navigationBar)
        .task(id: sessionId) {
            await chat.connect(computer: computer, sessionId: sessionId)
            await chat.loadSettings(computer: computer)
            await chat.loadFeedback(computer: computer)
        }
        .fullScreenCover(item: $forkTarget) { target in
            RemoteChatView(computer: computer, sessionId: target.id, title: "分支对话", project: project,
                           onUnauthorized: onUnauthorized)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await chat.loadSettings(computer: computer) } }
            if phase == .active && !chat.connected && !chat.loading {
                Task { await chat.retry(computer: computer, sessionId: sessionId) }
            }
        }
        .onChange(of: chat.nextPrompts) { _ in applyRecommendation() }
        .onChange(of: chat.running) { running in
            if !running { applyRecommendation() }
        }
        .onDisappear { chat.disconnect() }
        .alert("清除当前目标？", isPresented: $confirmingGoalClear) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                Task { await chat.composerCommand("/goal clear", computer: computer, sessionId: sessionId) }
            }
        } message: { Text("清除后将停止自动追求此目标，已有对话会保留") }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            HStack {
                if chat.testSendPending {
                    Button("完成测试发送") { chat.completeTestSend() }
                }
                if ProcessInfo.processInfo.arguments.contains("--dsh-mobile-test-tool-output") {
                    Button("追加测试输出") { chat.appendTestToolOutput() }.accessibilityIdentifier("advanceInlineOutput")
                }
                if ProcessInfo.processInfo.arguments.contains("--dsh-mobile-test-append") {
                    Button("追加测试回复") { chat.appendTestReply() }
                }
                if ProcessInfo.processInfo.arguments.contains("--dsh-mobile-test-assistant-batches") {
                    Button("追加回复事件") { chat.appendTestAssistantBatch() }
                }
            }
            .font(.caption).padding(.top, 66)
        }
        .environment(\.advanceToolOutputFixture, toolOutputFixtureAction)
        #endif
        .sheet(isPresented: $showingWorkspace) {
            if let url = URL(string: computer.url) {
                DshWebView(url: url, sessionId: sessionId, onUnauthorized: onUnauthorized)
            }
        }
        .mobileComposerActions(additions, computer: computer, planActive: chat.planActive) {
            Task { await chat.composerCommand("/plan off", computer: computer, sessionId: sessionId) }
        }
        .sheet(isPresented: $showingModels) { modelPicker }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                Form {
                    Section("模型") {
                        if chat.models.isEmpty { Text("暂无可选模型").foregroundStyle(.secondary) }
                        ForEach(chat.models) { model in
                            Button {
                                chooseModel(model, dismissPicker: false)
                            } label: {
                                modelSelectionRow(model)
                            }
                            .disabled(chat.selectingModelID != nil || !chat.connected)
                            .accessibilityLabel(mobileModelDisplayName(model.name, modelID: model.model, provider: model.provider))
                            .accessibilityValue(chat.selectingModelID == model.id ? "正在切换" : chat.selectedModel == model.id ? "当前模型" : "")
                            .accessibilityHint("\(model.provider)/\(model.model)")
                        }
                    }
                    if let error = chat.modelSelectionError { Text(error).foregroundStyle(.orange) }
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
                        Text("账号余额 \(chat.funds.account ?? "暂不可用")")
                        Text("API 余额 \(chat.funds.providers["deepseek-official"] ?? "暂不可用")")
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
            .confirmationDialog("选择思考深度", isPresented: effortDialog, titleVisibility: .visible) {
                effortOptions()
                Button("取消", role: .cancel) { effortTarget = nil }
            } message: { Text(effortDialogMessage) }
        }
    }

    private var modelPicker: some View {
            NavigationStack {
                List {
                    #if DEBUG
                    if chat.testModelPending {
                        Button("完成测试模型切换") { chat.completeTestModelSelection() }
                    }
                    #endif
                    if chat.settingsLoading && chat.models.isEmpty {
                        ProgressView().accessibilityLabel("正在读取模型")
                    } else if chat.models.isEmpty {
                        Text("暂无可选模型").foregroundStyle(.secondary)
                        Button("重试读取模型") { Task { await chat.loadSettings(computer: computer) } }
                    }
                    if let error = chat.modelSelectionError { Text(error).foregroundStyle(.orange) }
                    if chat.running { Text("选择将用于后续请求，当前请求继续使用原模型").font(.caption).foregroundStyle(.secondary) }
                    ForEach(Array(Set(chat.models.map(\.provider))).sorted(), id: \.self) { provider in
                        Section(provider == "deepseek-account" ? "账号模型" : "API 模型 · \(provider)") {
                            ForEach(chat.models.filter { $0.provider == provider }) { model in
                                Button {
                                    chooseModel(model, dismissPicker: true)
                                } label: { modelSelectionRow(model) }
                                .disabled(chat.selectingModelID != nil || !chat.connected)
                                .accessibilityLabel(mobileModelDisplayName(model.name, modelID: model.model, provider: model.provider))
                                .accessibilityValue(chat.selectingModelID == model.id ? "正在切换" : chat.selectedModel == model.id ? "当前模型" : "")
                                .accessibilityHint("\(model.provider)/\(model.model)")
                            }
                        }
                    }
                }
                .navigationTitle("选择模型")
                .toolbar { Button("完成") { showingModels = false } }
            }
            .presentationDetents([.medium, .large], selection: $modelPickerDetent)
            .confirmationDialog("选择思考深度", isPresented: effortDialog, titleVisibility: .visible) {
                effortOptions()
                Button("取消", role: .cancel) { effortTarget = nil }
            } message: { Text(effortDialogMessage) }
    }

    #if DEBUG
    private var toolOutputFixtureAction: (() -> Void)? {
        guard ProcessInfo.processInfo.arguments.contains("--dsh-mobile-test-tool-output") else { return nil }
        return { chat.appendTestToolOutput() }
    }
    #endif

    private func modelSelectionRow(_ model: MobileModel) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(mobileModelDisplayName(model.name, modelID: model.model, provider: model.provider))
                    .foregroundStyle(.primary)
                Text(model.model).font(.caption).foregroundStyle(.secondary)
                if let detail = model.detail, !detail.isEmpty {
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let effort = effortLabel(for: model) {
                Text(effort).font(.caption).foregroundStyle(.secondary)
            }
            if chat.selectingModelID == model.id {
                ProgressView().accessibilityLabel("正在切换模型")
            } else if chat.selectedModel == model.id {
                Image(systemName: "checkmark").accessibilityLabel("当前模型")
            }
        }
        .frame(minHeight: 44)
    }

    /// The reasoning level shown beside one model row.
    /// - Parameter model: route listed in the picker.
    /// - Returns: the Host's label for the level this row would apply, or nil without levels.
    private func effortLabel(for model: MobileModel) -> String? {
        guard !model.efforts.isEmpty else { return nil }
        let effort = chat.selectedModel == model.id
            ? (chat.selectedEffort ?? model.defaultEffort) : model.defaultEffort
        return MobileModelCatalog.effortName(effort, in: model)
    }

    /// Applies a model choice, asking for a reasoning level when the route offers several.
    /// - Parameters:
    ///   - model: route the user tapped.
    ///   - dismissPicker: whether a confirmed choice closes the model sheet.
    private func chooseModel(_ model: MobileModel, dismissPicker: Bool) {
        guard !model.efforts.isEmpty else {
            Task {
                if await chat.selectModel(model, effort: nil, computer: computer, sessionId: sessionId),
                   dismissPicker { showingModels = false }
            }
            return
        }
        effortDismissPicker = dismissPicker
        effortTarget = model
    }

    /// Applies the reasoning level the user chose for the pending model route.
    /// - Parameter effort: level the Host declared for that route.
    private func chooseEffort(_ effort: MobileModelReasoning) {
        guard let model = effortTarget else { return }
        let dismissPicker = effortDismissPicker
        effortTarget = nil
        Task {
            if await chat.selectModel(model, effort: effort.id, computer: computer, sessionId: sessionId),
               dismissPicker { showingModels = false }
        }
    }

    /// Lists the reasoning levels of the pending route.
    private func effortOptions() -> some View {
        ForEach(effortTarget?.efforts ?? []) { effort in
            Button(effort.name) { chooseEffort(effort) }
        }
    }

    /// Drives the reasoning-level dialog from the row the user tapped.
    private var effortDialog: Binding<Bool> {
        Binding(get: { effortTarget != nil }, set: { if !$0 { effortTarget = nil } })
    }

    /// Explains what the pending route's reasoning levels change.
    private var effortDialogMessage: String {
        guard let model = effortTarget else { return "" }
        return "\(mobileModelDisplayName(model.name, modelID: model.model, provider: model.provider))：档位越高，思考越深、用时越长"
    }

    private var compactComposer: Bool {
        readingComposer && !composerFocused && !additions.hasAttachments && additions.mode == .message
    }

    private var chatTitle: String {
        let value = chat.sessionTitle ?? title
        return chat.isFork && !value.hasPrefix("分支") ? "分支 · \(value)" : value
    }

    @ViewBuilder
    private var composerCard: some View {
        if compactComposer {
            HStack(spacing: 0) {
                addMenu
                Button {
                    readingComposer = false
                    composerFocused = true
                } label: {
                    Text(draft.isEmpty ? "在 \(computer.name) 上工作" : draft)
                        .font(.subheadline)
                        .foregroundStyle(draft.isEmpty ? Color.secondary : Color.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .accessibilityLabel("展开输入框")
                .accessibilityIdentifier("expandChatComposer")
                primaryButton
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .mobileGlass(in: Capsule())
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !chat.running && (!chat.nextPrompts.prompts.isEmpty || chat.nextPrompts.failed) {
                    nextPromptSuggestions
                }
                composerInput.padding(.horizontal, 7)
                HStack(spacing: 0) {
                    addMenu
                    permissionButton
                    HStack(spacing: 4) {
                        modelBadge
                        balanceBadge.layoutPriority(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    primaryButton
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 9)
            .mobileGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var composerInput: some View {
        TextField("在 \(computer.name) 上工作", text: $draft, axis: .vertical)
            .font(.subheadline)
            .lineLimit(1...5)
            .focused($composerFocused)
            .accessibilityIdentifier("chatComposerInput")
    }

    private var modelBadge: some View {
        Button {
            composerFocused = false
            modelPickerDetent = .large
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
        let provider = model?.provider ?? selectedModel.split(separator: "/").first.map(String.init) ?? ""
        let name = mobileModelDisplayName(model?.name ?? modelID, modelID: modelID, provider: provider)
        guard let effort = MobileModelCatalog.effortName(chat.selectedEffort, in: model) else { return name }
        return "\(name) · \(effort)"
    }

    @ViewBuilder private var balanceBadge: some View {
        if chat.selectedModel != nil {
            Text("余额 \(chat.balance ?? "暂不可用")")
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
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 17))
                .foregroundStyle(.orange)
                .frame(width: 44, height: 44)
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
        MobileComposerAddButton(additions: additions) { composerFocused = false }
            .disabled(chat.sending || additions.importing)
    }

    private var primaryButton: some View {
        let stopping = chat.running && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !additions.hasAttachments
        let busy = chat.sending || chat.cancelling
        let enabled = (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || additions.hasAttachments)
            && !chat.sending && !chat.loading && chat.connected && !additions.importing
            && (additions.mode != .goal || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        return Button {
            if stopping {
                Task { await chat.cancel(computer: computer, sessionId: sessionId) }
                return
            }
            let submittedDraft = draft
            let submittedAttachments = additions.attachments
            let submittedMode = additions.mode
            let text = submittedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            scrollRequestCount += 1
            Task {
                if await chat.send(text, attachments: submittedAttachments, mode: submittedMode,
                                   computer: computer, sessionId: sessionId) {
                    if draft == submittedDraft { draft = "" }
                    let delivered = Set(submittedAttachments.map(\.id))
                    additions.attachments.removeAll { delivered.contains($0.id) }
                    if additions.mode == submittedMode { additions.mode = .message }
                }
            }
        } label: {
            Group {
                if busy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: stopping ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 34, height: 34)
            .background(enabled || stopping || busy ? Color.blue : Color(uiColor: .tertiaryLabel), in: Circle())
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .disabled(busy || (stopping ? !chat.connected : !enabled))
        .accessibilityLabel(chat.cancelling ? "正在停止" : chat.sending ? "正在发送" : stopping ? "停止运行" : "发送")
        .contextMenu {
            if chat.running && !stopping {
                Button("停止当前任务", role: .destructive) {
                    Task { await chat.cancel(computer: computer, sessionId: sessionId) }
                }
                .disabled(busy || !chat.connected)
            }
        }
    }

    private func applyRecommendation() {
        guard !chat.running else { return }
        draft = recommendationDraft.receiving(chat.nextPrompts, draft: draft)
    }

    private var nextPromptSuggestions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(chat.nextPrompts.failed ? "暂时无法生成建议，可继续输入" : "下一步建议")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chat.nextPrompts.prompts, id: \.self) { prompt in
                        Button {
                            draft = recommendationDraft.selecting(prompt, draft: draft)
                            composerFocused = true
                        } label: {
                            Text(prompt).font(.caption).lineLimit(1)
                                .frame(maxWidth: 220, minHeight: 44, alignment: .leading)
                                .padding(.horizontal, 12)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(chat.sending)
                        .accessibilityIdentifier("nextPromptSuggestion")
                    }
                }
            }
        }
        .accessibilityIdentifier("composerRecommendations")
    }

    private func inspectProcess() {
        followingLatest = false
        composerFocused = false
    }

    /// Bridges the chat's thumbnail cache into the attachment summary view.
    private var attachmentPreview: MobileAttachmentPreviewSource {
        MobileAttachmentPreviewSource(
            image: { chat.attachmentImage($0) },
            failed: { chat.attachmentFailed($0) },
            load: { await chat.loadAttachmentImage($0) },
            retry: { chat.retryAttachment($0) })
    }

    private func chatRow(_ line: ChatLine) -> some View {
        HStack(alignment: .top) {
            if line.role == "user" { Spacer(minLength: 45) }
            if line.role == "activity" {
                ActivityGroupView(activities: line.activities, toolOutputs: chat.toolOutputs, onInspect: inspectProcess)
            } else if line.role == "turn" {
                TurnProcessView(startedAt: line.startedAt, endedAt: line.endedAt, endReason: line.endReason,
                                lastActivityAt: line.lastActivityAt,
                                activities: line.activities, reasoning: line.reasoning,
                                liveReasoning: chat.lines.last(where: { $0.role == "turn" })?.id == line.id
                                    ? chat.liveReasoning : "", toolOutputs: chat.toolOutputs, onInspect: inspectProcess)
            } else if line.role == "assistant" {
                VStack(alignment: .leading, spacing: 4) {
                    if !line.attachments.isEmpty {
                        MobileMessageAttachmentSummary(attachments: line.attachments, preview: attachmentPreview)
                    }
                    if !line.text.isEmpty {
                        AssistantMessageView(text: line.text, reasoning: line.reasoning, showCopy: false)
                    }
                    if line.live {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(chat.reconnecting ? "正在恢复回复" : "正在回复").font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("assistantReplyStreaming")
                    } else {
                        if line.interrupted { Text("已停止 · 保留已收到的回复").font(.caption).foregroundStyle(.secondary) }
                        if isLastAssistantInTurn(line.id), replyTurn(line)?.endedAt != nil || replyTurn(line) == nil {
                            replyFooter(line)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if !line.attachments.isEmpty {
                        MobileMessageAttachmentSummary(attachments: line.attachments, preview: attachmentPreview)
                    }
                    if !line.text.isEmpty {
                        Text(line.text)
                            .font(.system(size: 16, weight: .medium)).lineSpacing(5)
                            .foregroundStyle(colorScheme == .dark ? .white : Color(red: 0.05, green: 0.42, blue: 0.76))
                            .textSelection(.enabled)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(colorScheme == .dark ? Color(red: 0.02, green: 0.29, blue: 0.53)
                                        : Color(red: 0.88, green: 0.95, blue: 1),
                                        in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
            if line.role != "user" { Spacer(minLength: 20) }
        }
    }

    private func replyTurn(_ line: ChatLine) -> ChatLine? {
        if let turn = line.turn { return chat.lines.last(where: { $0.role == "turn" && $0.turn == turn }) }
        guard let index = chat.lines.firstIndex(where: { $0.id == line.id }) else { return nil }
        return chat.lines.prefix(index).last(where: { $0.role == "turn" })
    }

    private func replyFooter(_ line: ChatLine) -> some View {
        let cut = replyTurn(line)?.endSequence ?? line.mergedEventIds.max() ?? line.id
        let issueID = chat.feedbackIssueMessageID ?? chat.lines.last(where: { $0.role == "assistant" })?.messageID
        return VStack(alignment: .leading, spacing: 8) {
            MobileReplyActionsView(text: line.text, timestamp: line.timestamp,
                rating: line.messageID.flatMap { chat.feedbackItems[$0]?.rating },
                feedbackEnabled: chat.feedbackLoaded && chat.feedbackPending == nil && line.messageID != nil,
                feedbackBusy: chat.feedbackPending == line.messageID && line.messageID != nil,
                pendingRating: chat.feedbackPendingRating,
                feedbackError: line.messageID != nil && issueID == line.messageID ? chat.feedbackError : nil,
                forkEnabled: line.messageID != nil && chat.forkPending == nil && !chat.forkUnknown.contains(cut),
                forkBusy: chat.forkPending == cut,
                rate: { rating in
                    if let id = line.messageID { Task { await chat.rateReply(id, rating: rating, computer: computer) } }
                }, fork: {
                    Task {
                        if let id = await chat.forkReply(at: cut, computer: computer) { forkTarget = MobileForkTarget(id: id) }
                    }
                }, retryFeedback: { Task { await chat.loadFeedback(computer: computer) } })
            if let sequence = replyTurn(line)?.changesSequence {
                MobileChangesView(sequence: sequence,
                    loadSummary: { try await chat.changesSummary($0, computer: computer) },
                    loadDiff: { try await chat.fileDiff($0, index: $1, computer: computer) })
                    .frame(maxWidth: .infinity, alignment: .center)
            }
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

/// Category counts shared by the compact process strip and the running turn header.
private func mobileActivitySummary(_ activities: [MobileChatActivity]) -> String {
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

private struct ActivityGroupView: View {
    let activities: [MobileChatActivity]
    let toolOutputs: [String: MobileToolOutput]

    private var title: String {
        mobileActivitySummary(activities)
    }

    let onInspect: () -> Void

    var body: some View {
        ProcessDisclosureView(summary: title, reasoning: "", activities: activities, toolOutputs: toolOutputs, onInspect: onInspect)
    }
}

private struct TurnProcessView: View {
    let startedAt: TimeInterval?
    let endedAt: TimeInterval?
    let endReason: String?
    let lastActivityAt: TimeInterval?
    let activities: [MobileChatActivity]
    let reasoning: String?
    let liveReasoning: String
    let toolOutputs: [String: MobileToolOutput]
    let onInspect: () -> Void

    private var processSummary: String {
        let count = activities.count
        let failed = activities.filter(\.failed).count
        if count == 0 { return endedAt == nil ? "正在思考" : "查看过程" }
        let summary = mobileActivitySummary(activities)
        return failed == 0 ? summary : "\(summary)，\(failed) 项失败"
    }

    private func activityAge(now: Date) -> String? {
        guard endedAt == nil, let lastActivityAt, lastActivityAt > 0 else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince1970 - lastActivityAt / 1000))
        if seconds < 5 { return "最后活动刚刚" }
        if seconds < 60 { return "最后活动 \(seconds) 秒前" }
        return "最后活动 \(seconds / 60) 分 \(seconds % 60) 秒前"
    }

    private func title(now: Date) -> String {
        let outcome = mobileTurnStatus(endReason)
        guard let startedAt, startedAt > 0 else {
            return endedAt == nil ? "正在处理" : outcome ?? "已完成工作"
        }
        let end = endedAt ?? now.timeIntervalSince1970 * 1000
        let seconds = max(0, Int((end - startedAt) / 1000))
        let duration = seconds < 60 ? "\(seconds) 秒" : "\(seconds / 60) 分 \(seconds % 60) 秒"
        return endedAt == nil ? "已运行 \(duration)" : outcome.map { "\($0) · 用时 \(duration)" } ?? "用时 \(duration)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(now: context.date))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    if let age = activityAge(now: context.date) {
                        Text(age).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            ProcessDisclosureView(summary: processSummary,
                reasoning: [reasoning, liveReasoning.isEmpty ? nil : liveReasoning]
                    .compactMap { $0 }.joined(separator: "\n\n"),
                activities: activities, toolOutputs: toolOutputs, onInspect: onInspect)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Keeps the transcript preview bounded while full live details remain independently dismissible.
private struct ProcessDisclosureView: View {
    #if DEBUG
    @Environment(\.advanceToolOutputFixture) private var advanceFixture
    #endif
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let summary: String
    let reasoning: String
    let activities: [MobileChatActivity]
    let toolOutputs: [String: MobileToolOutput]
    let onInspect: () -> Void
    @State private var collapseVersion = 0
    @State private var reasoningExpanded = false
    @State private var expanded = false
    @State private var showingDetails = false
    @State private var detailDetent: PresentationDetent = .large

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onInspect()
                expanded.toggle()
            } label: {
                HStack {
                    Label(summary, systemImage: "list.bullet.clipboard")
                    Spacer(minLength: 8)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .font(.system(size: 13))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "已展开" : "已收起")
            if expanded {
                if !reasoning.isEmpty {
                    Text(reasoning).font(.system(size: 13)).lineLimit(4)
                }
                ForEach(Array(activities.suffix(3))) { activity in
                    VStack(alignment: .leading, spacing: 4) {
                        activityRow(activity, preview: true)
                        if let output = previewOutput(activity) {
                            Text(output)
                                .font(.system(.caption, design: .monospaced)).lineLimit(2)
                                .accessibilityIdentifier("liveToolPreview")
                        }
                    }
                }
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) { detailButton; collapseButton }
                } else {
                    HStack { detailButton; Spacer(); collapseButton }
                }
            }
        }
        .foregroundStyle(.secondary)
        .sheet(isPresented: $showingDetails) {
            VStack(spacing: 0) {
                processHeader.padding(.horizontal, 16).padding(.vertical, 8)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(activities) { activity in
                            ProcessActivityDetail(activity: activity, liveJobs: activity.jobIDs.compactMap { toolOutputs[$0] },
                                collapseVersion: collapseVersion, initiallyExpanded: activities.count <= 3 && collapseVersion == 0)
                        }
                        if !reasoning.isEmpty {
                            DisclosureGroup("思考过程", isExpanded: $reasoningExpanded) {
                                Text(reasoning).font(.body).textSelection(.enabled).padding(.top, 8)
                                    .accessibilityIdentifier("processFullReasoning")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .accessibilityIdentifier("processDetailScroll")
                #if DEBUG
                if let advanceFixture {
                    Button("追加测试输出", action: advanceFixture).accessibilityIdentifier("advanceDetailOutput")
                        .frame(minHeight: 44).padding(.horizontal)
                }
                #endif
            }
            .background(Color(uiColor: .systemBackground))
            .presentationDetents([.medium, .large], selection: $detailDetent)
            .presentationDragIndicator(.visible)
        }
    }

    private var processHeader: some View {
        VStack(spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("执行过程").font(.headline).foregroundStyle(.primary).accessibilityAddTraits(.isHeader)
                HStack { collapseAllButton; Spacer(); closeDetailsButton }
            } else {
                HStack {
                    collapseAllButton
                    Spacer(minLength: 8)
                    Text("执行过程").font(.headline).foregroundStyle(.primary).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    closeDetailsButton
                }
            }
        }
    }

    private var collapseAllButton: some View {
        Button("全部收起") { collapseVersion += 1; reasoningExpanded = false }
            .frame(minHeight: 44).foregroundStyle(Color.accentColor)
    }

    private var closeDetailsButton: some View {
        Button("完成") { showingDetails = false }
            .frame(minHeight: 44).foregroundStyle(Color.accentColor).accessibilityLabel("关闭过程详情")
    }

    private var detailButton: some View {
        Button("查看完整过程") { detailDetent = .large; showingDetails = true }
            .font(.caption).foregroundStyle(Color.accentColor).frame(minHeight: 44)
    }

    private var collapseButton: some View {
        Button("收起过程") { expanded = false }
            .font(.caption).foregroundStyle(Color.accentColor).frame(minHeight: 44)
    }

    private func previewOutput(_ activity: MobileChatActivity) -> String? {
        if let output = activity.jobIDs.compactMap({ toolOutputs[$0] }).last, !output.text.isEmpty {
            return output.text.split(separator: "\n").suffix(2).joined(separator: "\n")
        }
        guard let output = activity.output, !output.isEmpty else { return nil }
        return output.split(separator: "\n").suffix(2).joined(separator: "\n")
    }

    private func activityRow(_ activity: MobileChatActivity, preview: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: activity.cancelled ? "stop.circle" : activity.failed ? "exclamationmark.circle" :
                    activity.finished ? "checkmark.circle" : "circle.dotted")
            Text(activity.detail).lineLimit(preview ? 2 : nil).textSelection(.enabled)
                .accessibilityValue(activity.status)
        }
        .font(.system(size: preview ? 12 : 14))
        .foregroundStyle(activity.failed ? Color.orange : Color(uiColor: .secondaryLabel))
    }
}

/// Full call arguments and returned output stay outside the bounded transcript preview.
private struct ProcessActivityDetail: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let activity: MobileChatActivity
    let liveJobs: [MobileToolOutput]
    let collapseVersion: Int
    @State private var expanded: Bool
    @State private var outputLimit = 12000

    init(activity: MobileChatActivity, liveJobs: [MobileToolOutput], collapseVersion: Int, initiallyExpanded: Bool) {
        self.activity = activity
        self.liveJobs = liveJobs
        self.collapseVersion = collapseVersion
        _expanded = State(initialValue: initiallyExpanded)
    }

    private var activityStatus: String {
        if !activity.finished, !liveJobs.isEmpty, liveJobs.allSatisfy({ !$0.active && $0.phase != .unavailable }) {
            return "等待工具返回"
        }
        return activity.status
    }

    private var activitySummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("\(activity.category) · \(activity.name)").font(.subheadline)
                statusLabel
            } else {
                HStack {
                    Text("\(activity.category) · \(activity.name)").font(.subheadline)
                    Spacer()
                    statusLabel
                }
            }
            Text(activity.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .accessibilityIdentifier("toolDetailTitle-\(activity.id)")
        }
        .frame(minHeight: 44)
    }

    private var statusLabel: some View {
        Text(activityStatus).font(.caption).foregroundStyle(activity.failed ? Color.orange : Color.secondary)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(liveJobs) { output in LiveToolOutputView(output: output) }
                if !activity.invocation.isEmpty {
                    Text(activity.invocation == activity.parameters ? "调用参数" : "命令")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(activity.invocation).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    if activity.invocation != activity.parameters {
                        DisclosureGroup("全部调用参数") {
                            Text(activity.parameters).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
                if let output = activity.output {
                    HStack {
                        Text("工具输出").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("复制输出") { UIPasteboard.general.string = output }
                            .font(.caption).frame(minHeight: 44)
                    }
                    Text(String(output.prefix(outputLimit)))
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    if output.count > outputLimit {
                        Button("显示更多输出") { outputLimit += 12000 }.frame(minHeight: 44)
                    }
                } else {
                    Text(activity.finished ? "工具未返回文字输出" : liveJobs.isEmpty ? "此工具尚未提供实时输出，等待工具返回" : "最终结果将在工具返回后显示")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        } label: { activitySummary }
        .tint(.accentColor)
        .onChange(of: collapseVersion) { _ in expanded = false }
    }
}

private struct ChatBottomPreference: PreferenceKey {
    static var defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
