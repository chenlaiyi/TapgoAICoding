import SwiftUI
import Combine
import TapgoCore
import UniformTypeIdentifiers

/// Compact token/byte formatter shared by ChatView and ComposerView:
/// "1.2M" / "12.3k" / "123".
internal func tapgoFormatCount(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.0fk", Double(n) / 1_000) }
    return "\(n)"
}

/// True iff the composer holds nothing the user could meaningfully send.
/// Strips Unicode invisibles (NBSP / 全角空格 / ZW*) before testing, so a
/// composer that only contains an NBSP or zero-width joiner is treated as
/// empty. The previous `text.trimmingCharacters(in: .whitespacesAndNewlines)`
/// check missed these and the inline `xmark.circle.fill` clear button
/// leaked through in an otherwise empty composer.
internal func tapgoIsComposerUserContentEmpty(text: String, attachedImageCount: Int) -> Bool {
    if attachedImageCount > 0 { return false }
    let invisibles: Set<Character> = [
        "\u{00A0}", // NBSP
        "\u{2007}", // FIGURE SPACE
        "\u{202F}", // NARROW NO-BREAK SPACE
        "\u{3000}", // IDEOGRAPHIC SPACE (全角空格)
        "\u{FEFF}", // ZERO WIDTH NO-BREAK SPACE
        "\u{200B}", // ZERO WIDTH SPACE
        "\u{200C}", // ZWNJ
        "\u{200D}", // ZWJ
        "\u{2060}", // WORD JOINER
    ]
    for ch in text {
        if ch.isWhitespace { continue }
        if invisibles.contains(ch) { continue }
        return false
    }
    return true
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
              approval: TapgoConfig.ApprovalPolicy.untrusted.rawValue),
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

/// Coalesces high-frequency stream updates without publishing another piece
/// of SwiftUI state. Command stdout and assistant deltas can arrive many times
/// per second; starting a new scroll animation for every delta starves the
/// text editor and makes IME composition visibly jump.
private final class StreamScrollCoalescer {
    private var pending: DispatchWorkItem?

    func schedule(_ action: @escaping () -> Void) {
        guard pending == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.pending = nil
            action()
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: item)
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}

/// Persists composer drafts only after typing pauses. AppStorage used to
/// publish on every keystroke while the transcript was also streaming.
private final class ComposerDraftSaver {
    private var pending: DispatchWorkItem?
    private let key = "tapgo.composerDraft"

