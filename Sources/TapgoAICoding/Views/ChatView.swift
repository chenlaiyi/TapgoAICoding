import SwiftUI
import TapgoCore
import UniformTypeIdentifiers

/// Compact token/byte formatter shared by ChatView and ComposerView:
/// "1.2M" / "12.3k" / "123".
fileprivate func tapgoFormatCount(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.0fk", Double(n) / 1_000) }
    return "\(n)"
}

/// Codex-style operation-permission tiers shown in the composer's single
/// selector. Each tier maps to a (sandbox, approval) pair so choosing one
/// keeps the two settings in sync and understandable.
private struct PermissionChoice: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let sandbox: String
    let approval: String

    static let all: [PermissionChoice] = [
        .init(id: "ask", title: "请求批准",
              detail: "编辑外部文件和使用互联网时始终询问",
              icon: "hand.raised",
              sandbox: TapgoConfig.SandboxMode.readOnly.rawValue,
              approval: TapgoConfig.ApprovalPolicy.onRequest.rawValue),
        .init(id: "smart", title: "帮我批准",
              detail: "仅对检测到的风险操作请求批准",
              icon: "checkmark.seal",
              sandbox: TapgoConfig.SandboxMode.workspaceWrite.rawValue,
              approval: TapgoConfig.ApprovalPolicy.onFailure.rawValue),
        .init(id: "full", title: "完全访问权限",
              detail: "可不受限制地访问互联网和你电脑上的任何文件",
              icon: "exclamationmark.shield",
              sandbox: TapgoConfig.SandboxMode.dangerFullAccess.rawValue,
              approval: TapgoConfig.ApprovalPolicy.never.rawValue),
    ]

    static let full = all.last!

    func matches(sandboxRaw: String, approvalRaw: String) -> Bool {
        sandboxRaw == sandbox && approvalRaw == approval
    }
}

/// Reports the rendered content's bottom edge (in the scroll coordinate
/// space) so the chat can tell whether the user is at the latest message.
private struct ChatContentBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

