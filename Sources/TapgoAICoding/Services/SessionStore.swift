import Foundation
import SwiftUI
import TapgoCore

/// Top-level state container. Owns the `WorkspaceStore` (projects +
/// remote hosts), `ThreadStore` (persisted threads), and a
/// `CodexHarnessClient` per active thread. All mutations go through
/// here so persistence + UI stay in sync.
///
/// **Remote-thread architecture** (replaces the old "local exec + SSH
/// override UI" deception):
///   - When the active thread is bound to a remote project, we
///     spawn a `RemoteSSHHarnessTransport` — a `codex app-server`
///     process running on the remote host. JSON-RPC frames flow
///     over the SSH subprocess's stdio.
///   - The remote harness is the *only* source of truth: the
///     `exec_command` it spawns runs on the remote host, and the
///     stdout/stderr/exitCode the model sees are the *real* ones
///     from the remote shell.
///   - The API key is delivered through the SSH subprocess's
///     stdin as the first line — never written to the remote disk,
///     command line, or log file. Lifetime == SSH subprocess.
@MainActor
final class SessionStore: ObservableObject {
    let workspace: WorkspaceStore
    let threads: ThreadStore

    /// One harness client per active thread. The transport
    /// (local or remote) is built when the user starts a turn on
    /// a thread. We don't keep them around for the lifetime of
    /// the app because that would hold an idle SSH connection.
    private var runner: CodexHarnessClient?

    // Live state
    @Published var activeThreadId: String?
    @Published var runnerState: CodexHarnessClient.RunState = .idle
    @Published var attachedImages: [URL] = []
    /// Session-local feedback votes (turn id → 1 up / -1 down / 0 none),
    /// mirroring Codex's message action bar without a remote backend.
    @Published var turnFeedback: [String: Int] = [:]
    @Published var setupError: SetupError?

    /// Approval requests the harness is waiting on, keyed by request id.
    /// `ApprovalRow` watches this and resolves entries by calling
    /// `respondToApproval`.
    @Published var pendingApprovals: [String: ApprovalRequest] = [:]

    /// Mirror of persisted threads (live turns in-memory only).
    @Published private(set) var liveThreads: [TapgoCore.Thread] = []

    var modelName: String { TapgoConfig.modelName }

    private static let lastThreadKey = "tapgo.lastThreadId"

    init(workspace: WorkspaceStore, threads: ThreadStore) {
        self.workspace = workspace
        self.threads = threads
        self.liveThreads = threads.threads
        // Start on the centered "我们该处理什么工作？" empty state rather
        // than auto-selecting the last thread — the user picks a
        // conversation (or starts a new one) from there.
        self.activeThreadId = nil
        if (try? TapgoConfig.ensureReady()) == nil {
            setupError = catchSetupError()
        }
    }

    private func catchSetupError() -> SetupError? {
        do {
            try TapgoConfig.ensureReady()
            return nil
        } catch let e as SetupError { return e }
        catch { return .missingConfig(TapgoConfig.configPath.path) }
    }

    // MARK: - Image attach

    func addImages(_ urls: [URL]) {
        let valid = urls.filter {
            let exists = FileManager.default.fileExists(atPath: $0.path)
            let isImage = ["png", "jpg", "jpeg", "gif", "webp"].contains($0.pathExtension.lowercased())
            return exists && isImage
        }
        attachedImages.append(contentsOf: valid)
        attachedImages = Array(Set(attachedImages))
    }

    func removeImage(_ url: URL) {
        attachedImages.removeAll { $0 == url }
    }

    func clearImages() {
        attachedImages = []
    }

    /// Toggle a feedback vote for a turn (clicking the same value clears it).
    func setTurnFeedback(_ turnId: String, _ value: Int) {
        turnFeedback[turnId] = (turnFeedback[turnId] == value) ? 0 : value
    }

    // MARK: - Project mutations (delegate to WorkspaceStore)