    func schedule(_ value: String) {
        pending?.cancel()
        let item = DispatchWorkItem { [key] in
            UserDefaults.standard.set(value, forKey: key)
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    func flush(_ value: String) {
        pending?.cancel()
        pending = nil
        UserDefaults.standard.set(value, forKey: key)
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
    @State private var showEvolutionLog = false
    /// Codex-style fold state: completed turns collapse their work log into
    /// an "已处理 …" row. File edits remain visible as a separate summary card.
    @State private var expandedWork: Set<String> = []
    @State private var showShortcuts = false
    @State private var streamScrollCoalescer = StreamScrollCoalescer()
    @AppStorage("tapgo.wideContent") private var wideContent = false
    @AppStorage("tapgo.fontScale") private var fontScale = "medium"
    /// Global toggle for the ZCode-style "工作过程" work log (thinking,
    /// terminal, file edit, file read cards inside a turn). Default off
    /// because the per-row stream drowned the actual answer for users who
    /// do not care about the agent's internal mechanics. The chip +
    /// summary bar still appear; only the per-event rows hide.
    /// Individual `expandedWork` ids are AND-ed with this flag, so
    /// turning it off immediately collapses every expanded turn and
    /// the per-row chip toggles are inert until it is back on.
    @AppStorage("tapgo.showWorkProcess") private var showWorkProcess = false
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    var body: some View {
        VStack(spacing: 0) {
            if let thread = activeThread, hasConversation {
                threadBody(thread: thread)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 空会话也要能看到自进化引导横幅——否则新建的自进化
                // 会话没有「开始自进化」入口，独立开发无从发起。
                if let thread = activeThread, thread.isEvolution {
                    EvolutionPanel(thread: thread) { showEvolutionLog = true }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
                Spacer()
                Text("我们该处理什么工作？")
                    .font(AppFont.scaled(.largeTitle, multiplier: appFontScale.multiplier).bold())
                    .foregroundStyle(.primary)
                    .padding(.bottom, 8)
            }

            // Keep one structural ComposerView for the entire lifetime of
            // ChatView. Moving between the empty and active layouts must not
            // recreate NSTextView while the user is entering the next prompt.
            ComposerView(contentWidth: wideContent ? 980 : 720)
                .padding(.horizontal, hasConversation ? 0 : 16)

            if !hasConversation {
                Text("从左侧选择会话继续，或直接输入开始新任务。")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSHTheme.fidelityMainCanvas)
        .navigationTitle("")
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
        .sheet(isPresented: $showEvolutionLog) {
            EvolutionLogView()
        }
        .sheet(isPresented: $showShortcuts) {
            ShortcutsView()
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
            if t.isEvolution {
                // 自进化会话独立于项目分组，标题固定，后缀显示真实
                // 工作目录名让用户一眼确认改的是哪个仓库。
                let repo = t.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Tapgo AICoding"
                return "自进化 — \(repo)"
            }
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
           let t = store.liveThreads.first(where: { $0.id == id }) {
            if t.isEvolution {
                return t.cwd ?? "自进化 · 独立开发会话"
            }
            if let project = t.projectId.flatMap({ workspace.project(byId: $0) }) {
                return project.isRemote ? project.displayName : project.displayPath
            }
        }
        return "独立会话"
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
            if thread.isEvolution {
                EvolutionPanel(thread: thread) { showEvolutionLog = true }
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
                // The user just submitted a message — jump to the bottom
                // regardless of where the viewport was, so the new bubble is
                // always visible right above the composer.
                .onReceive(NotificationCenter.default.publisher(for: .tapgoRequestScrollToBottom)) { _ in
                    showNewMessage = false
                    streamScrollCoalescer.schedule {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            proxy.scrollTo("BOTTOM", anchor: .bottom)
                        }
                    }
                    lastWasNearBottom = true
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
                        streamScrollCoalescer.schedule {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                proxy.scrollTo("BOTTOM", anchor: .bottom)
                            }
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
                    if near {
                        showNewMessage = false
                    } else {
                        streamScrollCoalescer.cancel()
                    }
                }
                // When switching threads, land at the latest message.
                .onChange(of: thread.id) { _, _ in
                    streamScrollCoalescer.cancel()
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
                .onDisappear {
                    streamScrollCoalescer.cancel()
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
    private func threadHeader(thread: TapgoCore.Thread) -> some View {
        HStack(alignment: .center, spacing: 7) {
            Button {
                renamingCurrentId = thread.id
                renameDraft = thread.title
            } label: {
                Text(thread.title)
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier).weight(.semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("重命名任务")

            if let project = thread.projectId.flatMap({ workspace.project(byId: $0) }) {
                HStack(spacing: 4) {
                    Image(systemName: project.isRemote ? "globe" : "folder")
                    Text(project.displayName).lineLimit(1)
                }
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 6))
            }

            Menu {
                Button { copyToPasteboard(thread.title) } label: {
                    Label("复制标题", systemImage: "doc.on.doc")
                }
                Button { copyConversation(thread) } label: {
                    Label("复制为 Markdown", systemImage: "doc.on.doc")
                }
                Button { copyConversationAsText(thread) } label: {
                    Label("复制为纯文本", systemImage: "text.alignleft")
                }
                Divider()
                Button { wideContent.toggle() } label: {
                    Label(wideContent ? "使用标准内容宽度" : "使用宽内容区", systemImage: "arrow.left.and.right")
                }
                Menu {
                    ForEach(AppFontScale.allCases) { size in
                        Button { fontScale = size.rawValue } label: {
                            if size.rawValue == fontScale {
                                Label(size.displayName, systemImage: "checkmark")
                            } else {
                                Text(size.displayName)
                            }
                        }
                    }
                } label: {
                    Label("字体大小", systemImage: "textformat.size")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("任务更多操作")

            Spacer(minLength: 8)

            if thread.usageTotal > 0 {
                Text(TokenUsage.summary(of: thread.usageTotal))
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
            }
            if let project = thread.projectId.flatMap({ workspace.project(byId: $0) }), !project.isRemote {
                Button { NSWorkspace.shared.open(project.worktreeRoot) } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("在 Finder 中打开")
                .accessibilityLabel("在 Finder 中打开")
                Menu {
                    Button { NSWorkspace.shared.open(project.worktreeRoot) } label: {
                        Label("Finder", systemImage: "folder")
                    }
                    Button { openInTerminal(project.worktreeRoot.path) } label: {
                        Label("终端", systemImage: "terminal")
                    }
                    Button {
                        NotificationCenter.default.post(
                            name: .tapgoOpenWorkbenchTab,
                            object: WorkbenchLayoutState.TabKind.browser.rawValue
                        )
                    } label: {
                        Label("侧边浏览器", systemImage: "globe")
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .help("选择打开方式")
                .accessibilityLabel("选择打开方式")
            }
            Button { showShortcuts = true } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .help("快捷键")
            Button {
                NotificationCenter.default.post(
                    name: .tapgoOpenWorkbenchTab,
                    object: WorkbenchLayoutState.TabKind.terminal.rawValue
                )
            } label: {
                Image(systemName: "terminal")
            }
            .buttonStyle(.borderless)
            .help("切换终端")
            .accessibilityLabel("切换终端")
            Button {
                NotificationCenter.default.post(name: .tapgoToggleTrajectory, object: nil)
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .buttonStyle(.borderless)
            .help("切换侧边面板")
            .accessibilityLabel("切换侧边面板")
            if thread.turns.last?.status == .running {
                Button { store.cancelActiveTurn() } label: {
                    Image(systemName: "stop.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help(L10n.interrupt)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(DSHTheme.fidelityTitlebar)
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
                if item.isAppGeneratedProgress { continue }
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
                if item.isAppGeneratedProgress { continue }
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

    /// Compact "HH:mm" timestamp for a turn, used in the per-turn footer.
    private func turnTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func turnMetadataHelp(_ turn: Turn) -> String {
        var parts = ["复制本回合", turnTime(turn.startedAt)]
        if let duration = turn.durationText, !duration.isEmpty { parts.append(duration) }
        if let usage = turn.usage { parts.append(usage.summary) }
        return parts.joined(separator: " · ")
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

    @ViewBuilder
    private func turnSection(turn: Turn, isLast: Bool = false) -> some View {
        let isRunning = turn.status == .running
        let blocks = TurnPresentation.compactBlocks(turn.items)
        let fileChanges = turn.items.compactMap { item -> FileChange? in
            guard case .fileChange(let change) = item else { return nil }
            return change
        }
        VStack(alignment: .leading, spacing: 10) {
            // Codex-style work log. Live activity stays in the transcript;
            // completed activity folds into one quiet duration row. File
            // changes are promoted into their own persistent summary card.
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                switch block {
                case .item:
                    renderBlock(block, turn: turn)
                case .activity:
                    if isRunning {
                        renderBlock(block, turn: turn)
                    } else {
                        if index == firstActivityBlockIndex(blocks) {
                            workDurationChip(turn: turn)
                        }
                        let revealed = showWorkProcess && expandedWork.contains(turn.id)
                        if revealed { renderBlock(block, turn: turn) }
                    }
                case .fileBatch:
                    if isRunning {
                        // During execution, show the current file batch where
                        // it happened. Completed turns consolidate all edits
                        // into one card below the answer, like Codex.
                        renderBlock(block, turn: turn)
                    }
                }
            }
            if !isRunning, !fileChanges.isEmpty {
                FileEditBatchView(files: fileChanges)
                    .padding(.top, 2)
            }
            if isRunning && !hasRollingActivityTail(turn) && !hasStreamingAssistant(turn) {
                runningActivityLine(turn: turn)
            }
            if turn.status == .completed || turn.status == .failed || turn.status == .interrupted {
                // Codex keeps completion actions as a quiet icon row. Time,
                // usage and duration remain discoverable in the copy tooltip.
                HStack(spacing: 10) {
                    CopyIconButton(text: TurnMarkdown.render(turn), help: turnMetadataHelp(turn))
                        .controlSize(.mini)
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
                                Image(systemName: "arrow.turn.up.right")
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
                            Image(systemName: "arrow.clockwise")
                                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(DSHTheme.brand)
                        .help("重试本回合")
                        .accessibilityLabel("重试本回合")
                    }
                    Spacer()
                }
                .foregroundStyle(DSHTheme.labelTertiary)
                .padding(.top, 1)
            }
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: TurnPresentationBlock, turn: Turn) -> some View {
        switch block {
        case .item(let item):
            MessageRow(item: item,
                       isRunning: turn.status == .running,
                       userImagePaths: turn.userImagePaths,
                       startedAt: turn.startedAt,
                       onReply: userReplyClosure(item),
                       onEdit: { store.sendUserMessage($0) })
        case .activity(let activity):
            ActivityRollupView(
                activity: activity,
                turnIsRunning: turn.status == .running
            )
        case .fileBatch(let files):
            FileEditBatchView(files: files)
        }
    }

    /// "已处理 8 分 53 秒 >" — Codex's quiet completed-work boundary.
    private func workDurationChip(turn: Turn) -> some View {
        let expanded = expandedWork.contains(turn.id)
        return HStack(spacing: 9) {
            Button {
                toggleWork(turn.id)
            } label: {
                HStack(spacing: 5) {
                    Text("已处理 \(localizedWorkDuration(turn.duration))")
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(DSHTheme.labelTertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "折叠处理过程" : "展开处理过程")
            Rectangle()
                .fill(DSHTheme.border)
                .frame(height: 1)
        }
        .padding(.vertical, 2)
    }

    private func firstActivityBlockIndex(_ blocks: [TurnPresentationBlock]) -> Int? {
        blocks.firstIndex { block in
            switch block {
            case .activity: return true
            case .item, .fileBatch: return false
            }
        }
    }

    private func toggleWork(_ id: String) {
        if !showWorkProcess { showWorkProcess = true }
        if expandedWork.contains(id) {
            expandedWork.remove(id)
        } else {
            expandedWork.insert(id)
        }
    }

    /// Reasoning, command and tool events are already represented by the
    /// single rolling activity row. Do not append a second generic row.
    private func hasRollingActivityTail(_ turn: Turn) -> Bool {
        guard let last = turn.items.last else { return false }
        switch last {
        case .reasoning, .reasoningSummary, .commandExecution, .toolCall: return true
        default: return false
        }
    }

    private func hasStreamingAssistant(_ turn: Turn) -> Bool {
        guard let last = turn.items.last else { return false }
        if case .assistantMessage = last { return true }
        return false
    }

    private func localizedWorkDuration(_ duration: TimeInterval?) -> String {
        let total = max(Int((duration ?? 0).rounded()), 0)
        if total < 60 { return "\(total) 秒" }
        let minutes = total / 60
        let seconds = total % 60
        if minutes < 60 {
            return seconds == 0 ? "\(minutes) 分钟" : "\(minutes) 分 \(seconds) 秒"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) 小时" : "\(hours) 小时 \(remainder) 分"
    }

    /// While a reply streams without a tool item, keep one muted activity row
    /// at the latest position. The composer already owns the global stop
    /// control, so historical chat content never grows another stop card.
    @ViewBuilder
    private func runningActivityLine(turn: Turn) -> some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 16, height: 16)
            Text(runningActivityLabel(turn))
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(runningActivityLabel(turn))
            Spacer(minLength: 0)
        }
        .foregroundStyle(DSHTheme.labelTertiary)
    }

    private func runningActivityLabel(_ turn: Turn) -> String {
        guard let last = turn.items.last else { return "思考中…" }
        switch last {
        case .reasoning, .reasoningSummary: return "正在思考"
        case .commandExecution(let execution):
            return TurnPresentation.activityDisplay(for: .commandExecution(execution)).text
        case .toolCall(let call):
            return TurnPresentation.activityDisplay(for: .toolCall(call)).text
        case .fileChange(let change):
            return TurnPresentation.activityDisplay(for: .fileChange(change)).text
        case .assistantMessage: return "正在生成回复"
        default: return "正在处理"
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
    /// 与 ChatView 同 key 的本地镜像：切换模型菜单用高亮当前模型。
    @AppStorage(TapgoConfig.selectedModelKey) private var selectedModelRaw =
        "builtin:\(TapgoModel.minimaxM3.rawValue)"
    /// 归一化后的选中 ID（旧裸 slug → builtin: 前缀），用于菜单勾选判断。
    private var selectedModelID: String { ModelRegistry.normalizedID(selectedModelRaw) }
    /// How much of the "任务" status card's bottom is tucked behind the
    /// composer card (the "peeking tab" overlap). Keep small so the task
    /// Keep live editing local. The persisted draft is written by the
    /// coalescer instead of invalidating SwiftUI for every character.
    @State private var text: String = UserDefaults.standard.string(forKey: "tapgo.composerDraft") ?? ""
    @State private var draftSaver = ComposerDraftSaver()
    @FocusState private var focused: Bool
    @State private var isDropTargeted = false
    @State private var editorExpanded = false
    @State private var showAttachments = true
    @State private var showSlashMenu = false
    /// When true the composer is in "goal mode": the placeholder asks for a
    /// goal and submit sets/updates the thread's goal instead of a message.
    /// NSEvent monitor that intercepts ⌘V to attach clipboard images/files.
    @State private var pasteMonitor: Any?
    /// Goal-card "edit" sheet state (the item carries the initial goal text).
    @State private var editingGoalItem: GoalEditItem?
    /// Queued-message edit sheet state.
    @State private var editingQueued: QueuedMessage?
    /// The compact progress chip stays visible during a planned turn; its
    /// full checklist opens only when the user asks for it.
    @State private var showTurnProgressDetails = false
    /// composer 底部圆形进度条 popover。`pinned` 表示用户已点开,鼠标
    /// 移出不应自动关闭。
    @State private var showUsagePopover: Bool = false
    @State private var usagePopoverPinned: Bool = false
    @AppStorage(TapgoConfig.sandboxKey) private var sandboxRaw = TapgoConfig.SandboxMode.dangerFullAccess.rawValue
    @AppStorage(TapgoConfig.approvalPolicyKey) private var approvalPolicyRaw = TapgoConfig.ApprovalPolicy.never.rawValue
    @AppStorage(TapgoConfig.reasoningEffortKey) private var reasoningEffort = ""
    @AppStorage(TapgoConfig.computerUseEnabledKey) private var computerUseEnabled = true
    @AppStorage(TapgoConfig.computerUseShowInComposerKey) private var computerUseShowInComposer = true
    @State private var computerPermissionRefresh = 0
    @State private var computerPermissionState = ComputerUsePermissionState.loading
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

            turnProgressBadge

            // Queue sits directly above the composer as an independent rounded
            // panel — matching Codex: queue card is 90% of the composer card
            // width, same surface, same radius, separated by a small gap.
            // spacing -25 让 composer 顶部向下压住队列卡片约 25pt，
            // 形成清晰的「输入框浮在排队卡片上方」层次。
            VStack(spacing: store.activeQueue.isEmpty ? 0 : -25) {
                queueStatusBar

                // Codex Desktop keeps text and controls inside one quiet card.
                VStack(spacing: 10) {
                GrowingTextEditor(
                    text: $text,
                    placeholder: composerPlaceholder,
                    minHeight: 38,
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
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help("添加附件 / 插入技能")
                    .accessibilityLabel("添加附件或技能")

                    // 自进化会话的专属项目条：固定指向 TapgoAICoding 项目
                    // 根，不跟随 activeProject——否则用户看到「OctTapgo」
                    // 会以为还在项目会话里（v0.5.33 用户实测踩坑）。
                    if let thread = activeThread, thread.isEvolution {
                        let repoName = thread.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Tapgo AICoding"
                        Button {
                            if let cwd = thread.cwd {
                                NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                    .foregroundStyle(DSHTheme.brand)
                                Text("自进化 · \(repoName)")
                                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 3).padding(.vertical, 3)
                            .help("自进化会话固定工作在 \(thread.cwd ?? repoName)，消息只发进本会话")
                            .accessibilityLabel("自进化会话，工作目录 \(thread.cwd ?? repoName)")
                        }
                        .buttonStyle(.plain)
                    } else if activeThread == nil, let p = workspace.state.activeProject {
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
                            }
                            .padding(.horizontal, 3).padding(.vertical, 3)
                            .help("\(p.displayName) · \(p.displayPath)")
                            .accessibilityLabel("当前项目 \(p.displayName), 路径 \(p.displayPath), 点击切换")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                    } else if activeThread == nil {
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
                            }
                            .padding(.horizontal, 3).padding(.vertical, 3)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                    }

                    environmentChip

                    if computerUseShowInComposer {
                        computerControlChip
                    }

                    contextMeterChip

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

                    if !tapgoIsComposerUserContentEmpty(text: text, attachedImageCount: store.attachedImages.count) {
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
                        // v0.5.41: 弹窗只保留模型列表（品牌 + 模型名，勾选当前），
                        // 点开即选、对新建会话生效。端点/上下文信息看圆环弹窗，
                        // 思考深度在「运行设置」，新建会话有 ⌘N。
                        ForEach(TapgoConfig.allModels()) { m in
                            Button {
                                TapgoConfig.setSelectedModel(id: m.id)
                                selectedModelRaw = m.id
                                store.refreshRateLimits()
                            } label: {
                                if m.id == selectedModelID {
                                    Label(m.displayName, systemImage: "checkmark")
                                } else {
                                    Text(m.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(store.modelDisplayName).font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                            if isRunning {
                                ProgressView().controlSize(.mini)
                            }
                            if !effortLabel.isEmpty {
                                Text("· \(effortLabel)")
                                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.down")
                                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        }
                        .foregroundStyle(DSHTheme.labelDim)
                        .padding(.horizontal, 3).padding(.vertical, 3)
                        .help(L10n.modelChipHint + modelContextTooltip)
                        .accessibilityLabel("模型 \(store.modelDisplayName), 来自独立配置")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)

                    if isRunning {
                        Button(action: { store.cancelActiveTurn() }) {
                            Image(systemName: "stop.fill")
                                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                                .frame(width: 28, height: 28)
                                .foregroundStyle(DSHTheme.brandPrimaryText)
                                .background(DSHTheme.brandPrimary, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("中断当前任务（排队消息会被保留）")
                        .accessibilityLabel("中断当前任务")
                    }
                    Button(action: send) {
                        Image(systemName: "paperplane.fill")
                            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(DSHTheme.brandPrimaryText)
                            .background(DSHTheme.brandPrimary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(canSend ? 1 : 0.32)
                    .disabled(canSend == false)
                    .help(isRunning ? "发送（排队）(⌘↩)" : "发送 (⌘↩)")
                    .accessibilityLabel(L10n.sendButton)
                }
            }
            .padding(12)
            .background(DSHTheme.bgLayer1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isDropTargeted ? DSHTheme.brand : (focused ? DSHTheme.borderStrong : DSHTheme.border), lineWidth: isDropTargeted ? 2 : 1)
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

        }
        .frame(maxWidth: contentWidth, alignment: .center)
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
            draftSaver.schedule(newValue)
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            computerPermissionRefresh += 1
        }
        .task(id: computerPermissionRefresh) {
            computerPermissionState = await ComputerUsePermissionProbe.read(
                helperAppURL: TapgoConfig.computerUseHelperAppURL()
            )
        }
        .onChange(of: workspace.state.activeProjectId) { _, _ in
            // A draft typed for one project shouldn't be sent to another.
            text = ""
        }
        .onChange(of: store.activeThreadId) { _, _ in
            showTurnProgressDetails = false
        }
        .onChange(of: isRunning) { _, running in
            if !running { showTurnProgressDetails = false }
        }
        .onAppear {
            // On launch with a restored thread, put the cursor in the
            // composer so the user can start typing immediately.
            if store.activeThreadId != nil { focused = true }
            setUpPasteMonitor()
        }
        .onDisappear {
            draftSaver.flush(text)
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
            }
            .foregroundStyle(currentPermission.id == PermissionChoice.full.id ? DSHTheme.warn : DSHTheme.labelDim)
            .padding(.horizontal, 3).padding(.vertical, 3)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("操作权限: \(currentPermission.title)")
        .accessibilityLabel("操作权限")
    }

    private var currentPermission: PermissionChoice {
        PermissionChoice.all.first { $0.matches(sandboxRaw: sandboxRaw, approvalRaw: approvalPolicyRaw) }
            ?? PermissionChoice.full
    }

    /// Compact computer-control status. Codex's composer keeps secondary
    /// capabilities icon-only so the permission and model remain scannable.
    private var computerControlChip: some View {
        let _ = computerPermissionRefresh
        return Button {
            NotificationCenter.default.post(
                name: .tapgoRequestOpenSettings,
                object: SettingsView.Tab.computer.rawValue
            )
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "display")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                Circle()
                    .fill(computerControlStatusColor)
                    .frame(width: 6, height: 6)
            }
            .foregroundStyle(computerUseEnabled ? DSHTheme.labelDim : DSHTheme.labelTertiary)
            .padding(.horizontal, 3)
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .help(computerControlStatusText + "；点击打开电脑控制设置")
        .accessibilityLabel("电脑操作，\(computerControlStatusText)")
    }

    private var computerControlStatusColor: Color {
        guard computerUseEnabled else { return DSHTheme.labelTertiary }
        return computerControlReady ? DSHTheme.success : DSHTheme.warn
    }

    private var computerControlReady: Bool {
        computerUseEnabled
            && computerPermissionState.accessibility == true
            && computerPermissionState.screenRecording == true
            && computerUseConfigRegistered
    }

    private var computerUseConfigRegistered: Bool {
        guard let config = try? String(contentsOf: TapgoConfig.configPath, encoding: .utf8) else {
            return false
        }
        return config.contains("[mcp_servers.\(ComputerUseMCP.configServerKey)]")
    }

    private var computerControlStatusText: String {
        guard computerUseEnabled else { return "电脑控制已关闭" }
        var missing: [String] = []
        if computerPermissionState.accessibility != true { missing.append("辅助功能未授权") }
        if computerPermissionState.screenRecording != true { missing.append("屏幕录制未授权") }
        if !computerUseConfigRegistered { missing.append("MCP 未注册") }
        return missing.isEmpty ? "电脑控制已就绪" : missing.joined(separator: "、")
    }

    private var isRunning: Bool { store.isRunning }

    /// Active thread (if any) — the source for the composer metrics bar.
    private var activeThread: TapgoCore.Thread? {
        guard let id = store.activeThreadId else { return nil }
        return store.liveThreads.first(where: { $0.id == id })
    }

    private var activeTurnProgress: TurnProgressSummary? {
        guard let turn = activeThread?.turns.last,
              turn.status == .running || turn.status == .awaitingApproval else { return nil }
        return TurnProgressSummary(turn: turn)
    }

    /// Persistent Codex-style summary shown immediately above the queue and
    /// composer while a planned turn is running.
    @ViewBuilder
    private var turnProgressBadge: some View {
        if let progress = activeTurnProgress {
            Button {
                showTurnProgressDetails.toggle()
            } label: {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DSHTheme.brand)
                    Text("第 \(progress.currentStepNumber) / \(progress.steps.count) 步")
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(progress.changedFiles) 个文件已更改")
                    Text("+\(progress.additions)")
                        .foregroundStyle(DSHTheme.success)
                    Text("-\(progress.deletions)")
                        .foregroundStyle(DSHTheme.error)
                }
                .font(AppFont.scaled(.callout, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(DSHTheme.surfaceRaised, in: Capsule())
                .overlay(Capsule().stroke(DSHTheme.borderStrong, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("查看步骤执行进度")
            .accessibilityLabel(
                "第 \(progress.currentStepNumber) / \(progress.steps.count) 步，"
                + "\(progress.changedFiles) 个文件已更改，增加 \(progress.additions) 行，删除 \(progress.deletions) 行"
            )
            .popover(isPresented: $showTurnProgressDetails, arrowEdge: .bottom) {
                turnProgressChecklist(progress)
            }
            .frame(maxWidth: contentWidth)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func turnProgressChecklist(_ progress: TurnProgressSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(progress.steps) { step in
                HStack(alignment: .top, spacing: 10) {
                    Group {
                        switch step.status {
                        case .completed:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DSHTheme.success)
                        case .inProgress:
                            ProgressView()
                                .controlSize(.small)
                                .tint(DSHTheme.brand)
                        case .pending:
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 20, height: 20)

                    Text(step.text)
                        .font(AppFont.scaled(.callout, multiplier: appFontScale.multiplier))
                        .foregroundStyle(step.status == .completed ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(18)
        .frame(width: 440)
        .background(DSHTheme.surface)
    }

    /// Composer 底部的文本指标条：rounds · steps / LLM 时长 / 缓存命中 /
    /// 输入 tokens。圆形上下文进度条已经从这里迁出,改成输入框正下方
    /// 紧贴『完全访问权限』chip 的 `contextMeterChip`(悬停/点击弹
    /// `ModelUsagePopover`)。
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
            }
            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .frame(maxWidth: contentWidth)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// 输入框正下方 toolbar 中的圆形上下文进度条。位置紧贴权限控制；
    /// 内部仍然是 `CircularContextMeter`,hover/click 触发
    /// `ModelUsagePopover` 显示套餐 / 余额明细。
    @ViewBuilder
    private var contextMeterChip: some View {
        let lastUsage = activeThread?.turns.last(where: { $0.usage != nil })?.usage
        let avgCache = averageCacheHitPercent(thread: activeThread)
        // v0.5.37: 与侧栏/弹窗口径统一, 圆形表显示**剩余量**
        // (最差窗口的 100 - 已用)。无额度数据时退回上下文占用百分比。
        let quotaRemaining = store.rateLimits
            .flatMap { $0.worstUsedPercent }
            .map { max(0, 100 - $0) }
        let meterPercent: Int? = quotaRemaining ?? lastUsage?.contextPercent
        HStack(spacing: 4) {
            CircularContextMeter(percent: meterPercent, isActive: isRunning)
        }
        .padding(.horizontal, 3).padding(.vertical, 3)
        .help("查看模型用量与剩余额度")
        .contentShape(Rectangle())
        .onAppear { store.refreshRateLimits() }
        .onHover { hovering in
            if hovering {
                store.refreshRateLimits()
                showUsagePopover = true
            } else if !usagePopoverPinned {
                showUsagePopover = false
            }
        }
        .onTapGesture {
            showUsagePopover.toggle()
            usagePopoverPinned.toggle()
            if showUsagePopover { store.refreshRateLimits() }
        }
        .popover(isPresented: $showUsagePopover, arrowEdge: .bottom) {
            ModelUsagePopover(
                usage: lastUsage,
                averageCacheHitPercent: avgCache,
                rateLimits: store.rateLimits,
                rateLimitsLoading: store.rateLimitsLoading,
                rateLimitsError: store.rateLimitsError,
                appFontScale: appFontScale
            )
        }
        .accessibilityLabel(quotaRemaining != nil
            ? "套餐余量 \(quotaRemaining.map(String.init) ?? "未知")%"
            : "上下文用量 \(meterPercent.map(String.init) ?? "未知")%")
    }

    private func averageCacheHitPercent(thread: TapgoCore.Thread?) -> Int? {
        guard let thread else { return nil }
        return ModelUsageMetrics.averageCacheHitPercent(turns: thread.turns)
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

    /// Codex-style queue attached directly above the composer. The queue is a
    /// single quiet surface: rows update in place, keep one-line previews, and
    /// leave the primary actions aligned at the trailing edge.
    /// 队列卡片自适应高度：顶部小标题 22pt + VStack spacing 6 + 行 41pt/行 + 6pt 底部 padding，封顶 240pt 后内部滚动。
    private var queueAdaptiveHeight: CGFloat {
        let header: CGFloat = 22
        let perRow: CGFloat = 41 // 32 row content + 8 vertical padding + 1 divider
        let count = CGFloat(store.activeQueue.count)
        let natural = header + 6 + count * perRow + 6 // header + spacing + rows + bottom
        return min(natural, 240)
    }

    @ViewBuilder
    private var queueStatusBar: some View {
        if !store.activeQueue.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "tray.full.fill")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(DSHTheme.brand.opacity(0.85))
                    Text("排队中 · \(store.activeQueue.count) 条")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                        .tracking(0.4)
                    Spacer(minLength: 0)
                    Text("拖动排序 · 右键编辑")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(store.activeQueue.enumerated()), id: \.element.id) { index, q in
                            queueRow(q, index: index)
                            if index < store.activeQueue.count - 1 {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, DSHTheme.border.opacity(0.55), .clear],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(height: 1)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(height: queueAdaptiveHeight)

                if let error = store.activeQueueActionError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(DSHTheme.warn)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                }
            }
            // 队列卡片宽度 = 输入卡片宽度 (contentWidth) × 0.90,
            // 整体居中。SwiftUI HStack 默认会把卡片按行宽 proposal 撑开,
            // 这里用 0.90 倍 frame 收窄, 保持「队列卡片比输入框略窄」的层次。
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DSHTheme.bgLayer1.opacity(0.55))
                }
            )
            .overlay(
                // 底部 0.5px hairline 分隔：让卡片看上去是独立 panel，
                // 不会向下方输入框"塞背景"。品牌色 18% 让上沿更亮。
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DSHTheme.border.opacity(0.7), lineWidth: 1)
            )
            .overlay(alignment: .top) {
                // 顶部内嵌 1px 高光，替代向下投影的 shadow，
                // 避免阴影糊到下方输入框造成"塞到背后"的错觉。
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.10), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .blendMode(.plusLighter)
            }
            .frame(maxWidth: contentWidth * 0.90, alignment: .center)
            .accessibilityIdentifier("queued-message-card")
        }
    }

    /// Drag-over indicator target. `nil` = no drop hover; otherwise the
    /// id of the row currently targeted, with `.top` / `.bottom` indicating
    /// which half the cursor is over.
    @State private var dropTarget: (id: String, half: DropHalf)?
    private enum DropHalf { case top, bottom }

    @ViewBuilder
    private func queueRow(_ q: QueuedMessage, index: Int) -> some View {
        let adjusting = store.isAdjustingDirection(q.id)
        let isDropTop = dropTarget?.id == q.id && dropTarget?.half == .top
        let isDropBottom = dropTarget?.id == q.id && dropTarget?.half == .bottom
        HStack(spacing: 8) {
            Image(systemName: "arrow.turn.down.right")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(DSHTheme.brand.opacity(0.45))
                .frame(width: 18)

            if let firstImage = q.images.first {
                queueThumbnail(for: firstImage, count: q.images.count)
            }

            Text(q.text.isEmpty ? "(图片附件)" : q.text)
                .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Button {
                store.steerQueuedMessage(q.id)
            } label: {
                if adjusting {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text("调整中")
                    }
                } else {
                    Label("调整方向", systemImage: "arrow.turn.up.right")
                        .labelStyle(.iconOnly)
                        .frame(width: 22, height: 22)
                }
            }
            .buttonStyle(.borderless)
            .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
            .foregroundStyle(.secondary)
            .disabled(store.isAdjustingActiveQueue || adjusting)
            .help("立即补充到当前任务，不中断正在进行的工作")
            .accessibilityLabel(adjusting ? "正在调整方向" : "立即调整方向")

            Button {
                editingQueued = q
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(adjusting)
            .help("编辑这条排队消息的文本")
            .accessibilityLabel("编辑排队消息")

            Button {
                store.removeQueued(q.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(adjusting)
            .help("删除这条排队消息")
            .accessibilityLabel("删除排队消息")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(minHeight: 32)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if isDropTop {
                Rectangle().fill(DSHTheme.brand).frame(height: 3)
            }
        }
        .overlay(alignment: .bottom) {
            if isDropBottom {
                Rectangle().fill(DSHTheme.brand).frame(height: 3)
            }
        }
        .contextMenu {
            Button {
                editingQueued = q
            } label: {
                Label("编辑消息", systemImage: "pencil")
            }
            .disabled(adjusting)
            .help("修改这条排队消息的文本")

            Button {
                store.clearQueue()
            } label: {
                Label("关闭排队", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .disabled(adjusting)
            .help("清空当前对话的整个排队")
        }
        .draggable(q.id) {
            // Drag preview: a compact representation of the queued message.
            Text(q.text.isEmpty ? "(图片附件)" : q.text)
                .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                .lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(DSHTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
        }
        .dropDestination(for: String.self) { items, location in
            guard let draggedId = items.first, draggedId != q.id else {
                dropTarget = nil
                return false
            }
            let frameHeight: CGFloat = 44
            let half = location.y < frameHeight / 2 ? DropHalf.top : .bottom
            let targetIndex = half == .top ? index : index + 1
            store.moveQueued(draggedId, to: targetIndex)
            dropTarget = nil
            return true
        } isTargeted: { isOver in
            if isOver {
                // Probe cursor y via the next dropDestination? Without a
                // pointer-events API we approximate by toggling on enter;
                // actual half is decided inside `action` using location.y.
                if dropTarget?.id != q.id { dropTarget = (q.id, .top) }
            } else if dropTarget?.id == q.id {
                dropTarget = nil
            }
        }
        .accessibilityIdentifier("queued-message-row-\(q.id)")
    }

    @ViewBuilder
    private func queueThumbnail(for url: URL, count: Int) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DSHTheme.surface)
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DSHTheme.border, lineWidth: 1)
            )

            if count > 1 {
                Text("\(count)")
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.ultraThinMaterial, in: Capsule())
                    .offset(x: 4, y: 4)
            }
        }
        .frame(width: 36, height: 36)
        .accessibilityLabel(count == 1 ? "1 张图片" : "\(count) 张图片")
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
        // The user just spoke — land at the latest message. We bypass the
        // "isNearBottom" gate (which is async from preferences) so the new
        // user bubble always sits right above the composer, matching Codex.
        NotificationCenter.default.post(name: .tapgoRequestScrollToBottom, object: nil)
        // Keep the composer focused so the user can type the next message
        // immediately, matching Codex's always-ready input.
        focused = true
    }

    /// "插话发送全部" (Cmd/Ctrl+Enter): append the current draft to the queue
    /// (or send it immediately if idle), then drain the whole queue.
    private func interjectSend() {
        let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !store.attachedImages.isEmpty
        guard hasContent || !store.activeQueue.isEmpty else {
            // Nothing to send or interrupt.
            return
        }
        if hasContent {
            let t = text
            text = ""
            store.sendUserMessage(t)
        }
        store.interjectAndFlush()
        NotificationCenter.default.post(name: .tapgoRequestScrollToBottom, object: nil)
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
            let hasImage = pb.canReadObject(forClasses: [NSImage.self], options: nil)
            let hasFileURL = pb.canReadItem(withDataConformingToTypes: [UTType.fileURL.identifier])
            if hasImage || hasFileURL {
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
        } else if let image = NSImage(pasteboard: pb),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) {
            decodeAndAttachImage(png)
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
    /// 自进化会话必须显式覆盖——否则仍按 activeProject 显示「给 OctTapgo
    /// 发条任务…」，用户会误以为没切进自进化、把指令发去项目会话。
    private var composerPlaceholder: String {
        if activeThread?.isEvolution == true {
            return "向自进化下达本轮指令…"
        }
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

/// A native input that keeps selection and IME marked text intact while the
/// surrounding SwiftUI transcript receives high-frequency stream updates.
private struct GrowingTextEditor: View {
    @Binding var text: String
    var placeholder: String = ""
    var minHeight: CGFloat = 60
    var maxHeight: CGFloat = 150
    @FocusState.Binding var focused: Bool
    var onSubmit: () -> Void

    @State private var contentHeight: CGFloat = 36
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    private var editorHeight: CGFloat {
        max(min(contentHeight, maxHeight), minHeight)
    }

    var body: some View {
        StableComposerTextView(
            text: $text,
            font: NSFont.systemFont(
                ofSize: NSFont.systemFontSize * appFontScale.multiplier,
                weight: .regular
            ),
            wantsFocus: focused,
            onFocusChange: { focused = $0 },
            onSubmit: onSubmit,
            onHeightChange: { newValue in
                let clamped = max(min(newValue, maxHeight), minHeight)
                if abs(contentHeight - clamped) > 0.5 {
                    contentHeight = clamped
                }
            }
        )
            .frame(height: editorHeight)
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

private final class ComposerNSTextView: NSTextView {
    var onCommandReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if isReturn && flags.contains(.command) {
            onCommandReturn?()
            return
        }
        super.keyDown(with: event)
    }
}

/// Only applies external text when it really differs, and never overwrites
/// native storage during an active Chinese/Japanese/Korean IME composition.
private struct StableComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let wantsFocus: Bool
    let onFocusChange: (Bool) -> Void
    let onSubmit: () -> Void
    let onHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let editor = ComposerNSTextView()
        editor.delegate = context.coordinator
        editor.drawsBackground = false
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.font = font
        editor.textContainerInset = NSSize(width: 3, height: 4)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.string = text
        editor.onCommandReturn = onSubmit
        scrollView.documentView = editor
        context.coordinator.editor = editor

        DispatchQueue.main.async {
            context.coordinator.reportHeight()
            if wantsFocus { editor.window?.makeFirstResponder(editor) }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scrollView.documentView as? ComposerNSTextView else { return }
        editor.font = font
        editor.onCommandReturn = onSubmit

        if editor.string != text && !editor.hasMarkedText() {
            let selections = editor.selectedRanges
            editor.string = text
            let utf16Count = (text as NSString).length
            editor.selectedRanges = selections.map { value in
                let range = value.rangeValue
                let location = min(range.location, utf16Count)
                let length = min(range.length, max(0, utf16Count - location))
                return NSValue(range: NSRange(location: location, length: length))
            }
        }

        if wantsFocus && editor.window?.firstResponder !== editor {
            DispatchQueue.main.async { editor.window?.makeFirstResponder(editor) }
        }
        DispatchQueue.main.async { context.coordinator.reportHeight() }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: StableComposerTextView
        weak var editor: ComposerNSTextView?
        private var lastHeight: CGFloat = 0

        init(parent: StableComposerTextView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }

        func textDidChange(_ notification: Notification) {
            guard let editor else { return }
            if parent.text != editor.string { parent.text = editor.string }
            reportHeight()
        }

        func reportHeight() {
            guard let editor,
                  let layoutManager = editor.layoutManager,
                  let textContainer = editor.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let used = layoutManager.usedRect(for: textContainer)
            let height = ceil(used.height + editor.textContainerInset.height * 2)
            guard abs(height - lastHeight) > 0.5 else { return }
            lastHeight = height
            parent.onHeightChange(height)
        }
    }
}
