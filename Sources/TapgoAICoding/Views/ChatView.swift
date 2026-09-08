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

private struct CompactOutcomeAlert: Identifiable {
    let outcome: SessionStore.CompactOutcome
    var id: String { String(describing: outcome) }
    var title: String {
        switch outcome {
        case .empty: return "没有可 compact 的会话"
        case .busy: return "回合还在进行"
        case .compacted: return "已折叠会话"
        }
    }
    var message: String {
        switch outcome {
        case .empty:
            return "当前没有活跃会话。"
        case .busy:
            return "请先等当前回合结束再 compact。"
        case .compacted(let turns, let items):
            return "折叠了 \(turns) 个回合、\(items) 个 assistant 项。thread 元数据保留；下次发消息会从干净的 harness 上下文开始。"
        }
    }
}

private struct ModelSelectAlert: Identifiable {
    let outcome: SessionStore.ModelSelectOutcome
    var id: String { String(describing: outcome) }
    var title: String {
        switch outcome {
        case .empty: return "请输入模型名"
        case .notFound: return "未找到匹配的模型"
        case .ambiguous: return "匹配到多个模型"
        case .selected: return "已切换模型"
        case .notConfigured: return "模型未配置"
        }
    }
    var message: String {
        switch outcome {
        case .empty:
            return "用法：/model <provider::model 或 显示名片段>"
        case .notFound(let q):
            return "未找到包含 \"" + q + "\" 的模型。请到 设置 → 模型 确认注册表。"
        case .ambiguous(let hits):
            return ("命中多个模型，请用更精确的 provider::model 切换：\n" + hits.joined(separator: "、"))
        case .selected(let provider, let model):
            return "下一个新会话将使用 \(provider) · \(model)。当前在跑的回合沿用旧模型。"
        case .notConfigured(let provider, let model):
            return "\(provider) · \(model) 已注册但尚未配置 API Key。请到 设置 → 模型 → \(provider) 填入。"
        }
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
    @State private var showShortcuts = false
    @State private var streamScrollCoalescer = StreamScrollCoalescer()
    @AppStorage("tapgo.wideContent") private var wideContent = false
    @AppStorage("tapgo.fontScale") private var fontScale = "medium"
    /// Global toggle for the ZCode-style "工作过程" work log (thinking,
    /// terminal, file edit, file read cards inside a turn). Default off
    /// because the per-row stream drowned the actual answer for users who
    /// do not care about the agent's internal mechanics. The chip +
    /// summary bar still appear; only the per-event rows hide.
    /// The global flag controls automatic expansion; per-turn disclosure
    /// never mutates the persisted preference. Turning it off collapses all.
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
                CodexWelcomeView(contentWidth: wideContent ? 956 : 736)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Keep the same native text view when a new task becomes a chat.
            ComposerView(contentWidth: wideContent ? 980 : 760, isWelcome: !hasConversation)
                .frame(maxWidth: .infinity)

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
                RemoteProjectBanner(project: project, host: workspace.remoteHost(byId: project.remoteHostId ?? ""))
            }
            if thread.isEvolution {
                EvolutionPanel(thread: thread) { showEvolutionLog = true }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: wideContent ? 980 : 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(GeometryReader { g in
                        Color.clear.preference(
                            key: ChatContentBottomKey.self,
                            value: g.frame(in: .named("chat")).maxY
                        )
                    })
                }
                // 打开会话直接从底部开始布局。此前靠 scrollChatToBottom 延迟
                // scrollTo("BOTTOM")，而 LazyVStack 对未实例化的目标行只能从
                // 当前位置沿途布局找过去——大会话（数百轮、超长消息/表格）会
                // 被一次性全量布局，主线程卡死数秒到数十秒。原生底部锚定让
                // LazyVStack 第一帧就只布局底部可视区。
                .defaultScrollAnchor(.bottom)
                .coordinateSpace(name: "chat")
                .onReceive(NotificationCenter.default.publisher(for: .tapgoJumpToTurn)) { note in
                    if let id = note.object as? String {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
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
                    // @State 的 setter 不做值比较：无脑回写会让"布局 → preference
                    // 回调 → 标脏 → 再布局"无限循环（滚动到内容中间时主线程被
                    // 打满、整个 App 卡死）。只有跨过阈值才真正更新状态。
                    let near = bottom <= viewportHeight + 120
                    if near != isNearBottom { isNearBottom = near }
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
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
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
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
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
            // 动画滚动会沿途布局 LazyVStack 的全部行（大会话数百条），直接
            // 跳转只布局目标区，打开会话/新消息定位不再卡顿。
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
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

    @ViewBuilder
    private func turnSection(turn: Turn, isLast: Bool = false) -> some View {
        let isRunning = turn.status == .running || turn.status == .awaitingApproval
        let presentation = TurnResponsePresentation(turn)
        let fileChanges = turn.items.compactMap { item -> FileChange? in
            guard case .fileChange(let change) = item else { return nil }
            return change
        }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(presentation.users) { item in
                renderBlock(.item(item), turn: turn)
            }
            ConversationResponseView(turn: turn, showWorkProcess: showWorkProcess) {
                ForEach(presentation.notices) { item in
                    renderBlock(.item(item), turn: turn)
                }
            }
            .padding(.top, 12)
            if !isRunning, !fileChanges.isEmpty {
                FileEditBatchView(files: fileChanges).padding(.top, 6)
            }
            if turn.status == .completed || turn.status == .failed || turn.status == .interrupted {
                // Copy the answer, keeping diagnostics in explicit full export.
                HStack(spacing: 10) {
                    CopyIconButton(text: TurnMarkdown.response(turn), help: "复制回复")
                        .disabled(presentation.answerText.isEmpty)
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
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: TurnPresentationBlock, turn: Turn) -> some View {
        switch block {
        case .item(let item):
            MessageRow(item: item,
                       isRunning: turn.status == .running && turn.items.last?.id == item.id,
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
            if turn.status == .running {
                // ZCode 参考样式：运行中的文件改动是安静的「正在编辑」行，
                // 结束后才折叠成带审核按钮的批次卡。
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(files) { file in
                        FileChangeRowView(change: file)
                    }
                }
            } else {
                FileEditBatchView(files: files)
            }
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
            Text("保存目标后，点击“开始”执行。")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.tertiary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { store.setActiveThreadGoal(t) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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


struct ComposerView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var workspace: WorkspaceStore
    var contentWidth: CGFloat = 760
    var isWelcome = false
    @State private var preserveDraftOnProjectChange = false

    /// 静态菜单项定义（标题 + SF Symbol 图标 + 副标题描述）— 让 + 菜单
    /// 在视觉上与 Codex 桌面端对齐：每个命令带一行描述，插件分组使用
    /// 本地描述。等 Codex 插件目录接入后把 plugins 换成动态加载的
    /// `PluginCatalogItem` 列表。
    private struct AddMenuItem: Identifiable {
        let id: String
        let title: String
        let icon: String
        let detail: String
        let action: AddMenuAction
    }
    private enum AddMenuAction {
        case attachFiles
        case attachTapgoProject
        case setGoal
        case togglePlanMode
        case openRecordSkillSettings
        case insertSkill(String)
        case insertPlugin(name: String, detail: String)
    }
    private static let addMenuItems: [AddMenuItem] = [
        .init(id: "files", title: "文件和文件夹", icon: "paperclip",
              detail: "附加本地文件、文件夹或图片到会话",
              action: .attachFiles),
        .init(id: "tapgo", title: "附加 Tapgo AICoding", icon: "plus.app",
              detail: "把当前项目文件夹挂载到会话上下文",
              action: .attachTapgoProject),
        .init(id: "goal", title: "目标", icon: "target",
              detail: "设置要持续追求的目标",
              action: .setGoal),
        .init(id: "plan", title: "计划模式", icon: "lightbulb",
              detail: "启用计划模式：下一条消息只给方案不执行工具",
              action: .togglePlanMode),
        .init(id: "record", title: "录制技能", icon: "record.circle",
              detail: "录制可重放的操作序列并保存为技能",
              action: .openRecordSkillSettings),
    ]
    private static let addMenuPlugins: [AddMenuItem] = [
        .init(id: "skill:terminal", title: "终端执行", icon: "terminal",
              detail: "在主机上运行命令并读取输出", action: .insertSkill("终端执行")),
        .init(id: "skill:file", title: "文件读写", icon: "doc",
              detail: "读取与修改项目文件", action: .insertSkill("文件读写")),
        .init(id: "skill:web", title: "网络搜索", icon: "globe",
              detail: "从互联网检索最新信息", action: .insertSkill("网络搜索")),
        .init(id: "skill:mcp", title: "MCP 工具", icon: "cube",
              detail: "连接模型上下文协议服务器", action: .insertSkill("MCP 工具")),
        .init(id: "skill:book", title: "技能", icon: "book",
              detail: "按需加载的专项能力", action: .insertSkill("技能")),
    ]

    /// Codex 插件目录里 installed+enabled 的条目（v0.5.142 切到实时）。
    /// 加载失败或为空时 `composerAddMenu` 回落显示 `addMenuPlugins`。
    @State private var pluginCatalogEntries: [PluginCatalogItem] = []
    private static let codexPluginLoadFailed = false

    /// Codex 插件名 → SF Symbol 图标的静态映射（`PluginCatalogItem`
    /// 没有 icon 字段，用人维护一份常用映射，未知走 `puzzlepiece.extension`）。
    private static func pluginIcon(for item: PluginCatalogItem) -> String {
        let key = item.name.lowercased()
        if key.contains("github") { return "chevron.left.forwardslash.chevron.right" }
        if key.contains("cloudflare") { return "cloud.fill" }
        if key.contains("figma") { return "paintbrush.fill" }
        if key.contains("gmail") || key.contains("mail") { return "envelope.fill" }
        if key.contains("slack") { return "bubble.left.fill" }
        if key.contains("notion") { return "doc.text.fill" }
        if item.capabilities.contains(where: { $0.lowercased().contains("mcp") }) { return "cube" }
        return "puzzlepiece.extension"
    }

    /// Codex desktop parity: composer "+" 按钮弹出的下拉菜单。结构
    /// 模拟截图：标题"添加"、分组（文件 / 附件 / 目标 / 计划 / 录制 /
    /// 插件），每项带"标题 + 副标题"双行。
    @ViewBuilder
    private var composerAddMenu: some View {
        Menu {
            Text("添加")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
            ForEach(Self.addMenuItems) { item in
                Button {
                    runAddMenuAction(item.action)
                } label: {
                    composerAddMenuRow(icon: item.icon, title: item.title, detail: item.detail)
                }
            }
            Divider()
            Text("插件")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
            if !pluginCatalogEntries.isEmpty {
                ForEach(pluginCatalogEntries, id: \.id) { item in
                    Button {
                        runAddMenuAction(.insertPlugin(
                            name: item.displayName,
                            detail: item.summary.isEmpty ? "Codex 官方插件" : item.summary))
                    } label: {
                        composerAddMenuRow(
                            icon: Self.pluginIcon(for: item),
                            title: item.displayName,
                            detail: item.summary.isEmpty ? "Codex 官方插件" : item.summary)
                    }
                }
            } else {
                ForEach(Self.addMenuPlugins) { item in
                    Button {
                        runAddMenuAction(item.action)
                    } label: {
                        composerAddMenuRow(icon: item.icon, title: item.title, detail: item.detail)
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("添加")
        .accessibilityLabel("添加（文件/附件/插件/目标/计划）")
    }

    /// Codex desktop parity: + 菜单里每个命令的"图标 + 标题 + 描述"双行
    /// 行内布局。`Label` 默认只一行，这里换成 HStack+VStack 让菜单项在
    /// 视觉上和截图一致（描述字体小、secondary 颜色）。
    @ViewBuilder
    private func composerAddMenuRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 16, alignment: .center)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppFont.scaled(.body, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func runAddMenuAction(_ action: AddMenuAction) {
        switch action {
        case .attachFiles:
            pickImages()
        case .attachTapgoProject:
            NotificationCenter.default.post(name: .tapgoAttachTapgo, object: nil)
        case .setGoal:
            editingGoalItem = GoalEditItem(text: store.liveThreads
                .first(where: { $0.id == store.activeThreadId })?.goal ?? "")
        case .togglePlanMode:
            planningMode.toggle()
        case .openRecordSkillSettings:
            NotificationCenter.default.post(
                name: .tapgoRequestOpenSettings,
                object: SettingsView.Tab.computer.rawValue
            )
        case .insertSkill(let name):
            NotificationCenter.default.post(name: .tapgoInsertSkill, object: name)
        case .insertPlugin(let name, _):
            NotificationCenter.default.post(name: .tapgoInsertSkill, object: name)
        }
    }

    /// 异步加载 Codex 插件目录，筛选 installed + enabled。失败静默，
    /// `pluginCatalogEntries` 保持空数组让菜单回落显示本地静态项。
    /// 异步加载 Tapgo 插件目录，筛选 marketplace == .codex 且 installed + enabled。
    /// 失败静默，`pluginCatalogEntries` 保持空数组让菜单回落显示本地静态项。
    private func loadInstalledPlugins() async {
        let service = PluginManagerService()
        do {
            let all = try await service.loadCatalog()
            pluginCatalogEntries = all.filter { $0.marketplace == .codex && $0.installed && $0.enabled }
        } catch {
            pluginCatalogEntries = []
        }
    }

    @State private var pendingDraftProjectID: String?
    @State private var choosingWelcomeProject = false
    @State private var choosingPermission = false
    /// 与 ChatView 同 key 的本地镜像：切换模型菜单用高亮当前模型。
    @AppStorage(TapgoConfig.selectedModelKey) private var selectedModelRaw =
        "builtin:\(TapgoModel.minimaxM3.rawValue)"
    @AppStorage("tapgo.planningMode") private var planningMode = false
    /// 常驻 Plan mode：开启后发消息不清除（默认关闭 → single-shot 行为）
    @AppStorage("tapgo.planModePersistent") private var planModePersistent: Bool = false
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
    @State private var modelSelectAlert: ModelSelectAlert?
    @State private var compactOutcomeAlert: CompactOutcomeAlert?
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
            if planningMode {
                PlanModeBanner(
                    // v0.5.149 修：persistent 模式下 X 按钮不再绕开关 planMode。
                    // 之前 `if !planModePersistent { planningMode = false }` 在
                    // persistent=true 时跳过，导致 banner 永远不消失（render
                    // 条件仍是 `if planningMode`）。X 按钮 = 关 plan mode，
                    // persistent 模式下用户点 X 即"主动关"，符合常驻语义。
                    onDismiss: {
                        planningMode = false
                        NotificationCenter.default.post(name: .tapgoPlanModeBannerDidDismiss, object: nil)
                    },
                    isPersistent: planModePersistent
                )
            }
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
            VStack(spacing: isWelcome ? -12 : (store.activeQueue.isEmpty ? 0 : -25)) {
                if isWelcome { welcomeProjectBar }
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
                .alert(item: $modelSelectAlert) { item in
                    Alert(title: Text(item.title),
                          message: Text(item.message),
                          dismissButton: .default(Text("好")))
                }
                .alert(item: $compactOutcomeAlert) { item in
                    Alert(title: Text(item.title),
                          message: Text(item.message),
                          dismissButton: .default(Text("好")))
                }

                HStack(spacing: 8) {
                    // Codex desktop parity: the "+" button opens a dropdown
                    // titled "添加" with grouped actions (files, Tapgo,
                    // 目标 / 计划 / 录制 / 插件). Each action maps to either
                    // a local command or a Tapgo capability.
                    composerAddMenu

                    if !isWelcome {
                        existingProjectChip
                    }

                    environmentChip

                    // v0.5.146: 移除底部 Plan toggle 按钮 — Codex 桌面端底部只有
                    // `+` / `🛡 完全访问` / 模型 / 发送，Plan mode 入口只在 + 菜单里。
                    // 用户已经可以从 + 菜单的"计划模式"项开启 Plan mode。

                    if !isWelcome {
                        if computerUseShowInComposer { computerControlChip }
                        contextMeterChip
                    }

                    Spacer()

                    if !isWelcome {
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

                    }

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
                                .foregroundStyle(.white)
                                // v0.5.144 修：brandPrimary 是「主前景色」不是品牌蓝，
                                // dark 模式下近白 → stop 按钮变成白色圆。改用 brand 蓝。
                                .background(DSHTheme.brand, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("中断当前任务（排队消息会被保留）")
                        .accessibilityLabel("中断当前任务")
                    }
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(DSHTheme.composerActionText)
                            .background(DSHTheme.composerAction, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(canSend ? 1 : 0.32)
                    .disabled(canSend == false)
                    .help(isRunning ? "发送（排队）(⌘↩)" : "发送 (⌘↩)")
                    .accessibilityLabel(L10n.sendButton)
                }
            }
            .padding(12)
            .background(DSHTheme.composerSurface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isDropTargeted ? DSHTheme.brand : (focused ? DSHTheme.borderStrong : DSHTheme.border), lineWidth: isDropTargeted ? 2 : 0.5)
            )
            .frame(maxWidth: contentWidth)
            .frame(maxWidth: .infinity, alignment: .center)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
                acceptDroppedImages(providers)
            }
            .onPasteCommand(of: [.fileURL, .image]) { providers in
                handlePaste(providers)
            }
            .onReceive(NotificationCenter.default.publisher(for: .tapgoMcpStatus)) { _ in
                _ = store.mcpStatusSummary()
                NotificationCenter.default.post(name: .tapgoOpenCommandPalette, object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: .tapgoSideChat)) { _ in
                store.spawnSideChat()
            }
            .onReceive(NotificationCenter.default.publisher(for: .tapgoArchiveEmpty)) { _ in
                store.archiveActiveThread()
            }
            .onReceive(NotificationCenter.default.publisher(for: .tapgoPinEmpty)) { _ in
                if let id = store.activeThreadId { store.togglePinned(id) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tapgoTogglePlanMode)) { _ in
                planningMode.toggle()
            }
            .zIndex(1)
            }

        }
        .frame(maxWidth: contentWidth, alignment: .center)
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
        .onReceive(NotificationCenter.default.publisher(for: .tapgoOpenGoalEditor)) { _ in
            editingGoalItem = GoalEditItem(text: "")
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .tapgoInsertStarter)) { note in
            guard isWelcome, let prompt = note.object as? String else { return }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? prompt : text + "\n\n" + prompt
            focused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapgoChooseStarterProject)) { note in
            guard isWelcome else { return }
            chooseNewTaskProject(note.object as? String)
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
        .onChange(of: workspace.state.activeProjectId) { _, newID in
            // Explicit new-task destination changes retain the editable draft.
            // Navigating the sidebar to another conversation still clears it.
            if !(preserveDraftOnProjectChange && newID == pendingDraftProjectID) { text = "" }
            preserveDraftOnProjectChange = false
        }
        .onChange(of: store.activeThreadId) { _, _ in
            showTurnProgressDetails = false
        }
        .onChange(of: isRunning) { _, running in
            if !running { showTurnProgressDetails = false }
        }
        .onAppear(perform: handleComposerAppear)
        .onDisappear(perform: handleComposerDisappear)
        .sheet(item: $editingGoalItem) { item in
            GoalEditorSheet(initial: item.text)
        }
        .sheet(item: $editingQueued) { item in
            QueuedMessageEditor(item: item)
        }
    }

    /// 拆出 onAppear 让 Swift type-checker 不超时（v0.5.141 修）。
    private func handleComposerAppear() {
        // On launch with a restored thread, put the cursor in the
        // composer so the user can start typing immediately.
        if store.activeThreadId != nil { focused = true }
        setUpPasteMonitor()
        // 后台拉 Codex 插件目录。失败静默（菜单回落本地静态项）。
        Task { await loadInstalledPlugins() }
    }

    /// 拆出 onDisappear 让 Swift type-checker 不超时（v0.5.141 修）：
    /// 多语句闭包 + body 后端大量 onReceive 触发了 O(n²) 推断。
    private func handleComposerDisappear() {
        draftSaver.flush(text)
        if let m = pasteMonitor { NSEvent.removeMonitor(m); pasteMonitor = nil }
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
    private var existingProjectChip: some View {
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

    }

    private var welcomeProjectBar: some View {
        Button { choosingWelcomeProject = true } label: {
            HStack(spacing: 7) {
                Image(systemName: workspace.state.activeProject?.isRemote == true ? "globe" : "folder")
                Text(workspace.state.activeProject?.displayName ?? "选择项目")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 9))
            }
            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
            .foregroundStyle(DSHTheme.labelDim)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSHTheme.composerProjectSurface, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $choosingWelcomeProject) {
            WelcomeProjectPicker { id in
                choosingWelcomeProject = false
                chooseNewTaskProject(id)
            }
        }
        .help(workspace.state.activeProject?.displayPath ?? "选择新任务的工作目录")
        .accessibilityLabel("新任务项目：\(workspace.state.activeProject?.displayName ?? "未选择")")
        .padding(.horizontal, 12)
    }

    private func chooseNewTaskProject(_ id: String?) {
        preserveDraftOnProjectChange = true
        pendingDraftProjectID = id
        store.selectProjectForNewTask(id)
        focused = true
    }

    @ViewBuilder
    /// One "运行环境" chip that bundles the sandbox mode and the approval
    /// policy (previously two separate chips), so the composer footer stays
    /// compact. Both are quick-switch menus persisted to settings.
    /// One permission selector with Codex's three clear tiers. Each tier
    /// sets both the sandbox mode and the approval policy together, keeping
    /// the composer footer to a single, understandable control.
    private var environmentChip: some View {
        Button { choosingPermission = true } label: {
            HStack(spacing: 4) {
                Image(systemName: currentPermission.icon).font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                Text(currentPermission.id == PermissionChoice.full.id ? "完全访问" : currentPermission.title).font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
            }
            .foregroundStyle(currentPermission.id == PermissionChoice.full.id ? DSHTheme.warn : DSHTheme.labelDim)
            .padding(.horizontal, 3).padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $choosingPermission) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(PermissionChoice.all) { c in
                    Button {
                        sandboxRaw = c.sandbox
                        approvalPolicyRaw = c.approval
                        choosingPermission = false
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
                        .padding(8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .frame(width: 320)
        }
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
        if let progress = activeTurnProgress, let turn = activeThread?.turns.last {
            Button { showTurnProgressDetails.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "checklist")
                    Text("\(progress.completedSteps)/\(progress.steps.count) 已完成")
                    if let step = progress.steps.first(where: { $0.status == .inProgress }) {
                        Text(step.text).lineLimit(1).truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up").font(.system(size: 9))
                }
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(DSHTheme.labelDim)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看执行清单，已完成 \(progress.completedSteps) 项，共 \(progress.steps.count) 项")
            .popover(isPresented: $showTurnProgressDetails, arrowEdge: .bottom) {
                ScrollView { TaskPlanSteps(progress: progress, status: turn.status).padding(16) }
                    .frame(width: 400, height: min(360, CGFloat(progress.steps.count) * 58 + 32))
            }
            .frame(maxWidth: contentWidth)
            .frame(maxWidth: .infinity)
        }
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
    @ViewBuilder
    private var queueStatusBar: some View {
        if !store.activeQueue.isEmpty {
            TaskQueueCard(count: store.activeQueue.count, error: store.activeQueueActionError) {
                VStack(spacing: 0) {
                    ForEach(Array(store.activeQueue.enumerated()), id: \.element.id) { index, q in
                        queueRow(q, index: index)
                        if index < store.activeQueue.count - 1 { Divider().padding(.horizontal, 12) }
                    }
                }
            }
            .frame(maxWidth: contentWidth - 24)
            .frame(maxWidth: .infinity)
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
                .lineLimit(2)
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
        .frame(minHeight: 44)
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
                Label("清空排队消息", systemImage: "text.line.first.and.arrowtriangle.forward")
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
            let frameHeight: CGFloat = 52
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
    /// queued instead of dropped. When the user has Plan mode toggled on
    /// (Codex desktop parity), prepend a directive telling Codex to plan
    /// first and skip tool calls so the user can review the approach
    /// before any side effects run.
    private func send() {
        if handleLocalCommand() { return }
        let t = text
        guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !store.attachedImages.isEmpty else { return }
        text = ""
        let payload: String
        if planningMode {
            payload = "[计划模式] 请先给方案（Markdown：步骤 / 风险 / 验证），不要执行任何工具调用。\n\n" + t
        } else {
            payload = t
        }
        // v0.5.147: 从 composer 文本里扫 @DisplayName，匹配 pluginCatalogEntries
        // 后把 installSpecifier 收集传给 harness — Codex app-server 会把
        // 这些 MCP server 在本 thread 内激活，harness 直接调对应 tool。
        let enabledMcpServers = enabledMcpServersFromText(t)
        store.sendUserMessage(payload, planMode: planningMode, enabledMcpServers: enabledMcpServers)
        if !planModePersistent {
            planningMode = false  // single-shot: turn off after the plan is sent
        }
        // The user just spoke — land at the latest message. We bypass the
        // "isNearBottom" gate (which is async from preferences) so the new
        // user bubble always sits right above the composer, matching Codex.
        NotificationCenter.default.post(name: .tapgoRequestScrollToBottom, object: nil)
        // Keep the composer focused so the user can type the next message
        // immediately, matching Codex's always-ready input.
        focused = true
    }

    /// v0.5.147: 从 composer 文本里扫 `@DisplayName`，匹配 pluginCatalogEntries
    /// 的 displayName（不区分大小写）。匹配到的 installSpecifier 传给
    /// harness 作为 thread-level enabledMcpServers 激活 Codex 插件。
    private func enabledMcpServersFromText(_ text: String) -> [String] {
        let displayNames = Set(pluginCatalogEntries.map { $0.displayName.lowercased() })
        guard !displayNames.isEmpty else { return [] }
        var hits: [String] = []
        var seen: Set<String> = []
        for token in text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            guard token.hasPrefix("@"), token.count > 1 else { continue }
            let name = String(token.dropFirst()).lowercased()
            guard displayNames.contains(name) else { continue }
            guard let item = pluginCatalogEntries.first(where: { $0.displayName.lowercased() == name })
            else { continue }
            if seen.insert(item.installSpecifier).inserted {
                hits.append(item.installSpecifier)
            }
        }
        return hits
    }

    /// "插话发送全部" (Cmd/Ctrl+Enter): append the current draft to the queue
    /// (or send it immediately if idle), then drain the whole queue.
    private func interjectSend() {
        if handleLocalCommand() { return }
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

    /// Shared before every submission path, including the global shortcut.
    private func handleLocalCommand() -> Bool {
        guard let command = ComposerLocalCommand.parse(text) else { return false }
        switch command {
        case .goal(let goal):
            if goal.isEmpty { editingGoalItem = GoalEditItem(text: "") }
            else { store.setActiveThreadGoal(goal) }
        case .newTask:
            store.newThread()
        case .clear:
            store.clearActiveThread()
        case .model(let query):
            let outcome = store.selectModel(matching: query)
            modelSelectAlert = ModelSelectAlert(outcome: outcome)
        case .initProject:
            store.startInitProjectThread()
        case .compact:
            let outcome = store.compactActiveThread()
            compactOutcomeAlert = CompactOutcomeAlert(outcome: outcome)
        case .review(let scope):
            store.startReviewThread(scope: scope)
        }
        text = ""
        showSlashMenu = false
        focused = true
        return true
    }

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
            slashRow("/clear", "清空当前会话") {
                store.clearActiveThread()
                text = ""
                showSlashMenu = false
                focused = true
            }
            slashRow("/model", "切换模型（如 /model MiniMax M3）") {
                text = "/model "
                focused = true
            }
            slashRow("/init", "打开 AGENTS.md 起草会话") {
                store.startInitProjectThread()
                text = ""
                showSlashMenu = false
                focused = true
            }
            slashRow("/compact", "折叠当前会话历史（下次发消息从干净上下文）") {
                let outcome = store.compactActiveThread()
                compactOutcomeAlert = CompactOutcomeAlert(outcome: outcome)
                text = ""
                showSlashMenu = false
                focused = true
            }
            slashRow("/review [scope]", "打开 diff 审查会话（scope: working/staged/main/<ref>）") {
                text = "/review "
                focused = true
            }
            Text("输入 /goal 后加目标文字，回车设置；输入 /clear 清空当前会话；输入 /model 后加模型名/显示名/provider::model 切换；输入 /init 打开起草 AGENTS.md 的会话；输入 /compact 折叠当前会话历史；输入 /review [scope] 打开 diff 审查会话。")
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

    /// Composer placeholder — Codex 桌面端对齐。Codex 桌面端 placeholder
    /// 是 "添加文件等内容 @ 人/项目" 提示 composer 可以做什么。
    /// TapgoAICoding 不支持 @ 人/@ 项目但支持 @ 插件（v0.5.147），
    /// 所以 hint 改 "发消息 / 添加文件 / @ 插件"，更贴近实际能力。
    /// 自进化会话必须显式覆盖——否则仍按 activeProject 显示「给 OctTapgo
    /// 发条任务…」，用户会误以为没切进自进化、把指令发去项目会话。
    private var composerPlaceholder: String {
        if activeThread?.isEvolution == true {
            return "向自进化下达本轮指令…"
        }
        return "发消息 / 添加文件 / @ 插件"
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
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                TaskGoalCard(goal: goal, status: thread.goalStatus,
                             elapsed: goalElapsedText(store.goalElapsedSeconds(thread)),
                             hasStarted: thread.goalWorkedSeconds > 0 || thread.goalResumedAt != nil,
                             canStart: !store.isRunning && store.setupError == nil,
                             onPause: { store.pauseGoal() }, onStart: { store.startGoal() },
                             onEdit: { editingGoalItem = GoalEditItem(text: goal) },
                             onRemove: { store.setActiveThreadGoal(nil) })
                    .id(thread.id)
            }
            .frame(maxWidth: contentWidth - 24)
            .frame(maxWidth: .infinity)
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


/// Plan mode 视觉提示 — 在 composer 顶部显示蓝色 banner，提示
/// 当前会话已开启 Plan mode，下一条消息会自动加 [计划模式] 指令
/// 前缀让 Codex 先出方案不执行工具。Codex 桌面端同样在 composer 顶部
/// 显示类似提示。
struct PlanModeBanner: View {
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale
    /// 点 X 关闭 banner（single-shot 模式时同时关 planMode；persistent 模式时仅 dismiss banner）
    var onDismiss: () -> Void
    /// 是否常驻 Plan mode（关闭 banner 不重置 planMode）
    var isPersistent: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.white)
            Text(isPersistent ? "Plan mode（常驻）" : "Plan mode 已开启")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.white)
                .bold()
            // v0.5.150: 副文从 28 字符精简到 10 字符，避免 banner 过高。完整说明放 help tooltip。
            Text("先出方案不执行工具")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("关闭 Plan mode 提示")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // v0.5.144 修：之前用 brandPrimary（dark 模式下近白色），banner 变成白条。
        // brandPrimary 是「主前景色」不是品牌蓝。正确的蓝色是 brand。
        .background(DSHTheme.brand, in: RoundedRectangle(cornerRadius: 6))
        // v0.5.150: 把完整说明放进 tooltip，避免 banner 文本过长。
        .help(isPersistent
              ? "Plan mode 常驻：所有消息都会让 Codex 先出方案不执行工具"
              : "Plan mode：下一条消息会让 Codex 先出方案不执行工具")
    }
}