    func setActiveProject(_ id: String?) {
        workspace.setActiveProject(id)
        // Auto-select the most recent thread in the newly-active project so
        // switching project (from the sidebar header or the composer menu)
        // lands on useful context instead of an empty chat.
        if let id {
            if let t = liveThreads
                .filter({ $0.projectId == id })
                .max(by: { $0.updatedAt < $1.updatedAt }) {
                activeThreadId = t.id
            } else {
                activeThreadId = nil
            }
        } else {
            activeThreadId = nil
        }
        persistActiveThread()
    }

    func activeProject() -> Project? {
        workspace.state.activeProject
    }

    // MARK: - TapgoCore.Thread selection / creation

    func selectThread(_ id: String) {
        activeThreadId = id
        // Keep the top-left project chip in sync with the selected
        // thread's project, so selecting a thread in project B no longer
        // leaves the header stuck on a previously-active project A.
        if let t = liveThreads.first(where: { $0.id == id }) {
            workspace.setActiveProject(t.projectId)
        }
        persistActiveThread()
        // When the user switches conversation, put focus back on the
        // composer so they can start typing immediately (Codex behavior).
        NotificationCenter.default.post(name: .tapgoFocusComposer, object: nil)
    }

    private func persistActiveThread() {
        UserDefaults.standard.set(activeThreadId, forKey: Self.lastThreadKey)
    }

    /// Create a new thread in the active project (if any). For
    /// remote projects the thread's `cwd` is the *actual* remote
    /// path (e.g. `/Users/remoteuser/workspaces`), NOT a local
    /// mirror. The remote harness will see that path and chdir
    /// into it on its own host.
    func newThread(title: String? = nil) {
        let project = activeProject()
        let cwd = project?.remotePath ?? project?.harnessCwd
        let t = TapgoCore.Thread(
            id: "local-" + UUID().uuidString,
            title: title ?? L10n.newThread,
            createdAt: Date(),
            updatedAt: Date(),
            projectId: project?.id,
            cwd: cwd,
            harnessThreadId: nil,
            turns: []
        )
        liveThreads.insert(t, at: 0)
        threads.save(t)
        activeThreadId = t.id
        persistActiveThread()
        NotificationCenter.default.post(name: .tapgoClearComposer, object: nil)
        NotificationCenter.default.post(name: .tapgoFocusComposer, object: nil)
    }

    func deleteThread(_ id: String) {
        liveThreads.removeAll { $0.id == id }
        threads.delete(id)
        if activeThreadId == id { activeThreadId = liveThreads.first?.id }
        persistActiveThread()
    }

    func renameThread(_ id: String, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = liveThreads.firstIndex(where: { $0.id == id }) else { return }
        liveThreads[idx].title = trimmed
        liveThreads[idx].updatedAt = Date()
        threads.save(liveThreads[idx])
    }

    /// Set / clear the active thread's session goal (`/goal` command). An
    /// empty string clears it. Persisted with the thread.
    func setActiveThreadGoal(_ goal: String?) {
        guard let id = activeThreadId,
              let idx = liveThreads.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = goal?.trimmingCharacters(in: .whitespacesAndNewlines)
        liveThreads[idx].goal = (trimmed?.isEmpty == false) ? trimmed : nil
        liveThreads[idx].updatedAt = Date()
        threads.save(liveThreads[idx])
    }

    func togglePinned(_ id: String) {
        guard let idx = liveThreads.firstIndex(where: { $0.id == id }) else { return }
        liveThreads[idx].isPinned.toggle()
        liveThreads[idx].updatedAt = Date()
        threads.save(liveThreads[idx])
    }

    func updateThreadHarness(threadId: String, harnessThreadId: String) {
        guard let idx = liveThreads.firstIndex(where: { $0.id == threadId }) else { return }
        liveThreads[idx].harnessThreadId = harnessThreadId
        liveThreads[idx].updatedAt = Date()
        threads.save(liveThreads[idx])
    }

    /// Re-validate setup after the user runs `init-tapgo.sh`.
    func revalidateSetup() { setupError = catchSetupError() }

    // MARK: - Send user message