struct ChatView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var workspace: WorkspaceStore
    @State private var renamingCurrentId: String?
    @State private var renameDraft = ""
    @State private var isNearBottom = true
    @State private var lastWasNearBottom = true
    @State private var showNewMessage = false
    @State private var viewportHeight: CGFloat = 0
    @State private var searchActive = false
    @State private var searchQuery = ""
    @State private var jumpToTurnId: String? = nil
    @AppStorage("tapgo.wideContent") private var wideContent = false
    @AppStorage("tapgo.fontScale") private var fontScale = "medium"
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let thread = activeThread, hasConversation {
                    threadBody(thread: thread)
                } else {
                    emptyStateBody
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The composer only docks at the bottom once a conversation has
            // content; in the empty / initial state it is centered in the body.
            if hasConversation {
                Divider()
                ComposerView(contentWidth: wideContent ? 1280 : 1000)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSHTheme.bg)
        .navigationTitle(currentTitle)
        .navigationSubtitle(currentSubtitle)
        .alert("重命名会话", isPresented: Binding(
            get: { renamingCurrentId != nil },
            set: { if !$0 { renamingCurrentId = nil } }
        )) {
            TextField("标题", text: $renameDraft)
            Button("确定") {
                if let id = renamingCurrentId { store.renameThread(id, to: renameDraft) }
                renamingCurrentId = nil
            }
            Button("取消", role: .cancel) { renamingCurrentId = nil }
        } message: {
            Text("为这个会话起一个新标题。")
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapgoCopyConversation)) { _ in
            if let id = store.activeThreadId,
               let t = store.liveThreads.first(where: { $0.id == id }) {
                copyConversation(t)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapgoFindInConversation)) { _ in
            searchActive = true
            searchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapgoOpenActiveProject)) { _ in
            if let project = workspace.state.activeProject {
                NSWorkspace.shared.open(project.worktreeRoot)
            }
        }
    }

    /// In-chat search bar (⌘⇧F): filter turns to those matching the query.
    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("在对话中查找…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.caption)
                .focused($searchFieldFocused)
                .onExitCommand { searchActive = false; searchQuery = "" }
            Text(matchCount)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button {
                jumpToMatch(-1)
            } label: {
                Image(systemName: "chevron.up")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(matchingTurnIds.isEmpty)
            .help("上一个匹配")
            .accessibilityLabel("上一个匹配")
            Button {
                jumpToMatch(1)
            } label: {
                Image(systemName: "chevron.down")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(matchingTurnIds.isEmpty)
            .help("下一个匹配")
            .accessibilityLabel("下一个匹配")
            Button {
                searchActive = false
                searchQuery = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("关闭查找")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: DSHTheme.radiusPill))
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var matchCount: String {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return "\(threadTurnCount) 回合" }
        let n = store.liveThreads
            .first(where: { $0.id == store.activeThreadId })?
            .turns.filter { turnMatches($0, q) }.count ?? 0
        return "\(n) 个匹配"
    }

    private var threadTurnCount: Int {
        store.liveThreads.first(where: { $0.id == store.activeThreadId })?.turns.count ?? 0
    }

    private var searchFilterActive: Bool {
        searchActive && !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var matchingTurnIds: [String] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty,
              let thread = store.liveThreads.first(where: { $0.id == store.activeThreadId }) else { return [] }
        return thread.turns.filter { turnMatches($0, q) }.map(\.id)
    }

    private func jumpToMatch(_ delta: Int) {
        let ids = matchingTurnIds
        guard !ids.isEmpty else { return }
        let current = jumpToTurnId ?? ids[0]
        let idx = ids.firstIndex(of: current) ?? 0
        let next = (idx + delta + ids.count) % ids.count
        jumpToTurnId = ids[next]
    }

    private func turnMatches(_ turn: Turn, _ q: String) -> Bool {
        if turn.userInput.lowercased().contains(q) { return true }
        return turn.items.contains { item in
            let text: String
            switch item {
            case .userMessage(_, let t): text = t
            case .assistantMessage(_, let t): text = t
            case .reasoning(_, let t): text = t
            case .reasoningSummary(_, let t): text = t
            case .commandExecution(let ce): text = ce.stdout + " " + ce.command
            case .toolCall(let tc): text = tc.name + " " + tc.arguments + " " + (tc.result ?? "")
            case .fileChange(let fc): text = fc.path + " " + fc.diff
            default: text = ""
            }
            return text.lowercased().contains(q)
        }
    }

    /// Window / conversation title — follows the active thread's title so
    /// the middle column no longer reads as a static app name.
    private var currentTitle: String {
        if let id = store.activeThreadId,
           let t = store.liveThreads.first(where: { $0.id == id }) {
            if let project = t.projectId.flatMap({ workspace.project(byId: $0) }) {
                return "\(t.title) — \(project.displayName)"
            }
            return t.title
        }
        return "Tapgo AICoding"
    }

    /// The currently selected thread, if any.
    private var activeThread: TapgoCore.Thread? {
        store.activeThreadId.flatMap { id in store.liveThreads.first(where: { $0.id == id }) }
    }

    /// True once there's an active thread that already has content, so the
    /// full conversation layout (messages + docked composer) is shown.
    private var hasConversation: Bool {
        activeThread?.turns.isEmpty == false
    }

    /// Window subtitle: the active project's path (or remote endpoint), so
    /// the titlebar always shows which workspace the conversation is in.
    private var currentSubtitle: String {
        if let id = store.activeThreadId,
           let t = store.liveThreads.first(where: { $0.id == id }),
           let project = t.projectId.flatMap({ workspace.project(byId: $0) }) {
            return project.isRemote ? project.displayName : project.displayPath
        }
        return "独立会话"
    }

    @ViewBuilder
    private var emptyStateBody: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("我们该处理什么工作？")
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
            ComposerView(contentWidth: 1000)
                .padding(.horizontal, 16)
            Text("从左侧选择会话继续，或直接输入开始新任务。")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Session-goal banner set via `/goal`, shown above the conversation.
    @ViewBuilder
    private func goalBanner(thread: TapgoCore.Thread) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "scope")
                .foregroundStyle(DSHTheme.brand)
            VStack(alignment: .leading, spacing: 2) {
                Text("目标")
                    .font(.caption)
                    .foregroundStyle(DSHTheme.brand)
                Text(thread.goal ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            Spacer()
            Button {
                store.setActiveThreadGoal(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .help("清除目标")
            .accessibilityLabel("清除目标")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DSHTheme.surface)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private func threadBody(thread: TapgoCore.Thread) -> some View {
        VStack(spacing: 0) {
            threadHeader(thread: thread)
            Divider()
            if thread.goal != nil {
                goalBanner(thread: thread)
            }
            if searchActive {
                searchBar
            }
            if let project = thread.projectId.flatMap({ workspace.project(byId: $0) }),
               project.isRemote {
                RemoteBanner(project: project, host: workspace.remoteHost(byId: project.remoteHostId ?? ""))
            }
            if let usage = thread.turns.last(where: { $0.usage != nil })?.usage,
               usage.contextLevel == .critical {
                ContextWarningBanner(percent: usage.contextPercent ?? 0)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        // The thread title now lives in the window title
                        // (`.navigationTitle`), so the chat body starts
                        // directly with the turns — no duplicate header.
                        Color.clear.frame(height: 1).id("TOP")
                        ForEach(Array(thread.turns.enumerated()), id: \.element.id) { idx, turn in
                            let isMatch = !searchFilterActive || turnMatches(turn, searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                            if TapgoCore.Thread.showDateBanner(at: idx, in: thread.turns) {
                                dateDivider(for: turn.startedAt)
                            }
                            turnSection(turn: turn, isLast: turn.id == thread.turns.last?.id)
                                .id(turn.id)
                                .opacity(isMatch ? 1 : 0.35)
                        }
                        Color.clear.frame(height: 1).id("BOTTOM")
                    }
                    .padding(16)
                    .frame(maxWidth: wideContent ? 1280 : 1000, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(GeometryReader { g in
                        Color.clear.preference(
                            key: ChatContentBottomKey.self,
                            value: g.frame(in: .named("chat")).maxY
                        )
                    })
                }
                .coordinateSpace(name: "chat")
                .dynamicTypeSize(chatDynamicType)
                .onReceive(NotificationCenter.default.publisher(for: .tapgoJumpToTurn)) { note in
                    if let id = note.object as? String {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
                }
                .onPreferenceChange(ChatContentBottomKey.self) { bottom in
                    isNearBottom = bottom <= viewportHeight + 120
                }
                .overlay(alignment: .bottomTrailing) {
                    GeometryReader { g in
                        Color.clear
                            .onAppear { viewportHeight = g.size.height }
                            .onChange(of: g.size.height) { _, newValue in viewportHeight = newValue }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    VStack(alignment: .trailing, spacing: 6) {
                        if !isNearBottom {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo("TOP", anchor: .top)
                                }
                            } label: {
                                Label("回到顶部", systemImage: "arrow.up")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("回到顶部")
                        }
                        if showNewMessage {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo("BOTTOM", anchor: .bottom)
                                }
                                showNewMessage = false
                            } label: {
                                Label("回到最新", systemImage: "arrow.down")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("回到最新")
                        }
                    }
                    .padding(10)
                }
                // Follow the stream: when at the bottom, keep it pinned;
                // when scrolled up, offer the "回到最新" chip instead of
                // yanking the view. Uses the previous "at bottom" reading so
                // content growth during streaming doesn't immediately flip it.
                .onChange(of: thread.turns) { _, newTurns in
                    if lastWasNearBottom || isNearBottom {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("BOTTOM", anchor: .bottom)
                        }
                        showNewMessage = false
                    } else if !newTurns.isEmpty {
                        showNewMessage = true
                    }
                    lastWasNearBottom = isNearBottom
                }
                // When the user manually scrolls back to the bottom, drop the
                // "回到最新" chip instead of leaving it over the latest message.
                .onChange(of: isNearBottom) { _, near in
                    if near { showNewMessage = false }
                }
                // When switching threads, land at the latest message.
                .onChange(of: thread.id) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("BOTTOM", anchor: .bottom)
                    }
                    showNewMessage = false
                }
                // Jump to a search match.
                .onChange(of: jumpToTurnId) { _, id in
                    if let id = id {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                        jumpToTurnId = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func threadHeader(thread: TapgoCore.Thread) -> some View {        // Codex-style compact top bar: project + (optional) cwd
        // path on the left, status + interrupt on the right. The
        // thread title moves into the chat body as the first line
        // so it doesn't compete for header real estate.
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 6) {
                if let project = thread.projectId.flatMap({ workspace.project(byId: $0) }) {
                    HStack(spacing: 4) {
                        Image(systemName: project.isRemote ? "globe" : "folder.fill")
                            .font(.caption)
                            .foregroundStyle(project.isRemote ? .blue : .accentColor)
                        Text(project.displayName)
                            .font(.subheadline).bold()
                    }
                }
            }
            Spacer()
            if thread.usageTotal > 0 || thread.durationTotalText != nil {
                HStack(spacing: 4) {
                    if thread.usageTotal > 0 {
                        Text(TokenUsage.summary(of: thread.usageTotal))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let d = thread.durationTotalText {
                        Text(d)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            contextIndicator(thread: thread)
            statusPill(thread: thread)
            Button {
                renamingCurrentId = thread.id
                renameDraft = thread.title
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("重命名会话")
            .accessibilityLabel("重命名会话")
            if let proj = thread.projectId.flatMap({ workspace.project(byId: $0) }), !proj.isRemote {
                Button {
                    openInTerminal(proj.worktreeRoot.path)
                } label: {
                    Image(systemName: "terminal").font(.caption)
                }
                .buttonStyle(.borderless)
                .help("在终端中打开项目")
                .accessibilityLabel("在终端中打开项目")
                Button {
                    NSWorkspace.shared.open(proj.worktreeRoot)
                } label: {
                    Image(systemName: "folder").font(.caption)
                }
                .buttonStyle(.borderless)
                .help("在访达中显示项目")
                .accessibilityLabel("在访达中显示项目")
            }
            Menu {
                Button {
                    NSWorkspace.shared.open(TapgoConfig.logFileURL)
                } label: {
                    Label("打开运行日志", systemImage: "doc.text.magnifyingglass")
                }
                Button {
                    wideContent.toggle()
                } label: {
                    if wideContent {
                        Label("内容宽度: 宽 (标准)", systemImage: "checkmark")
                    } else {
                        Label("内容宽度: 标准 (宽)", systemImage: "arrow.up.left.and.arrow.down.right.square")
                    }
                }
                Menu {
                    ForEach(["small", "medium", "large"], id: \.self) { s in
                        Button { fontScale = s } label: {
                            if s == fontScale {
                                Label(fontLabel(s), systemImage: "checkmark")
                            } else {
                                Text(fontLabel(s))
                            }
                        }
                    }
                } label: {
                    Label("字体大小", systemImage: "textformat.size")
                }
                if !thread.turns.isEmpty {
                    Divider()
                    Button {
                        copyToPasteboard(thread.title)
                    } label: {
                        Label("复制标题", systemImage: "doc.on.doc")
                    }
                    Button {
                        copyConversation(thread)
                    } label: {
                        Label("复制为 Markdown", systemImage: "doc.on.doc")
                    }
                    Button {
                        copyConversationAsText(thread)
                    } label: {
                        Label("复制为纯文本", systemImage: "text.alignleft")
                    }
                    Button {
                        saveConversation(thread)
                    } label: {
                        Label("导出为 .md 文件…", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        saveConversationAsText(thread)
                    } label: {
                        Label("导出为 .txt 文件…", systemImage: "square.and.arrow.down")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .help("更多操作")
            .accessibilityLabel("更多操作")
            if let last = thread.turns.last, last.status == .running {
                Button {
                    store.cancelActiveTurn()
                } label: {
                    Label(L10n.interrupt, systemImage: "stop.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help(L10n.interrupt)
                .accessibilityLabel("中断当前任务")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Compact "context used" indicator from the most recent turn that
    /// reported usage. Mirrors Codex's context meter so the user can see
    /// how much of the window is being consumed.
    @ViewBuilder
    private func contextIndicator(thread: TapgoCore.Thread) -> some View {        // The most recent completed turn with reported usage.
        if let usage = thread.turns.last(where: { $0.usage != nil })?.usage,
           let pct = usage.contextPercent {
            let color = Self.contextColor(usage.contextLevel)
            HStack(spacing: 5) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.gray.opacity(0.15))
                        .frame(width: 44, height: 4)
                    Capsule()
                        .fill(color)
                        .frame(width: 44 * CGFloat(pct) / 100, height: 4)
                }
                Text("上下文 \(pct)%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if usage.total > 0, let cw = usage.contextWindow, cw > 0 {
                    Text("\(tapgoFormatCount(usage.total)) / \(tapgoFormatCount(cw))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .help("上下文已用 \(pct)%")
            .accessibilityLabel("上下文已用 \(pct)%")
        }
    }

    private static func contextColor(_ level: TapgoCore.ContextLevel?) -> Color {
        switch level {
        case .critical: return .red
        case .warn: return .orange
        case .normal: return .green
        case .none: return .secondary
        }
    }

    private func copyConversation(_ thread: TapgoCore.Thread) {
        let md = thread.turns.map { TurnMarkdown.render($0) }.joined(separator: "\n\n---\n\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(md, forType: .string)
    }

    /// Open Terminal at the given directory.
    private func openInTerminal(_ path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Terminal", path]
        try? p.run()
    }

    /// Copy the conversation as plain text (user prompts + replies stripped
    /// of markdown), for pasting into a plain-text context.
    private func copyConversationAsText(_ thread: TapgoCore.Thread) {
        var parts: [String] = []
        for turn in thread.turns {
            for item in turn.items {
                switch item {
                case .userMessage(_, let t):
                    parts.append("用户: " + t.trimmingCharacters(in: .whitespacesAndNewlines))
                case .assistantMessage(_, let t):
                    parts.append("助手: " + t.trimmingCharacters(in: .whitespacesAndNewlines))
                case .reasoning(_, let t):
                    if !t.isEmpty { parts.append("思考: " + t.trimmingCharacters(in: .whitespacesAndNewlines)) }
                default:
                    break
                }
            }
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(parts.joined(separator: "\n\n"), forType: .string)
    }

    private func copyToPasteboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    private func saveConversation(_ thread: TapgoCore.Thread) {
        let md = thread.turns.map { TurnMarkdown.render($0) }.joined(separator: "\n\n---\n\n")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(thread.title).md"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? md.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func saveConversationAsText(_ thread: TapgoCore.Thread) {
        var parts: [String] = []
        for turn in thread.turns {
            for item in turn.items {
                switch item {
                case .userMessage(_, let t):
                    parts.append("用户: " + t.trimmingCharacters(in: .whitespacesAndNewlines))
                case .assistantMessage(_, let t):
                    parts.append("助手: " + t.trimmingCharacters(in: .whitespacesAndNewlines))
                case .reasoning(_, let t):
                    if !t.isEmpty { parts.append("思考: " + t.trimmingCharacters(in: .whitespacesAndNewlines)) }
                default:
                    break
                }
            }
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(thread.title).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? parts.joined(separator: "\n\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Small colored pill that summarises the most recent turn's
    /// status. Mirrors the dot in the sidebar row but adds a word
    /// (执行中 / 已完成 / 失败 / etc.) so the user doesn't have to
    /// hover the chat header to know what's happening.
    @ViewBuilder
    private func statusPill(thread: TapgoCore.Thread) -> some View {
        let last = thread.turns.last
        let status = last?.status
        let (label, color, icon): (String, Color, String) = {
            switch status {
            case .running: return ("执行中", DSHTheme.brand, "circle.dotted")
            case .completed: return ("已完成", DSHTheme.success, "checkmark.circle.fill")
            case .failed: return ("失败", DSHTheme.error, "exclamationmark.triangle.fill")
            case .awaitingApproval: return ("等待批准", DSHTheme.warn, "hand.raised.fill")
            case .interrupted: return ("中断", DSHTheme.warn, "pause.circle.fill")
            case .pending: return ("待处理", .secondary, "ellipsis.circle")
            case .none: return ("就绪", .secondary, "circle")
            }
        }()
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(label).font(.caption2)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
        .accessibilityLabel("会话状态 \(label)")
    }

    /// Groups consecutive file-change items into one Codex-style "已编辑
    /// N 个文件" batch block; everything else renders one row per item.
    private func chatBlocks(_ items: [TurnItem]) -> [ChatBlock] {
        var out: [ChatBlock] = []
        var fileAcc: [FileChange] = []
        func flush() {
            if !fileAcc.isEmpty { out.append(.fileBatch(fileAcc)); fileAcc = [] }
        }
        for item in items {
            if case .fileChange(let fc) = item {
                fileAcc.append(fc)
            } else {
                flush()
                out.append(.item(item))
            }
        }
        flush()
        return out
    }

    /// Compact "HH:mm" timestamp for a turn, used in the per-turn footer.
    private func turnTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// A centered date banner for the first turn of each new day, styled
    /// like Codex's "今天 / 昨天 / 2026年3月1日" separators.
    private func dateDivider(for date: Date) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(DSHTheme.border).frame(height: 1)
            Text(dateLabel(date))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Rectangle().fill(DSHTheme.border).frame(height: 1)
        }
        .padding(.vertical, 6)
    }

    private func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }

    private func fontLabel(_ s: String) -> String {
        switch s {
        case "small": return "小"
        case "large": return "大"
        default: return "中"
        }
    }

    private var chatDynamicType: DynamicTypeSize {
        switch fontScale {
        case "small": return .medium
        case "large": return .xxLarge
        default: return .xLarge
        }
    }

    /// Live activity label for the in-flight indicator, mirroring Codex:
    /// "思考中" while reasoning, "执行中" while a tool/command runs, and
    /// "生成中" once the model is streaming its reply.
    private func streamingLabel(for turn: TapgoCore.Turn) -> String {
        guard let last = turn.items.last else { return "思考中" }
        switch last {
        case .reasoning, .reasoningSummary: return "思考中"
        case .commandExecution, .toolCall: return "执行中"
        case .assistantMessage: return "生成中"
        default: return "处理中"
        }
    }

    /// One renderable unit in a turn: either a single item or a merged
    /// batch of consecutive file changes.
    private enum ChatBlock: Identifiable {
        case item(TurnItem)
        case fileBatch([FileChange])

        var id: String {
            switch self {
            case .item(let it): return "item-" + it.id
            case .fileBatch(let files): return "batch-" + (files.first?.id ?? "e")
            }
        }
    }

    @ViewBuilder
    private func turnSection(turn: Turn, isLast: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if turn.status == .running {
                // Show the user's question immediately, then ONE compact
                // activity line that cycles through thinking / commands.
                ForEach(Array(userMessageItems(turn)), id: \.id) { userItem in
                    MessageRow(item: userItem, isRunning: false,
                               startedAt: turn.startedAt,
                               onReply: userReplyClosure(userItem),
                               onEdit: { store.sendUserMessage($0) })
                }
                runningActivityLine(turn: turn)
            } else {
                ForEach(chatBlocks(turn.items)) { block in
                    switch block {
                    case .item(let item):
                        MessageRow(item: item, isRunning: false,
                                   startedAt: turn.startedAt,
                                   onReply: userReplyClosure(item),
                                   onEdit: { store.sendUserMessage($0) })
                    case .fileBatch(let files):
                        FileEditBatchView(files: files)
                    }
                }
            }
            if turn.status == .completed || turn.status == .failed || turn.status == .interrupted {
                // Single-line footer: metadata + copy + feedback / actions.
                HStack(spacing: 8) {
                    if let usage = turn.usage {
                        HStack(spacing: 5) {
                            Image(systemName: "number")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(turnTime(turn.startedAt) + " · " + usage.summary + (turn.durationText.map { " · \($0)" } ?? ""))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        CopyIconButton(text: TurnMarkdown.render(turn), help: "复制本回合")
                            .controlSize(.mini)
                    }
                    if isLast, turn.status == .completed {
                        Button {
                            store.setTurnFeedback(turn.id, 1)
                        } label: {
                            Image(systemName: store.turnFeedback[turn.id] == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.caption)
                                .foregroundStyle(store.turnFeedback[turn.id] == 1 ? DSHTheme.brand : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("有帮助")
                        .accessibilityLabel("有帮助")
                        Button {
                            store.setTurnFeedback(turn.id, -1)
                        } label: {
                            Image(systemName: store.turnFeedback[turn.id] == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                .font(.caption)
                                .foregroundStyle(store.turnFeedback[turn.id] == -1 ? DSHTheme.error : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("没有帮助")
                        .accessibilityLabel("没有帮助")
                        if !turn.userInput.isEmpty {
                            Button {
                                store.newThread()
                                store.sendUserMessage(turn.userInput)
                            } label: {
                                Label("以此输入开新任务", systemImage: "plus.message")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("用这条用户的输入新建一个会话")
                            .accessibilityLabel("以此输入开新任务")
                        }
                    }
                    if isLast, (turn.status == .failed || turn.status == .interrupted), !turn.userInput.isEmpty {
                        Button {
                            store.sendUserMessage(turn.userInput)
                        } label: {
                            Label("重试", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(DSHTheme.brand)
                        .help("重试本回合")
                        .accessibilityLabel("重试本回合")
                    }
                    Spacer()
                }
                .padding(.leading, 8)
            }
        }
    }

    /// While a turn runs, render a single compact activity line (thinking /
    /// command / generating) that updates live, with one stop button.
    @ViewBuilder
    private func runningActivityLine(turn: Turn) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.horizontal.circle")
                .foregroundStyle(DSHTheme.brand)
            Text(runningActivityLabel(turn))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(runningActivityLabel(turn))
            Spacer(minLength: 0)
            ProgressView().controlSize(.mini)
            Button {
                store.cancelActiveTurn()
            } label: {
                Label("停止", systemImage: "stop.fill")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("中断当前任务")
            .accessibilityLabel("中断当前任务")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DSHTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: DSHTheme.radiusCard).stroke(DSHTheme.border, lineWidth: 1))
    }

    private func runningActivityLabel(_ turn: Turn) -> String {
        guard let last = turn.items.last else { return "思考中…" }
        switch last {
        case .reasoning(_, let t): return t.isEmpty ? "思考中…" : "思考 · \(t)"
        case .reasoningSummary(_, let t): return t.isEmpty ? "思考中…" : "思考 · \(t)"
        case .commandExecution(let ce): return "Bash · \(ce.command)"
        case .toolCall(let tc): return "工具 · \(tc.name)"
        case .assistantMessage(_, let t): return t.isEmpty ? "生成中…" : "生成 · \(t)"
        default: return "处理中…"
        }
    }

    /// The user's own messages in a turn (the question), which stay visible
    /// immediately after sending — even while the turn is still running.
    private func userMessageItems(_ turn: Turn) -> [TurnItem] {
        turn.items.filter { if case .userMessage = $0 { return true }; return false }
    }

    /// Build a "重发" closure for a user-message item, or nil for any other
    /// item type (so only the user's question gets the reply action).
    private func userReplyClosure(_ item: TurnItem) -> (() -> Void)? {
        guard case .userMessage(_, let text) = item else { return nil }
        return { store.sendUserMessage(text) }
    }
}

/// Warns when the active thread's context window is nearly full, nudging
/// the user to start a fresh thread instead of letting the harness
/// silently compact. Mirrors Codex's context meter.
private struct ContextWarningBanner: View {
    let percent: Int
    @EnvironmentObject var store: SessionStore
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("上下文已用 \(percent)% — 建议新建会话以留出空间")
                .font(.caption)
            Spacer(minLength: 8)
            Button {
                store.newThread()
            } label: {
                Label("新建会话", systemImage: "plus.message")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(DSHTheme.warn)
            .help("新建一个会话以留出上下文空间")
            .accessibilityLabel("新建会话")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSHTheme.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: DSHTheme.radiusCard).stroke(DSHTheme.warn.opacity(0.3), lineWidth: 1))
        .foregroundStyle(DSHTheme.warn)
    }
}

/// Animated "typing" dots shown while a turn is streaming. Replaces the
/// plain spinner so the chat reads like Codex while the model generates.
private struct StreamingIndicator: View {
    var label: String = "生成中"
    var startedAt: Date = Date()
    @State private var blinking = false
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var elapsedText: String {
        let d = max(now.timeIntervalSince(startedAt), 0)
        return DurationFormatter.string(seconds: d)
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(elapsedText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Text("▍")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .opacity(blinking ? 1 : 0.2)
        }
        .onAppear {
            now = Date()
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                blinking = true
            }
        }
        .onReceive(timer) { _ in
            now = Date()
        }
        .accessibilityLabel("\(label), 已用 \(elapsedText)")
    }
}

private struct RemoteBanner: View {
    let project: Project
    let host: RemoteHost?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe.americas.fill").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.remoteBanner)
                    .font(.subheadline).bold()
                Text(L10n.remoteBannerHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if let host = host {
                Button {
                    let cmd = "ssh \(host.user)@\(host.host)"
                    NSWorkspace.shared.open(URL(string: "ssh://" + cmd) ?? URL(fileURLWithPath: "/"))
                } label: {
                    Label(L10n.openInTerminal, systemImage: "terminal")
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(DSHTheme.brand.opacity(0.08))
        .accessibilityElement(children: .combine)
    }
}

struct ComposerView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var workspace: WorkspaceStore
    var contentWidth: CGFloat = 760
    @AppStorage("tapgo.composerDraft") private var text: String = ""
    @FocusState private var focused: Bool
    @State private var isDropTargeted = false
    @State private var editorExpanded = false
    @State private var showAttachments = true
    @State private var showSlashMenu = false
    @State private var queueExpanded = false
    @AppStorage(TapgoConfig.sandboxKey) private var sandboxRaw = TapgoConfig.SandboxMode.dangerFullAccess.rawValue
    @AppStorage(TapgoConfig.approvalPolicyKey) private var approvalPolicyRaw = TapgoConfig.ApprovalPolicy.never.rawValue
    @AppStorage(TapgoConfig.reasoningEffortKey) private var reasoningEffort = ""

    var body: some View {
        VStack(spacing: 8) {
            if !store.attachedImages.isEmpty {
                if showAttachments {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(store.attachedImages, id: \.self) { url in
                                ZStack(alignment: .topTrailing) {
                                    thumbnail(for: url)
                                    Button { store.removeImage(url) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .buttonStyle(.borderless)
                                    .offset(x: 5, y: -5)
                                    .help("移除")
                                    .accessibilityLabel("移除图片 \(url.lastPathComponent)")
                                }
                                .help(url.lastPathComponent)
                                .contextMenu {
                                    Button {
                                        copyGlobal(url.path)
                                    } label: {
                                        Label("复制路径", systemImage: "doc.on.doc")
                                    }
                                    Button {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    } label: {
                                        Label("在访达中显示", systemImage: "folder")
                                    }
                                }
                            }
                            Button {
                                store.clearImages()
                            } label: {
                                Label("清空", systemImage: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("清空已添加的图片")
                            .accessibilityLabel("清空已添加的图片")
                        }.padding(.horizontal, 4)
                    }
                    .frame(height: 46)
                } else {
                    HStack(spacing: 6) {
                        Text("已添加 \(store.attachedImages.count) 张图片")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            showAttachments = true
                        } label: {
                            Label("展开", systemImage: "chevron.down")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                        Button {
                            store.clearImages()
                        } label: {
                            Label("清空", systemImage: "trash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }

            queueStatusBar

            // Centered, max-width rounded dock (mirrors the DSH composer
            // 'composer-card-max-width'). The input and its controls live
            // inside one raised card.
            VStack(spacing: 8) {
            GrowingTextEditor(
                    text: $text,
                    placeholder: composerPlaceholder,
                    maxHeight: editorExpanded ? 320 : 150,
                    focused: $focused,
                    onSubmit: send
                )
                .popover(isPresented: $showSlashMenu, arrowEdge: .bottom) {
                    slashMenu
                }

                HStack(spacing: 8) {
                    // The "+" holds both image attachment and skill references.
                    Menu {
                        Button {
                            pickImages()
                        } label: {
                            Label("添加图片附件…", systemImage: "photo")
                        }
                        if !AgentCapabilities.skills.isEmpty {
                            Divider()
                            Menu {
                                ForEach(AgentCapabilities.skills) { item in
                                    Button {
                                        NotificationCenter.default.post(name: .tapgoInsertSkill, object: item.name)
                                    } label: {
                                        Label(item.name, systemImage: item.icon)
                                    }
                                }
                            } label: {
                                Label("插入技能", systemImage: "wrench.adjustable")
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .help("添加附件 / 插入技能")
                    .accessibilityLabel("添加附件或技能")

                    if let p = workspace.state.activeProject {
                        Menu {
                            Button {
                                NotificationCenter.default.post(name: .tapgoRequestOpenLocalFolder, object: nil)
                            } label: {
                                Label("更改工作目录…", systemImage: "arrow.triangle.branch")
                            }
                            Divider()
                            Button {
                                store.setActiveProject(nil)
                            } label: {
                                Label("无项目", systemImage: p.isRemote ? "questionmark.folder" : "folder")
                            }
                            ForEach(workspace.state.projects.sorted(by: { $0.lastUsedAt > $1.lastUsedAt })) { proj in
                                Button {
                                    store.setActiveProject(proj.id)
                                } label: {
                                    if proj.id == p.id {
                                        Label(proj.displayName, systemImage: "checkmark")
                                    } else {
                                        Label(proj.displayName, systemImage: proj.isRemote ? "globe" : "folder")
                                    }
                                }
                            }
                            if !p.isRemote {
                                Divider()
                                Button {
                                    NSWorkspace.shared.open(p.worktreeRoot)
                                } label: {
                                    Label("在访达中显示", systemImage: "folder")
                                }
                                Button {
                                    openInTerminal(p.worktreeRoot.path)
                                } label: {
                                    Label("在终端中打开", systemImage: "terminal")
                                }
                                Button {
                                    copyGlobal(p.displayPath)
                                } label: {
                                    Label("复制路径", systemImage: "doc.on.doc")
                                }
                                let agentsPath = p.worktreeRoot.appendingPathComponent("AGENTS.md")
                                let readmePath = p.worktreeRoot.appendingPathComponent("README.md")
                                if FileManager.default.fileExists(atPath: agentsPath.path) {
                                    Button {
                                        NSWorkspace.shared.open(agentsPath)
                                    } label: {
                                        Label("打开项目文档 (AGENTS.md)", systemImage: "doc.text")
                                    }
                                } else if FileManager.default.fileExists(atPath: readmePath.path) {
                                    Button {
                                        NSWorkspace.shared.open(readmePath)
                                    } label: {
                                        Label("打开项目文档 (README.md)", systemImage: "doc.text")
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: p.isRemote ? "globe" : "folder")
                                    .font(.caption)
                                    .foregroundStyle(p.isRemote ? .blue : .secondary)
                                Text(p.displayName).font(.caption).lineLimit(1)
                                if !p.isRemote {
                                    Text(p.displayPath)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(DSHTheme.surface, in: Capsule())
                            .help("\(p.displayName) · \(p.displayPath)")
                            .accessibilityLabel("当前项目 \(p.displayName), 路径 \(p.displayPath), 点击切换")
                        }
                        .menuStyle(.borderlessButton)
                    } else {
                        Menu {
                            Button {
                                NotificationCenter.default.post(name: .tapgoRequestOpenLocalFolder, object: nil)
                            } label: {
                                Label("添加本地目录…", systemImage: "folder.badge.plus")
                            }
                            Divider()
                            ForEach(workspace.state.projects.sorted(by: { $0.lastUsedAt > $1.lastUsedAt })) { proj in
                                Button {
                                    store.setActiveProject(proj.id)
                                } label: {
                                    Label(proj.displayName, systemImage: proj.isRemote ? "globe" : "folder")
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder").font(.caption).foregroundStyle(.secondary)
                                Text("选择项目").font(.caption)
                                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(DSHTheme.surface, in: Capsule())
                        }
                        .menuStyle(.borderlessButton)
                    }

                    environmentChip

                    Spacer()

                    Button {
                        editorExpanded.toggle()
                    } label: {
                        Image(systemName: editorExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                    .help(editorExpanded ? "收起输入框" : "展开输入框")
                    .accessibilityLabel(editorExpanded ? "收起输入框" : "展开输入框")

                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.attachedImages.isEmpty {
                        Button {
                            text = ""
                            store.clearImages()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.borderless)
                        .help("清空输入和附件 (⌘⌫)")
                        .accessibilityLabel("清空输入和附件")
                    }

                    Menu {
                        Button {
                            copyGlobal(store.modelName)
                        } label: {
                            Label("模型: \(store.modelName)", systemImage: "cpu")
                        }
                        Button {
                            copyGlobal(TapgoConfig.effectiveBaseURL)
                        } label: {
                            Label("端点: \(TapgoConfig.effectiveBaseURL)", systemImage: "network")
                        }
                        if let pct = composerContextPercent {
                            Button {} label: {
                                Label("上下文: \(pct)%", systemImage: "gauge.medium")
                            }
                            .disabled(true)
                        }
                        if let cw = store.liveThreads
                            .first(where: { $0.id == store.activeThreadId })?
                            .turns.last?.usage?.contextWindow {
                            Button {} label: {
                                Label("上下文上限: \(formatCount(cw))", systemImage: "rectangle.3.group")
                            }
                            .disabled(true)
                        }
                        Divider()
                        Menu {
                            ForEach(["", "none", "low", "medium", "high"], id: \.self) { e in
                                Button { reasoningEffort = e } label: {
                                    if e == reasoningEffort {
                                        Label(effortName(e), systemImage: "checkmark")
                                    } else {
                                        Text(effortName(e))
                                    }
                                }
                            }
                        } label: {
                            Label("思考深度: \(effortLabel)", systemImage: "brain")
                        }
                        let nearFull = (composerContextPercent ?? 0) >= 90
                        Divider()
                        Button {
                            store.newThread()
                        } label: {
                            if nearFull {
                                Label("新建会话（清空上下文）", systemImage: "arrow.clockwise.circle")
                            } else {
                                Label("新建会话（清空上下文）", systemImage: "plus.message")
                            }
                        }
                        .foregroundStyle(nearFull ? DSHTheme.warn : .primary)
                        Divider()
                        Button {
                            copyGlobal(runInfoText)
                        } label: {
                            Label("复制运行信息", systemImage: "doc.on.doc")
                        }
                        Button {
                            NotificationCenter.default.post(name: .tapgoRequestOpenSettings, object: nil)
                        } label: {
                            Label("打开运行设置…", systemImage: "gear")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu").font(.caption)
                            Text(store.modelName).font(.caption)
                            if isRunning {
                                ProgressView().controlSize(.mini)
                            }
                            if !effortLabel.isEmpty {
                                Text("· \(effortLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let pct = composerContextPercent {
                                HStack(spacing: 2) {
                                    if pct >= 90 {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                    }
                                    Text("\(pct)%")
                                        .font(.caption)
                                    if let counts = composerContextCounts {
                                        Text(counts)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .foregroundStyle(pct >= 90 ? DSHTheme.warn : .secondary)
                            }
                            Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(DSHTheme.brand)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(DSHTheme.brandSoft, in: Capsule())
                        .help(L10n.modelChipHint + modelContextTooltip)
                        .accessibilityLabel("模型 \(store.modelName), 来自独立配置")
                    }
                    .menuStyle(.borderlessButton)

                    if isRunning {
                        Button(action: { store.cancelActiveTurn() }) {
                            Label("停止", systemImage: "stop.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .help("中断当前任务（排队消息会被保留）")
                        .accessibilityLabel("中断当前任务")
                    }
                    Button(action: send) {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isRunning ? DSHTheme.warn : DSHTheme.brand)
                    .disabled(canSend == false)
                    .help(isRunning ? "发送（排队）(⌘↩)" : "发送 (⌘↩)")
                    .accessibilityLabel(L10n.sendButton)
                }
            }
            .padding(10)
            .background(DSHTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: DSHTheme.radiusCard)
                    .stroke(isDropTargeted ? DSHTheme.brand : (focused ? DSHTheme.brand : DSHTheme.border), lineWidth: isDropTargeted ? 2 : 1)
            )
            .frame(maxWidth: contentWidth)
            .frame(maxWidth: .infinity, alignment: .center)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
                acceptDroppedImages(providers)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
        .onReceive(NotificationCenter.default.publisher(for: .tapgoFocusComposer)) { _ in
            focused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapgoClearComposer)) { _ in
            text = ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapgoSendMessage)) { _ in
            send()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapgoInterjectAndFlush)) { _ in
            interjectSend()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapgoRetryTurn)) { _ in
            retryLastTurn()
        }
        .onChange(of: text) { _, newValue in
            // Show the slash-command menu while the user is typing a
            // `/command` prefix (no space yet).
            showSlashMenu = newValue.hasPrefix("/") && !newValue.contains(" ")
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapgoInsertSkill)) { note in
            if let name = note.object as? String {
                let ref = "@\(name)"
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    text = ref + " "
                } else {
                    text = text.trimmingCharacters(in: .whitespacesAndNewlines) + " " + ref + " "
                }
                focused = true
            }
        }
        .onChange(of: workspace.state.activeProjectId) { _, _ in
            // A draft typed for one project shouldn't be sent to another.
            text = ""
        }
        .onAppear {
            // On launch with a restored thread, put the cursor in the
            // composer so the user can start typing immediately.
            if store.activeThreadId != nil { focused = true }
        }
    }

    /// Resend the last turn's user input when it failed / was interrupted.
    private func retryLastTurn() {
        if store.isRunning { return }
        guard let id = store.activeThreadId,
              let t = store.liveThreads.first(where: { $0.id == id }),
              let last = t.turns.last,
              !last.userInput.isEmpty,
              last.status == .failed || last.status == .interrupted else { return }
        store.sendUserMessage(last.userInput)
    }

    /// Quick switch for the harness sandbox mode (persisted). Mirrors
    /// Codex's sandbox selector in the composer footer.
    @ViewBuilder
    /// One "运行环境" chip that bundles the sandbox mode and the approval
    /// policy (previously two separate chips), so the composer footer stays
    /// compact. Both are quick-switch menus persisted to settings.
    /// One permission selector with Codex's three clear tiers. Each tier
    /// sets both the sandbox mode and the approval policy together, keeping
    /// the composer footer to a single, understandable control.
    private var environmentChip: some View {
        Menu {
            ForEach(PermissionChoice.all) { c in
                Button {
                    sandboxRaw = c.sandbox
                    approvalPolicyRaw = c.approval
                } label: {
                    HStack {
                        Image(systemName: c.icon)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.title)
                            Text(c.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if c.matches(sandboxRaw: sandboxRaw, approvalRaw: approvalPolicyRaw) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(DSHTheme.brand)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: currentPermission.icon).font(.caption)
                Text(currentPermission.title).font(.caption)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(DSHTheme.surface, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .help("操作权限: \(currentPermission.title)")
        .accessibilityLabel("操作权限")
    }

    private var currentPermission: PermissionChoice {
        PermissionChoice.all.first { $0.matches(sandboxRaw: sandboxRaw, approvalRaw: approvalPolicyRaw) }
            ?? PermissionChoice.full
    }

    private var isRunning: Bool { store.isRunning }

    private var canSend: Bool {
        if store.setupError != nil { return false }
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = !store.attachedImages.isEmpty
        // Sending is always allowed when there is content — while a turn is
        // running the message is queued instead of dropped.
        return hasText || hasImage
    }

    /// Status strip above the composer mirroring the DSH "任务 进行中 · 待处理"
    /// queue affordance. Shown only when a turn is running or messages are
    /// awaiting send.
    @ViewBuilder
    private var queueStatusBar: some View {
        if isRunning || !store.queue.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: isRunning ? "arrow.triangle.2.circlepath" : "list.bullet")
                        .font(.caption)
                        .foregroundStyle(isRunning ? DSHTheme.brand : .secondary)
                    Text("任务 \(store.inProgressTasks) 进行中 · \(store.queue.count) 待处理")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(isRunning ? DSHTheme.brand : .secondary)
                    Spacer()
                    if !store.queue.isEmpty {
                        Button {
                            store.interjectAndFlush()
                        } label: {
                            Label("插话发送全部", systemImage: "bolt.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(DSHTheme.warn)
                        .keyboardShortcut(.return, modifiers: [.control])
                        .help("Ctrl+Enter 中断当前并立即发送全部排队消息")
                        .accessibilityLabel("插话发送全部排队消息")
                    }
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { queueExpanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(queueExpanded ? 180 : 0))
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.queue.isEmpty)
                    .help(store.queue.isEmpty ? "暂无排队消息" : (queueExpanded ? "收起排队列表" : "展开排队列表"))
                }

                if store.queue.isEmpty {
                    Text(isRunning ? "仍在生成中，可继续输入，消息会按顺序排在后面" : "等待下一条消息")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Cmd/Ctrl+Enter 插话发送全部排队消息")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if queueExpanded && !store.queue.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(store.queue) { q in
                            HStack(spacing: 6) {
                                Image(systemName: "text.bubble")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(q.text.isEmpty ? "(图片附件)" : q.text)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                if !q.images.isEmpty {
                                    Text("🖼 \(q.images.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    store.removeQueued(q.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.borderless)
                                .help("移除这条排队消息")
                                .accessibilityLabel("移除排队消息")
                            }
                        }
                        HStack {
                            Spacer()
                            Button("清空排队") { store.clearQueue() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(6)
                    .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(DSHTheme.border, lineWidth: 1))
            .frame(maxWidth: contentWidth)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// Send the composed message. While a turn is running the message is
    /// queued instead of dropped.
    private func send() {
        // Slash commands are intercepted before hitting the harness.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let goal = slashGoal(trimmed) {
            store.setActiveThreadGoal(goal)
            text = ""
            focused = true
            return
        }
        if trimmed == "/new" {
            store.newThread()
            text = ""
            showSlashMenu = false
            return
        }
        let t = text
        guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !store.attachedImages.isEmpty else { return }
        text = ""
        store.sendUserMessage(t)
        // Keep the composer focused so the user can type the next message
        // immediately, matching Codex's always-ready input.
        focused = true
    }

    /// "插话发送全部" (Cmd/Ctrl+Enter): append the current draft to the queue
    /// (or send it immediately if idle), then drain the whole queue.
    private func interjectSend() {
        let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !store.attachedImages.isEmpty
        guard hasContent || !store.queue.isEmpty else {
            // Nothing to send or interrupt.
            return
        }
        if hasContent {
            let t = text
            text = ""
            store.sendUserMessage(t)
        }
        store.interjectAndFlush()
        focused = true
    }

    /// Extract the goal text from a `/goal <text>` command, or nil.
    private func slashGoal(_ trimmed: String) -> String? {
        guard trimmed.hasPrefix("/goal") else { return nil }
        let rest = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : String(rest)
    }

    /// The "/" command popover shown while typing a slash command.
    private var slashMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("命令")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            slashRow("/goal", "设置会话目标") {
                text = "/goal "
                focused = true
            }
            slashRow("/new", "新建会话") {
                store.newThread()
                text = ""
                showSlashMenu = false
            }
            Text("输入 /goal 后加目标文字，回车设置。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .padding(.top, 4)
        }
        .frame(width: 260)
    }

    private func slashRow(_ cmd: String, _ desc: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(cmd)
                    .font(.subheadline)
                    .monospaced()
                    .foregroundStyle(DSHTheme.brand)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pickImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        panel.message = "选择图片附件"
        if panel.runModal() == .OK {
            store.addImages(panel.urls)
        }
    }

    /// Accept image files dropped onto the composer and attach them.
    private func acceptDroppedImages(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        var urls: [URL] = []
        var remaining = providers.count
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url = url, Self.isImageFile(url) {
                    urls.append(url)
                }
                remaining -= 1
                if remaining == 0, !urls.isEmpty {
                    DispatchQueue.main.async { store.addImages(urls) }
                }            }
        }
        return true
    }

    /// Open Terminal at the given directory.
    private func openInTerminal(_ path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Terminal", path]
        try? p.run()
    }

    private func copyGlobal(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    /// Open a git remote URL (SSH/git/HTTPS → browser).
    private func openRemote(_ remote: String) {
        var u = remote
        // Map git@host:path and git:// to https:// so browsers can open it.
        if u.hasPrefix("git@") {
            u = "https://" + u.dropFirst(4).replacingOccurrences(of: ":", with: "/")
        } else if u.hasPrefix("git://") {
            u = "https://" + u.dropFirst(6)
        }
        if let url = URL(string: u) {
            NSWorkspace.shared.open(url)
        }
    }

    private static func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(ext)
    }

    /// Compact reasoning-effort label shown beside the model chip.
    private var effortLabel: String {
        switch reasoningEffort {
        case "none": return "无"
        case "low": return "低"
        case "medium": return "中"
        case "high": return "高"
        default: return "默认"
        }
    }

    /// Composer placeholder, mentioning the active project when set.
    private var composerPlaceholder: String {
        if let p = workspace.state.activeProject {
            return "给 \(p.displayName) 发条任务…"
        }
        return "随心输"
    }

    private var composerContextPercent: Int? {
        activeTurnUsage?.contextPercent
    }

    /// Latest usage for the active turn, when present.
    private var activeTurnUsage: TokenUsage? {
        guard let id = store.activeThreadId,
              let t = store.liveThreads.first(where: { $0.id == id }) else { return nil }
        return t.turns.last?.usage
    }

    /// "12.3k / 214k" used-vs-window label, or nil if unknown.
    private var composerContextCounts: String? {
        guard let u = activeTurnUsage,
              u.total > 0,
              let cw = u.contextWindow, cw > 0 else { return nil }
        return "\(formatCount(u.total)) / \(formatCount(cw))"
    }

    private var modelContextTooltip: String {
        var parts = "\n区域: \(TapgoConfig.defaultRegion.displayName)\n端点: \(TapgoConfig.effectiveBaseURL)"
        if let pct = composerContextPercent {
            parts += "\n上下文 \(pct)%"
            if let c = composerContextCounts { parts += " (\(c))" }
        }
        return parts
    }

    private var runInfoText: String {
        var lines = [
            "模型: \(store.modelName)",
            "端点: \(TapgoConfig.effectiveBaseURL)",
            "区域: \(TapgoConfig.defaultRegion.displayName)",
        ]
        if let p = workspace.state.activeProject {
            lines.append("工作目录: \(p.displayPath)")
        }
        if let c = composerContextCounts {
            lines.append("上下文: \(c)")
        }
        return lines.joined(separator: "\n")
    }

    private func effortName(_ e: String) -> String {
        switch e {
        case "none": return "无 (none)"
        case "low": return "低 (low)"
        case "medium": return "中 (medium)"
        case "high": return "高 (high)"
        default: return "默认 (模型定)"
        }
    }

    private func formatCount(_ n: Int) -> String {
        tapgoFormatCount(n)
    }

    /// Small rounded preview of an attached image, falling back to a
    /// placeholder icon when the file can't be loaded.
    private func thumbnail(for url: URL) -> some View {
        Group {
            if let ns = NSImage(contentsOf: url) {
                Image(nsImage: ns)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DSHTheme.border, lineWidth: 1))
        .shadow(color: DSHTheme.cardShadow, radius: 2, x: 0, y: 1)
        .contentShape(Rectangle())
        .onTapGesture {
            // Clicking the thumbnail opens the original image in Preview.
            NSWorkspace.shared.open(url)
        }
        .help(url.lastPathComponent)
    }
}

/// A single-line-by-default text input that grows as the user types: the
/// height tracks the rendered text, capped at `maxHeight` (after which the
/// editor scrolls). Mirrors the harness composer's behaviour.
private struct GrowingTextEditor: View {
    @Binding var text: String
    var placeholder: String = ""
    var minHeight: CGFloat = 36
    var maxHeight: CGFloat = 150
    @FocusState.Binding var focused: Bool
    var onSubmit: () -> Void

    @State private var contentHeight: CGFloat = 36

    private var editorHeight: CGFloat {
        max(min(contentHeight, maxHeight), minHeight)
    }

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .focused($focused)
            .onSubmit(onSubmit)
            .frame(height: editorHeight)
            .overlay(alignment: .topLeading) {
                // Invisible replica that measures the natural height at the
                // current editor width; height never contributes to layout.
                Text(text.isEmpty ? " " : text)
                    .font(.body)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(0)
                    .background(GeometryReader { g in
                        Color.clear
                            .onAppear { contentHeight = min(g.size.height, maxHeight) }
                            .onChange(of: g.size.height) { _, newValue in contentHeight = min(newValue, maxHeight) }
                    })
            }
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(DSHTheme.labelDim)
                        .padding(.top, 5)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }
            }
    }
}
