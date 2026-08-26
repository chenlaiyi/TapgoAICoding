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
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

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
                ComposerView(contentWidth: wideContent ? 980 : 720)
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
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
            TextField("在对话中查找…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .focused($searchFieldFocused)
                .onExitCommand { searchActive = false; searchQuery = "" }
                // ⏎ = 下一处, ⇧⏎ = 上一处 — matching Codex's search bar
                // and the convention in browsers / Finder.
                .onSubmit { jumpToMatch(1) }
                .onChange(of: searchQuery) { _, _ in
                    // New query → forget which match we were on so the
                    // counter resets to "N 个匹配" until the user jumps.
                    jumpToTurnId = nil
                }
            Text(matchCount)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
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
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return "\(threadTurnCount) 回合" }
        let n = matchingTurnIds.count
        if n == 0 { return "0 个匹配" }
        // Show "X/Y" once we have a current match, otherwise just "Y 个匹配"
        // so the user knows the total while they decide to jump.
        if let cur = jumpToTurnId,
           let idx = matchingTurnIds.firstIndex(of: cur) {
            return "\(idx + 1)/\(n)"
        }
        return "\(n) 个匹配"
    }

    private var threadTurnCount: Int {
        store.liveThreads.first(where: { $0.id == store.activeThreadId })?.turns.count ?? 0
    }

    private var searchFilterActive: Bool {
        searchActive && !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Matching turn ids in the active thread, in conversation order.
    /// Delegates to `Turn.matches(query:)` (TapgoCore) so the matching
    /// rule lives in one tested place.
    private var matchingTurnIds: [String] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty,
              let thread = store.liveThreads.first(where: { $0.id == store.activeThreadId }) else { return [] }
        return thread.turns.filter { $0.matches(query: q) }.map(\.id)
    }

    /// Cycle through matches: "下一处" advances, "上一处" backs up.
    /// Wraps around so the user can keep tapping. `jumpToTurnId` drives
    /// the scroll; `matchCount` reads its position out of it.
    private func jumpToMatch(_ delta: Int) {
        let ids = matchingTurnIds
        guard !ids.isEmpty else { return }
        let current = jumpToTurnId ?? ids.first!
        let idx = ids.firstIndex(of: current) ?? 0
        let next = (idx + delta + ids.count) % ids.count
        jumpToTurnId = ids[next]
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
                .font(AppFont.scaled(.largeTitle, multiplier: appFontScale.multiplier).bold())
                .foregroundStyle(.primary)
            ComposerView(contentWidth: 720)
                .padding(.horizontal, 16)
            Text("从左侧选择会话继续，或直接输入开始新任务。")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Session-goal banner set via `/goal`, shown above the conversation.
    @ViewBuilder
    private func threadBody(thread: TapgoCore.Thread) -> some View {
        VStack(spacing: 0) {
            threadHeader(thread: thread)
            Divider()
            if searchActive {
                searchBar
            }
            if let project = thread.projectId.flatMap({ workspace.project(byId: $0) }),
               project.isRemote {
                RemoteBanner(project: project, host: workspace.remoteHost(byId: project.remoteHostId ?? ""))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        // The thread title now lives in the window title
                        // (`.navigationTitle`), so the chat body starts
                        // directly with the turns — no duplicate header.
                        Color.clear.frame(height: 1).id("TOP")
                        ForEach(Array(thread.turns.enumerated()), id: \.element.id) { idx, turn in
                            let isMatch = !searchFilterActive || turn.matches(query: searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))
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
                    .frame(maxWidth: wideContent ? 980 : 720, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(GeometryReader { g in
                        Color.clear.preference(
                            key: ChatContentBottomKey.self,
                            value: g.frame(in: .named("chat")).maxY
                        )
                    })
                }
                .coordinateSpace(name: "chat")
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
                                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
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
                                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
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
                    scrollChatToBottom(proxy)
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
                // On first render (app launch / opening a conversation), land
                // at the latest message so the input box sits right below it.
                .onAppear {
                    scrollChatToBottom(proxy)
                }
            }
        }
    }

    /// Land the chat at the latest message. The "BOTTOM" marker is a trailing
    /// LazyVStack element that may not be laid out yet when a thread opens, so
    /// we delay briefly before scrolling.
    private func scrollChatToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("BOTTOM", anchor: .bottom)
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
                            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                            .foregroundStyle(project.isRemote ? .blue : .accentColor)
                        Text(project.displayName)
                            .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier)).bold()
                    }
                }
            }
            Spacer()
            if thread.usageTotal > 0 || thread.durationTotalText != nil {
                HStack(spacing: 4) {
                    if thread.usageTotal > 0 {
                        Text(TokenUsage.summary(of: thread.usageTotal))
                            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                            .foregroundStyle(.tertiary)
                    }
                    if let d = thread.durationTotalText {
                        Text(d)
                            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            statusPill(thread: thread)
            Button {
                renamingCurrentId = thread.id
                renameDraft = thread.title
            } label: {
                Image(systemName: "pencil")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
            }
            .buttonStyle(.borderless)
            .help("重命名会话")
            .accessibilityLabel("重命名会话")
            if let proj = thread.projectId.flatMap({ workspace.project(byId: $0) }), !proj.isRemote {
                Button {
                    openInTerminal(proj.worktreeRoot.path)
                } label: {
                    Image(systemName: "terminal").font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                }
                .buttonStyle(.borderless)
                .help("在终端中打开项目")
                .accessibilityLabel("在终端中打开项目")
                Button {
                    NSWorkspace.shared.open(proj.worktreeRoot)
                } label: {
                    Image(systemName: "folder").font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
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
                    ForEach(AppFontScale.allCases) { s in
                        Button { fontScale = s.rawValue } label: {
                            if s.rawValue == fontScale {
                                Label(s.displayName, systemImage: "checkmark")
                            } else {
                                Text(s.displayName)
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
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
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

    // MARK: - Status pill (running / failed / idle)

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
            Image(systemName: icon).font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
            Text(label).font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
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
                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
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
                                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                                .foregroundStyle(.tertiary)
                            Text(turnTime(turn.startedAt) + " · " + usage.summary + (turn.durationText.map { " · \($0)" } ?? ""))
                                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
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
                                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                .foregroundStyle(store.turnFeedback[turn.id] == 1 ? DSHTheme.brand : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("有帮助")
                        .accessibilityLabel("有帮助")
                        Button {
                            store.setTurnFeedback(turn.id, -1)
                        } label: {
                            Image(systemName: store.turnFeedback[turn.id] == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
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
                                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
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
                                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
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
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
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
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
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

/// Identifiable payload that opens the goal-edit sheet, carrying the current
/// goal text so the editor can initialise its own @State reliably.
private struct GoalEditItem: Identifiable {
    let id = UUID()
    let text: String
}

/// Goal edit sheet. Uses `@State(initialValue:)` so the TextEditor reliably
/// shows the current goal text (a binding pre-set before `.sheet` presentation
/// can be ignored by TextEditor).
private struct GoalEditorSheet: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    init(initial: String) {
        _text = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑目标").font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier))
            TextEditor(text: $text)
                .font(AppFont.scaled(.body, multiplier: appFontScale.multiplier))
                .frame(minHeight: 80, maxHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(DSHTheme.border, lineWidth: 1))
                .padding(6)
            Text("保存后会暂停计时；需要时点 ▶ 开始重新执行。")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.tertiary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { store.setActiveThreadGoal(t) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// Queued-message edit sheet. Uses `@State(initialValue:)` so the TextEditor
/// reliably shows the queued message's current text.
private struct QueuedMessageEditor: View {
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    let item: QueuedMessage
    @State private var text: String
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    init(item: QueuedMessage) {
        self.item = item
        _text = State(initialValue: item.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑排队消息").font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier))
            TextEditor(text: $text)
                .font(AppFont.scaled(.body, multiplier: appFontScale.multiplier))
                .frame(minHeight: 100, maxHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(DSHTheme.border, lineWidth: 1))
                .padding(6)
            Text("图片附件会保留。")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.tertiary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    store.updateQueuedMessage(item.id, text: text)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// Compact context meter shown in the composer metrics bar: a "context N%"
/// label plus a small progress bar, colour-coded green → yellow → red.
private struct ContextMeter: View {
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    let percent: Int

    private var color: Color {
        switch percent {
        case 80...: return .red
        case 50...: return DSHTheme.warn
        default:    return .green
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("context \(percent)%")
                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(DSHTheme.border)
                    Capsule()
                        .fill(color)
                        .frame(width: g.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
                }
            }
            .frame(width: 72, height: 5)
        }
        .help("当前离线上下文占用 \(percent)%（80% 触发自动压缩）")
        .accessibilityLabel("上下文占用 \(percent)%")
    }
}

/// Animated "typing" dots shown while a turn is streaming. Replaces the
/// plain spinner so the chat reads like Codex while the model generates.
private struct StreamingIndicator: View {
    var label: String = "生成中"
    var startedAt: Date = Date()
    @State private var blinking = false
    @State private var now = Date()
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var elapsedText: String {
        let d = max(now.timeIntervalSince(startedAt), 0)
        return DurationFormatter.string(seconds: d)
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
            Text(elapsedText)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Text("▍")
                .font(AppFont.monoScaled(size: 13, multiplier: appFontScale.multiplier))
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
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    let project: Project
    let host: RemoteHost?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe.americas.fill").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.remoteBanner)
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier)).bold()
                Text(L10n.remoteBannerHint)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
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
    /// How much of the "任务" status card's bottom is tucked behind the
    /// composer card (the "peeking tab" overlap). Keep small so the task
    /// text stays readable (≈1/10 of the card height).
    private let cardOverlap: CGFloat = 6
    @AppStorage("tapgo.composerDraft") private var text: String = ""
    @FocusState private var focused: Bool
    @State private var isDropTargeted = false
    @State private var editorExpanded = false
    @State private var showAttachments = true
    @State private var showSlashMenu = false
    /// When true the composer is in "goal mode": the placeholder asks for a
    /// goal and submit sets/updates the thread's goal instead of a message.
    @State private var isGoalMode = false
    /// NSEvent monitor that intercepts ⌘V to attach clipboard images/files.
    @State private var pasteMonitor: Any?
    /// Goal-card "edit" sheet state (the item carries the initial goal text).
    @State private var editingGoalItem: GoalEditItem?
    /// Queued-message edit sheet state.
    @State private var editingQueued: QueuedMessage?
    @AppStorage(TapgoConfig.sandboxKey) private var sandboxRaw = TapgoConfig.SandboxMode.dangerFullAccess.rawValue
    @AppStorage(TapgoConfig.approvalPolicyKey) private var approvalPolicyRaw = TapgoConfig.ApprovalPolicy.never.rawValue
    @AppStorage(TapgoConfig.reasoningEffortKey) private var reasoningEffort = ""
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

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
                                            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
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
                                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("清空已添加的图片")
                            .accessibilityLabel("清空已添加的图片")
                        }.padding(.horizontal, 4)
                    }
                    .frame(height: 46)
                    .frame(maxWidth: contentWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    HStack(spacing: 6) {
                        Text("已添加 \(store.attachedImages.count) 张图片")
                            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                            .foregroundStyle(.secondary)
                        Button {
                            showAttachments = true
                        } label: {
                            Label("展开", systemImage: "chevron.down")
                                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                        Button {
                            store.clearImages()
                        } label: {
                            Label("清空", systemImage: "trash")
                                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: contentWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            goalCard

            VStack(spacing: store.queue.isEmpty ? 0 : -cardOverlap) {
                queueStatusBar
                    .zIndex(0)

                // Centered, max-width rounded dock (mirrors the DSH composer
                // 'composer-card-max-width'). The input and its controls live
                // inside one raised card. zIndex(1) so it draws on top,
                // covering the task card's bottom `cardOverlap` pixels.
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
                                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                    .foregroundStyle(p.isRemote ? .blue : .secondary)
                                Text(p.displayName).font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier)).lineLimit(1)
                                if !p.isRemote {
                                    Text(p.displayPath)
                                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Image(systemName: "chevron.down").font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier)).foregroundStyle(.tertiary)
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
                                Image(systemName: "folder").font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier)).foregroundStyle(.secondary)
                                Text("选择项目").font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                Image(systemName: "chevron.down").font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier)).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(DSHTheme.surface, in: Capsule())
                        }
                        .menuStyle(.borderlessButton)
                    }

                    environmentChip

                    goalChip

                    Spacer()

                    Button {
                        editorExpanded.toggle()
                    } label: {
                        Image(systemName: editorExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
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
                                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
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
                            Image(systemName: "cpu").font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                            Text(store.modelName).font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                            if isRunning {
                                ProgressView().controlSize(.mini)
                            }
                            if !effortLabel.isEmpty {
                                Text("· \(effortLabel)")
                                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.down").font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier)).foregroundStyle(.tertiary)
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
                                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
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
            .onPasteCommand(of: [.fileURL, .image]) { providers in
                handlePaste(providers)
            }
            .zIndex(1)
            }

            composerMetricsBar
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
        .onChange(of: store.activeThreadId) { _, _ in
            // Goal mode belongs to the previous thread — reset on switch.
            isGoalMode = false
        }
        .onAppear {
            // On launch with a restored thread, put the cursor in the
            // composer so the user can start typing immediately.
            if store.activeThreadId != nil { focused = true }
            setUpPasteMonitor()
        }
        .onDisappear {
            if let m = pasteMonitor { NSEvent.removeMonitor(m); pasteMonitor = nil }
        }
        .sheet(item: $editingGoalItem) { item in
            GoalEditorSheet(initial: item.text)
        }
        .sheet(item: $editingQueued) { item in
            QueuedMessageEditor(item: item)
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
                                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
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
                Image(systemName: currentPermission.icon).font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                Text(currentPermission.title).font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                Image(systemName: "chevron.down")
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
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

    /// Active thread (if any) — the source for the composer metrics bar.
    private var activeThread: TapgoCore.Thread? {
        guard let id = store.activeThreadId else { return nil }
        return store.liveThreads.first(where: { $0.id == id })
    }

    /// DSH-style metrics bar below the input: rounds · steps · LLM time ·
    /// cache hit · input tokens · a live context meter (replaces the old top
    /// context banner).
    @ViewBuilder
    private var composerMetricsBar: some View {
        if let thread = activeThread {
            let rounds = thread.turns.count
            let steps = thread.turns.reduce(0) { acc, t in
                acc + t.items.filter { item in
                    switch item {
                    case .toolCall, .commandExecution: return true
                    default: return false
                    }
                }.count
            }
            let lastUsage = thread.turns.last(where: { $0.usage != nil })?.usage
            let pct = lastUsage?.contextPercent
            let cacheHit = cacheHitPercent(lastUsage)

            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    Text("\(rounds) 轮")
                    Text("·")
                    Text("\(steps) 步")
                }
                if let d = thread.durationTotalText {
                    Text("LLM \(d)")
                }
                if let c = cacheHit {
                    Text("缓存命中 \(c)%")
                }
                if thread.usageTotal > 0 {
                    Text("输入 \(tapgoFormatCount(thread.usageTotal))")
                }
                Spacer()
                if let pct {
                    ContextMeter(percent: pct)
                }
            }
            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .frame(maxWidth: contentWidth)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func cacheHitPercent(_ usage: TokenUsage?) -> Int? {
        guard let usage, usage.input > 0 else { return nil }
        return Int((Double(usage.cached) / Double(usage.input) * 100).rounded())
    }

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
        // Only show the task card when there is an actual task list (queued
        // messages). With an empty queue it would just repeat the running
        // message — so it stays hidden.
        if !store.queue.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(DSHTheme.brand)
                    Text("任务清单 · \(store.queue.count) 待处理")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .fontWeight(.medium)
                        .foregroundStyle(DSHTheme.brand)
                    Spacer()
                    Button {
                        store.interjectAndFlush()
                    } label: {
                        Label("发送全部", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(DSHTheme.warn)
                    .keyboardShortcut(.return, modifiers: [.control])
                    .help("Ctrl+Enter 中断当前并立即发送全部排队消息")
                    .accessibilityLabel("发送全部排队消息")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(store.queue) { q in
                            HStack(spacing: 6) {
                                Image(systemName: "text.bubble")
                                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                    .foregroundStyle(.secondary)
                                Text(q.text.isEmpty ? "(图片附件)" : q.text)
                                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                if !q.images.isEmpty {
                                    Text("🖼 \(q.images.count)")
                                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    editingQueued = q
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .help("编辑这条排队消息")
                                .accessibilityLabel("编辑排队消息")
                                Button {
                                    store.removeQueued(q.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .help("删除这条排队消息")
                                .accessibilityLabel("删除排队消息")
                                Button {
                                    store.sendQueuedNow(q.id)
                                } label: {
                                    Image(systemName: "arrow.up")
                                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                        .foregroundStyle(DSHTheme.brand)
                                }
                                .buttonStyle(.borderless)
                                .help("发送这条（让当前任务/目标调整方向）")
                                .accessibilityLabel("发送这条排队消息")
                            }
                        }
                        HStack {
                            Spacer()
                            Button("清空排队") { store.clearQueue() }
                                .buttonStyle(.borderless)
                                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxHeight: 150)
                .padding(6)
                .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: contentWidth - 48)
            .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(DSHTheme.border, lineWidth: 1))
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// Send the composed message. While a turn is running the message is
    /// queued instead of dropped.
    private func send() {
        // Goal mode: submit sets/updates the thread's goal, not a message.
        if isGoalMode {
            let goalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !goalText.isEmpty {
                store.setActiveThreadGoal(goalText)
                text = ""
                isGoalMode = false
            }
            focused = true
            return
        }
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
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
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
                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
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
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                    .monospaced()
                    .foregroundStyle(DSHTheme.brand)
                Text(desc)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
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

    /// Attach an image/file pasted from the clipboard (⌘V). Image data is
    /// written to a temp PNG; file URLs are added directly.
    private func handlePaste(_ providers: [NSItemProvider]) {
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async { store.addImages([url]) }
                    }
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                      let typeID = p.registeredTypeIdentifiers.first(where: {
                          (UTType($0)?.conforms(to: .image)) ?? false
                      }) {
                p.loadDataRepresentation(forTypeIdentifier: typeID) { data, _ in
                    if let data = data {
                        self.decodeAndAttachImage(data)
                    }
                }
            }
        }
    }

    private func decodeAndAttachImage(_ data: Data) {
        var png = data
        if let ns = NSImage(data: data),
           let tiff = ns.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let converted = rep.representation(using: .png, properties: [:]) {
            png = converted
        }
        if let url = Self.writePastedImage(png, ext: "png") {
            DispatchQueue.main.async { store.addImages([url]) }
        }
    }

    /// Write pasted image bytes to a temp file so it can be attached.
    /// Intercept ⌘V at the window: if the pasteboard holds an image or file,
    /// attach it instead of letting the focused TextEditor paste text only.
    private func setUpPasteMonitor() {
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers == "v" else { return event }
            let pb = NSPasteboard.general
            if pb.canReadItem(withDataConformingToTypes: [UTType.image.identifier, UTType.fileURL.identifier]) {
                handlePasteboard(pb)
                return nil
            }
            return event
        }
    }

    private func handlePasteboard(_ pb: NSPasteboard) {
        if let url = pb.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL {
            DispatchQueue.main.async { store.addImages([url]) }
        } else if let data = pb.data(forType: .png) {
            decodeAndAttachImage(data)
        }
    }

    private static func writePastedImage(_ data: Data, ext: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tapgo-paste", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("paste-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
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
        if isGoalMode { return "描述你想完成的目标" }
        if let p = workspace.state.activeProject {
            return "给 \(p.displayName) 发条任务…"
        }
        return "随心输"
    }

    /// The active thread's current goal text (drives the 目标 chip highlight).
    private var activeThreadGoal: String? {
        guard let id = store.activeThreadId else { return nil }
        return store.liveThreads.first(where: { $0.id == id })?.goal
    }

    /// "目标" mode toggle in the composer toolbar. Highlights when a goal is
    /// set or goal mode is active.
    private var goalChip: some View {
        Button {
            toggleGoalMode()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "scope").font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                Text(titleForGoalChip)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((isGoalMode || activeThreadGoal != nil) ? DSHTheme.brandSoft : DSHTheme.surface, in: Capsule())
            .foregroundStyle((isGoalMode || activeThreadGoal != nil) ? DSHTheme.brand : .secondary)
        }
        .buttonStyle(.plain)
        .help(isGoalMode ? "退出目标模式" : "设置会话目标")
        .accessibilityLabel("目标")
    }

    private var titleForGoalChip: String {
        // The goal card above the input already shows the full text; the chip
        // is a compact toggle.
        if isGoalMode || activeThreadGoal != nil { return "目标" }
        return "设为目标"
    }

    /// Clicking the 目标 chip: if the user has typed a goal, commit it
    /// directly (one step) — the goal card appears at the top and the chip
    /// highlights. We deliberately leave the text in the composer so the user
    /// can also press 发送 to have the model act on it. If nothing is typed,
    /// toggle goal mode instead.
    private func toggleGoalMode() {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty {
            store.setActiveThreadGoal(typed)
            isGoalMode = false
        } else {
            isGoalMode.toggle()
        }
    }

    /// Goal card rendered just above the input box (not at the top of the
    /// conversation): 进行中 / 已设目标 + goal text + live elapsed time +
    /// clear. Status is dynamic — "进行中" only while the agent is actually
    /// running.
    @ViewBuilder
    private var goalCard: some View {
        if let thread = activeThread, let goal = thread.goal, !goal.isEmpty {
            let goalRunning = thread.goalStatus == "running"
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "scope")
                    .foregroundStyle(DSHTheme.brand)
                HStack(spacing: 6) {
                    Circle()
                        .fill(goalRunning ? .green : DSHTheme.brand.opacity(0.6))
                        .frame(width: 7, height: 7)
                    Text(goalRunning ? "进行中" : "已暂停")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                }
                .foregroundStyle(.secondary)
                Text(goal)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(goalElapsedText(store.goalElapsedSeconds(thread)))
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.tertiary)
                }
                if goalRunning {
                    Button {
                        store.pauseGoal()
                    } label: {
                        Image(systemName: "pause.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("暂停目标")
                    .accessibilityLabel("暂停目标")
                } else {
                    Button {
                        store.startGoal()
                    } label: {
                        Image(systemName: "play.fill")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.borderless)
                    .help("开始执行目标（会把目标作为消息发出）")
                    .accessibilityLabel("开始执行目标")
                }
                Button {
                    editingGoalItem = GoalEditItem(text: goal)
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("编辑目标")
                .accessibilityLabel("编辑目标")
                Button {
                    store.setActiveThreadGoal(nil)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("清除目标")
                .accessibilityLabel("清除目标")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(DSHTheme.brand.opacity(0.25), lineWidth: 1))
            .frame(maxWidth: contentWidth - 48)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// Compact elapsed time ("1h20m", "2m05s", "45s") for the goal card.
    private func goalElapsedText(_ interval: TimeInterval) -> String {
        let s = Int(interval)
        if s >= 3600 { return "\(s / 3600)h\(String(format: "%02dm", (s % 3600) / 60))" }
        if s >= 60 { return "\(s / 60)m\(s % 60)s" }
        return "\(s)s"
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
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
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
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    private var editorHeight: CGFloat {
        max(min(contentHeight, maxHeight), minHeight)
    }

    var body: some View {
        TextEditor(text: $text)
            .font(AppFont.scaled(.body, multiplier: appFontScale.multiplier))
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .focused($focused)
            .onSubmit(onSubmit)
            .frame(height: editorHeight)
            .overlay(alignment: .topLeading) {
                // Invisible replica that measures the natural height at the
                // current editor width; height never contributes to layout.
                Text(text.isEmpty ? " " : text)
                    .font(AppFont.scaled(.body, multiplier: appFontScale.multiplier))
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
                        .font(AppFont.scaled(.body, multiplier: appFontScale.multiplier))
                        .foregroundStyle(DSHTheme.labelDim)
                        .padding(.top, 5)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }
            }
    }
}