    func sendUserMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImages = !attachedImages.isEmpty
        guard !trimmed.isEmpty || hasImages else { return }
        if setupError != nil { return }
        if activeThreadId == nil { newThread() }
        guard let threadId = activeThreadId,
              let idx = liveThreads.firstIndex(where: { $0.id == threadId })
        else { return }
        guard !isRunning else { return }

        let displayText: String
        if trimmed.isEmpty { displayText = hasImages ? "(图片)" : "" }
        else { displayText = trimmed }

        let turn = Turn(
            id: "turn-" + UUID().uuidString,
            userInput: displayText,
            items: [.userMessage(id: "u-" + UUID().uuidString, text: displayText)],
            status: .running,
            startedAt: Date(),
            completedAt: nil
        )
        liveThreads[idx].turns.append(turn)
        liveThreads[idx].updatedAt = Date()
        // Auto-title: when the user sends the first message of a
        // brand-new thread, derive a short title from it. Codex
        // does this; we mirror the behaviour so the sidebar row
        // becomes identifiable as soon as the user types.
        if liveThreads[idx].hasDefaultTitle, !displayText.isEmpty {
            liveThreads[idx].title = TapgoCore.Thread.autoTitle(from: displayText)
        }
        threads.save(liveThreads[idx])
        let turnIdx = liveThreads[idx].turns.count - 1

        // Only reuse the harness thread when its last turn finished cleanly
        // (completed / failed). Resuming a thread whose turn was interrupted
        // mid-flight (or is still running) can collide with the harness's
        // active writer ("already has an active writer"), so start fresh.
        let resumeId: String?
        if let lastStatus = liveThreads[idx].turns.last?.status,
           lastStatus == .completed || lastStatus == .failed {
            resumeId = liveThreads[idx].harnessThreadId
        } else {
            resumeId = nil
        }
        let cwd = liveThreads[idx].cwd
        let project = liveThreads[idx].projectId.flatMap { workspace.project(byId: $0) }
        let imagesToUse = attachedImages
        attachedImages = []

        // For remote threads, inject a stable environment preamble
        // so the model *knows* it's on the remote host and won't
        // try to `ssh` again from there.
        let effectivePrompt = Self.composeEffectivePrompt(
            userPrompt: trimmed,
            project: project
        )

        // Build the right transport for this thread.
        let newRunner = makeRunner(for: project)
        runner = newRunner

        Task { [weak self] in
            guard let self else { return }
            let finalState = await newRunner.run(
                prompt: effectivePrompt,
                resumeThreadId: resumeId,
                cwd: cwd,
                images: imagesToUse
            ) { [weak self] event in
                self?.handle(event: event, threadIdx: idx, turnIdx: turnIdx)
            }
            self.runnerState = finalState
            if idx < self.liveThreads.count {
                if self.liveThreads[idx].harnessThreadId == nil,
                   case .running(let hid) = finalState, let hid {
                    self.liveThreads[idx].harnessThreadId = hid
                } else if let activeTid = newRunner.activeThreadIdSnapshot,
                          self.liveThreads[idx].harnessThreadId == nil {
                    self.liveThreads[idx].harnessThreadId = activeTid
                }
                self.liveThreads[idx].updatedAt = Date()
                self.threads.save(self.liveThreads[idx])
            }
            if idx < self.liveThreads.count,
               turnIdx < self.liveThreads[idx].turns.count {
                var turn = self.liveThreads[idx].turns[turnIdx]
                if turn.status == .running || turn.status == .awaitingApproval {
                    switch finalState {
                    case .finished:
                        turn.status = .completed
                        turn.completedAt = Date()
                    case .failed(let msg):
                        turn.status = .failed
                        turn.completedAt = Date()
                        if !turn.items.contains(where: { if case .error = $0 { return true } else { return false } }) {
                            turn.items.append(.error(id: "e-" + UUID().uuidString, message: msg))
                        }
                    case .running, .idle: break
                    }
                    self.pendingApprovals.removeAll()
                    self.liveThreads[idx].turns[turnIdx] = turn
                    self.threads.save(self.liveThreads[idx])
                }
            }
        }
    }

    /// Build the JSON-RPC runner for the given project. Local
    /// projects get a `LocalHarnessTransport`; remote projects get
    /// a `RemoteSSHHarnessTransport` that spawns the harness on the
    /// remote host.
    private func makeRunner(for project: Project?) -> CodexHarnessClient {
        let apiKey: String
        do {
            apiKey = try Self.readApiKey()
        } catch {
            // Should never happen — `sendUserMessage` already
            // returned early if there was a setup error. If we
            // land here, build a local client with an empty key
            // and let it fail loudly.
            return CodexHarnessClient(transport: LocalHarnessTransport(
                harnessPath: Self.findHarness(),
                codexHome: TapgoConfig.codexHome,
                apiKey: ""
            ))
        }
        if let project, project.kind == .remote,
           let hostId = project.remoteHostId,
           let host = workspace.remoteHost(byId: hostId) {
            let sshPath = Self.findSSH()
            return CodexHarnessClient(transport: RemoteSSHHarnessTransport(
                sshPath: sshPath,
                host: host,
                remoteCodexHome: host.codexHomePath,
                apiKey: apiKey
            ))
        }
        return CodexHarnessClient(transport: LocalHarnessTransport(
            harnessPath: Self.findHarness(),
            codexHome: TapgoConfig.codexHome,
            apiKey: apiKey
        ))
    }

    /// Inject a small environment preamble for remote threads.
    /// The model sees the same `host` / `user` / `pwd` the user
    /// sees, and is explicitly told not to nest `ssh` again.
    static func composeEffectivePrompt(userPrompt: String, project: Project?) -> String {
        guard let project, project.kind == .remote,
              project.remoteHostId != nil else {
            return userPrompt
        }
        // The host alias is the second half of `displayPath`. We
        // deliberately keep this short — long system prompts eat
        // tokens.
        let display = project.displayPath
        return """
        [环境] 你正在远程主机上工作 (display path: \(display))。
        所有 `exec_command` 工具调用都会在远端实际执行,stdout/stderr/exitCode 就是远端真实结果。
        不要在远端 shell 里再 `ssh` 到当前主机,会失败。
        用户消息: \(userPrompt)
        """
    }

    func cancelActiveTurn() { runner?.cancel() }

    /// Resolve a pending approval. Forwards the decision to the harness
    /// and updates the in-chat approval item so the user sees the outcome.
    func respondToApproval(_ request: ApprovalRequest, approve: Bool) {
        runner?.respondToApproval(request, approve: approve)
        pendingApprovals.removeValue(forKey: request.id)
        setApprovalDecision(id: request.id, decide: approve ? .approved : .denied)
    }

    private func setApprovalDecision(id: String, decide: ApprovalRequest.Decision) {
        guard let threadId = activeThreadId,
              let idx = liveThreads.firstIndex(where: { $0.id == threadId }) else { return }
        for turnIdx in liveThreads[idx].turns.indices {
            var items = liveThreads[idx].turns[turnIdx].items
            for i in items.indices {
                if case .approval(var ar) = items[i], ar.id == id {
                    ar.decision = decide
                    items[i] = .approval(ar)
                    liveThreads[idx].turns[turnIdx].items = items
                    threads.save(liveThreads[idx])
                    return
                }
            }
        }
    }

    private var isRunning: Bool {
        if case .running = runnerState { return true }
        return false
    }

    // MARK: - Event application

    private func handle(event: ExecEvent, threadIdx: Int, turnIdx: Int) {
        guard threadIdx < liveThreads.count,
              turnIdx < liveThreads[threadIdx].turns.count else { return }
        var turn = liveThreads[threadIdx].turns[turnIdx]

        switch event {
        case .threadStarted(let id):
            updateThreadHarness(threadId: liveThreads[threadIdx].id, harnessThreadId: id)
        case .turnStarted:
            turn.status = .running
        case .turnCompleted(let status, let errorMessage, let usage):
            if status == "failed" {
                turn.status = .failed
                turn.completedAt = Date()
                if let msg = errorMessage,
                   !turn.items.contains(where: { if case .error = $0 { return true } else { return false } }) {
                    turn.items.append(.error(id: "e-" + UUID().uuidString, message: msg))
                }
            } else {
                turn.status = .completed
                turn.completedAt = Date()
            }
            if let usage { turn.usage = usage }
        case .tokenUsageUpdated(let usage):
            // Live context tick: keep the running turn's usage fresh so the
            // context meter updates mid-turn instead of only at completion.
            if turn.status == .running || turn.status == .awaitingApproval {
                turn.usage = usage
            }
        case .approvalRequested(let req):
            pendingApprovals[req.id] = req
            if turn.items.firstIndex(where: {
                if case .approval(let a) = $0 { return a.id == req.id }
                return false
            }) == nil {
                turn.items.append(.approval(req))
            }
            turn.status = .awaitingApproval
        case .agentMessageDelta(let id, let delta):
            appendToStreamingMessage(id: id, delta: delta, in: &turn) {
                .assistantMessage(id: $0, text: "")
            }
        case .agentMessage(let id, let text):
            replaceAssistantText(id: id, text: text, in: &turn)
        case .reasoningDelta(let id, let delta):
            appendToStreamingMessage(id: id, delta: delta, in: &turn) {
                .reasoning(id: $0, text: "")
            }
        case .reasoningSummaryDelta(let id, _ , let delta):
            // The condensed reasoning summary streams separately from the
            // raw `reasoning/textDelta` trace; we keep it in its own
            // disclosure.
            appendToStreamingMessage(id: id, delta: delta, in: &turn) {
                .reasoningSummary(id: $0, text: "")
            }
        case .reasoning(let id, let summary):
            // Keep the detailed streamed trace (collapsed behind the
            // disclosure) rather than throwing it away in favour of the
            // condensed summary. Only fall back to the summary when
            // nothing meaningful streamed.
            let hasStreamed = turn.items.contains {
                if case .reasoning(let rid, let text) = $0 {
                    return rid == id && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                return false
            }
            if !hasStreamed {
                replaceReasoningText(id: id, text: ReasoningMerge.finalizeText(streamed: "", summary: summary), in: &turn)
            }
        case .commandStarted(let id, let command, let cwd):
            // For remote threads, tag the cell with the SSH host
            // alias up front so the user sees "via SSH remotehost"
            // while the command is running. The harness is on the
            // remote host — the cell IS the remote result.
            let project = liveThreads[threadIdx].projectId.flatMap { workspace.project(byId: $0) }
            let sshAlias: String?
            if let project, project.kind == .remote,
               let hostId = project.remoteHostId,
               let host = workspace.remoteHost(byId: hostId) {
                sshAlias = host.alias
            } else {
                sshAlias = nil
            }
            let ce = CommandExecution(
                id: id, command: command, cwd: cwd, status: .running,
                stdout: "", stderr: "", exitCode: nil,
                startedAt: Date(), completedAt: nil,
                viaSSH: sshAlias
            )
            if turn.items.firstIndex(where: { $0.id == id }) == nil {
                turn.items.append(.commandExecution(ce))
            }
        case .commandOutput(let id, let output):
            if let i = turn.items.firstIndex(where: { $0.id == id }),
               case .commandExecution(var ce) = turn.items[i] {
                ce.stdout += output
                turn.items[i] = .commandExecution(ce)
            }
        case .commandCompleted(let id, let exitCode, let status):
            // E. Honor the *real* exit code. exit 255 / DNS failure /
            // anything non-zero must be a hard failure — not a
            // success. The harness stringifies "failed" / "completed"
            // / "declined" so we map those to the right `status`.
            if let i = turn.items.firstIndex(where: { $0.id == id }),
               case .commandExecution(var ce) = turn.items[i] {
                ce.exitCode = exitCode
                ce.completedAt = Date()
                switch status {
                case "completed", "succeeded":
                    ce.status = (exitCode == 0) ? .succeeded : .failed
                case "failed":
                    ce.status = .failed
                case "declined":
                    ce.status = .denied
                default:
                    ce.status = .running
                }
                turn.items[i] = .commandExecution(ce)
            } else if turn.items.firstIndex(where: { $0.id == id }) == nil {
                let ce = CommandExecution(
                    id: id, command: "", cwd: nil, status: .succeeded,
                    stdout: "", stderr: "", exitCode: exitCode,
                    startedAt: Date(), completedAt: Date()
                )
                turn.items.append(.commandExecution(ce))
            }
        case .fileChange(let id, let changes):
            for (i, op) in changes.enumerated() {
                let kind: FileChange.Kind
                switch op.kind.lowercased() {
                case "add", "create": kind = .create
                case "delete":        kind = .delete
                default:              kind = .update
                }
                let fc = FileChange(id: "\(id)-\(i)", kind: kind, path: op.path, diff: "", status: .applied)
                turn.items.append(.fileChange(fc))
            }
        case .mcpToolCallStarted(let id, let server, let tool, let arguments):
            let argsString = arguments.flatMap { value -> String? in
                if let data = try? JSONEncoder().encode(value),
                   let s = String(data: data, encoding: .utf8) { return s }
                return nil
            } ?? ""
            if turn.items.firstIndex(where: { $0.id == id }) == nil {
                let tc = ToolCall(id: id, name: "\(server).\(tool)", arguments: argsString, result: nil, status: .running)
                turn.items.append(.toolCall(tc))
            }
        case .mcpToolCallCompleted(let id, let status, let error, let resultSummary):
            if let i = turn.items.firstIndex(where: { $0.id == id }),
               case .toolCall(var tc) = turn.items[i] {
                switch status {
                case "completed": tc.status = .succeeded
                case "failed":    tc.status = .failed
                case "declined":  tc.status = .denied
                default:          tc.status = .succeeded
                }
                tc.result = resultSummary ?? error ?? status
                turn.items[i] = .toolCall(tc)
            }
        case .webSearch(let id, let query):
            let tc = ToolCall(id: id, name: "web_search", arguments: query ?? "", result: nil, status: .succeeded)
            turn.items.append(.toolCall(tc))
        case .error(let message):
            turn.items.append(.error(id: "e-" + UUID().uuidString, message: message))
        }

        liveThreads[threadIdx].turns[turnIdx] = turn
        liveThreads[threadIdx].updatedAt = Date()
        threads.save(liveThreads[threadIdx])
    }

    private func appendToStreamingMessage(
        id: String, delta: String, in turn: inout Turn,
        make: (String) -> TurnItem
    ) {
        if let i = turn.items.firstIndex(where: { $0.id == id }) {
            switch turn.items[i] {
            case .assistantMessage(let aid, let text):
                guard aid == id else { return }
                turn.items[i] = .assistantMessage(id: aid, text: text + delta)
            case .reasoning(let rid, let text):
                guard rid == id else { return }
                turn.items[i] = .reasoning(id: rid, text: text + delta)
            case .reasoningSummary(let rid, let text):
                guard rid == id else { return }
                turn.items[i] = .reasoningSummary(id: rid, text: text + delta)
            default:
                turn.items[i] = make(id)
            }
        } else {
            turn.items.append(make(id))
        }
    }
    private func replaceAssistantText(id: String, text: String, in turn: inout Turn) {
        if let i = turn.items.firstIndex(where: { $0.id == id }) {
            turn.items[i] = .assistantMessage(id: id, text: text)
        } else {
            turn.items.append(.assistantMessage(id: id, text: text))
        }
    }
    private func replaceReasoningText(id: String, text: String, in turn: inout Turn) {
        if let i = turn.items.firstIndex(where: { $0.id == id }) {
            turn.items[i] = .reasoning(id: id, text: text)
        } else {
            turn.items.append(.reasoning(id: id, text: text))
        }
    }

    // MARK: - Static helpers

    static func findHarness() -> String { RemoteCodexHomeSync.findHarness() }
    static func findSSH() -> String { RemoteCodexHomeSync.findSSH() }
    static func findSCP() -> String { RemoteCodexHomeSync.findSCP() }

    static func readApiKey() throws -> String {
        let url = TapgoConfig.authPath
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["OPENAI_API_KEY"] as? String,
              !key.isEmpty
        else {
            throw SetupError.missingAuth(url.path)
        }
        return key
    }
}
