import AppKit
import SwiftUI
import TapgoCore
import WebKit

/// ZCode-style trailing workbench. It is a real split pane, not an overlay:
/// chat and workbench keep independent widths, tabs have their own lifecycle,
/// and the environment drawer is a second trailing pane.
struct RightWorkbenchView: View {
    @EnvironmentObject private var store: SessionStore
    let thread: TapgoCore.Thread
    @Binding var requestedKind: WorkbenchLayoutState.TabKind?
    /// Set true by the chat|workbench divider gesture when the user drags the
    /// workbench wide; this view consumes it and reveals the drawer.
    @Binding var requestEnvironmentReveal: Bool
    let closePanel: () -> Void

    @AppStorage("tapgo.workbench.layout") private var persistedLayout = ""
    @AppStorage("tapgo.workbench.width") private var workbenchWidth = 430.0
    @AppStorage("tapgo.workbench.environmentWidth") private var environmentWidth = 310.0
    @State private var layout = WorkbenchLayoutState.default
    @State private var didRestore = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                tabBar
                Divider()
                tabContents
            }
            .frame(minWidth: 340, idealWidth: CGFloat(workbenchWidth), maxWidth: 820)
            .background(DSHTheme.bg)
            .background(widthReader(for: .workbench))

            if layout.isEnvironmentVisible {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Label("环境信息", systemImage: "info.circle")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button {
                            layout.isEnvironmentVisible = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .help("关闭环境信息")
                        .accessibilityLabel("关闭环境信息")
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 37)
                    .background(DSHTheme.titlebarBg)
                    Divider()
                    ScrollView {
                        EnvironmentPanel(thread: thread)
                            .padding(12)
                    }
                }
                .frame(minWidth: 250, idealWidth: CGFloat(environmentWidth), maxWidth: 460)
                .background(DSHTheme.moduleBg)
                .background(widthReader(for: .environment))
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .accessibilityIdentifier("workbench-environment-drawer")
            }
        }
        .frame(
            minWidth: layout.isEnvironmentVisible ? 590 : 340,
            idealWidth: layout.isEnvironmentVisible
                ? CGFloat(workbenchWidth + environmentWidth)
                : CGFloat(workbenchWidth),
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .overlay(alignment: .trailing) {
            if !layout.isEnvironmentVisible {
                environmentRevealHandle
            }
        }
        .onAppear(perform: restore)
        .onChange(of: layout) { _, _ in persist() }
        .onChange(of: layout.isEnvironmentVisible) { _, isVisible in
            if isVisible { ensureHostWindowFitsEnvironment() }
        }
        .onChange(of: requestedKind) { _, kind in
            guard let kind else { return }
            focusOrOpen(kind)
            requestedKind = nil
        }
        .onChange(of: requestEnvironmentReveal) { _, requested in
            guard requested else { return }
            layout.isEnvironmentVisible = true
            requestEnvironmentReveal = false
        }
        .animation(.easeOut(duration: 0.16), value: layout.isEnvironmentVisible)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(layout.tabs) { tab in
                    Button {
                        layout.select(tab.id)
                    } label: {
                        Label(tab.title, systemImage: icon(for: tab.kind))
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)
            .help("搜索标签页")
            .accessibilityLabel("搜索标签页")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(layout.tabs) { tab in
                        workbenchTab(tab)
                    }
                }
            }

            Menu {
                addTabButton(.assistant)
                addTabButton(.review)
                addTabButton(.terminal)
                addTabButton(.browser)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 30)
            }
            .menuStyle(.borderlessButton)
            .help("新增标签")
            .accessibilityLabel("新增标签")

            Button {
                layout.isEnvironmentVisible.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .frame(width: 28, height: 30)
            }
            .buttonStyle(.borderless)
            .help(layout.isEnvironmentVisible ? "收起环境信息" : "展开环境信息")
            .accessibilityLabel(layout.isEnvironmentVisible ? "收起环境信息" : "展开环境信息")

            Menu {
                if let selected = layout.selectedTabID {
                    Button("关闭其他标签") {
                        closeOtherTabs(keeping: selected)
                    }
                    .disabled(hasRunningAuxiliary(excluding: selected))
                }
                Button("恢复默认布局") {
                    removeAuxiliaryThreads(in: layout.tabs)
                    layout = .default
                    workbenchWidth = 430
                    environmentWidth = 310
                }
                .disabled(hasRunningAuxiliary(excluding: nil))
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 30)
            }
            .menuStyle(.borderlessButton)
            .help("更多")
            .accessibilityLabel("更多工作台操作")

            Button(action: closePanel) {
                Image(systemName: "sidebar.trailing")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            .help("收起侧边面板")
            .accessibilityLabel("收起侧边面板")
        }
        .padding(.horizontal, 4)
        .frame(height: 37)
        .background(DSHTheme.titlebarBg)
    }

    private func workbenchTab(_ tab: WorkbenchLayoutState.Tab) -> some View {
        let selected = layout.selectedTabID == tab.id
        return HStack(spacing: 5) {
            Button {
                layout.select(tab.id)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: icon(for: tab.kind))
                    Text(tab.title).lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(selected ? .primary : .secondary)
                .padding(.leading, 8)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            Button {
                closeWorkbenchTab(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 22)
            }
            .buttonStyle(.plain)
            .help("关闭 \(tab.title)")
            .accessibilityLabel("关闭 \(tab.title)")
            .disabled(isRunningAuxiliary(tab))
        }
        .padding(.trailing, 5)
        .background(selected ? DSHTheme.surfaceRaised : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(selected ? DSHTheme.brand : Color.clear)
                .frame(height: 2)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var tabContents: some View {
        if layout.tabs.isEmpty {
            ContentUnavailableView {
                Label("侧边工作台", systemImage: "sidebar.trailing")
            } description: {
                Text("使用上方 + 新建审查、终端、浏览器或辅助对话。")
            } actions: {
                Button("打开审查") { _ = layout.open(.review) }
            }
        } else {
            ZStack {
                ForEach(layout.tabs) { tab in
                    tabContent(tab)
                        .opacity(layout.selectedTabID == tab.id ? 1 : 0)
                        .allowsHitTesting(layout.selectedTabID == tab.id)
                        .accessibilityHidden(layout.selectedTabID != tab.id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: WorkbenchLayoutState.Tab) -> some View {
        switch tab.kind {
        case .assistant:
            WorkbenchAuxiliaryConversation(tabID: tab.id, threadID: tab.linkedThreadID)
        case .review:
            WorkbenchReview(thread: thread)
        case .terminal:
            WorkbenchTerminal(tabID: tab.id, cwd: thread.cwd)
        case .browser:
            WorkbenchBrowser()
        }
    }

    private func addTabButton(_ kind: WorkbenchLayoutState.TabKind) -> some View {
        Button {
            _ = openWorkbenchTab(kind)
        } label: {
            Label(addLabel(for: kind), systemImage: icon(for: kind))
        }
    }

    private func addLabel(for kind: WorkbenchLayoutState.TabKind) -> String {
        switch kind {
        case .assistant: return "新建辅助对话"
        case .review: return "打开审查"
        case .terminal: return "新建终端"
        case .browser: return "打开浏览器"
        }
    }

    private func icon(for kind: WorkbenchLayoutState.TabKind) -> String {
        switch kind {
        case .assistant: return "bubble.left.and.bubble.right"
        case .review: return "doc.text.magnifyingglass"
        case .terminal: return "terminal"
        case .browser: return "globe"
        }
    }

    private var environmentRevealHandle: some View {
        ZStack {
            Rectangle().fill(Color.clear).frame(width: 12)
            Capsule()
                .fill(DSHTheme.borderStrong)
                .frame(width: 3, height: 42)
        }
        .contentShape(Rectangle())
        .onTapGesture { layout.isEnvironmentVisible = true }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    // The window usually sits flush against the screen's
                    // right edge, so a rightward drag only has a few points
                    // of travel — any deliberate nudge must reveal.
                    if value.translation.width > 3 {
                        layout.isEnvironmentVisible = true
                    }
                }
        )
        .help("点击或向右拖动展开环境信息")
        .accessibilityLabel("展开环境信息")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { layout.isEnvironmentVisible = true }
    }

    private enum WidthTarget { case workbench, environment }

    private func widthReader(for target: WidthTarget) -> some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { saveWidth(proxy.size.width, for: target) }
                .onChange(of: proxy.size.width) { _, width in saveWidth(width, for: target) }
        }
    }

    private func saveWidth(_ width: CGFloat, for target: WidthTarget) {
        guard width.isFinite, width > 0 else { return }
        switch target {
        case .workbench:
            workbenchWidth = min(820, max(340, Double(width)))
        case .environment:
            environmentWidth = min(460, max(250, Double(width)))
        }
    }

    private func restore() {
        guard !didRestore else { return }
        didRestore = true
        if let data = persistedLayout.data(using: .utf8),
           var restored = try? JSONDecoder().decode(WorkbenchLayoutState.self, from: data) {
            restored.ensureUsableSelection()
            layout = restored
            ensureAuxiliaryThreads()
            if restored.isEnvironmentVisible { ensureHostWindowFitsEnvironment() }
        }
        if let requestedKind {
            focusOrOpen(requestedKind)
            self.requestedKind = nil
        }
    }

    /// Toolbar shortcuts are toggles/focus actions. Multiple terminal and
    /// assistant sessions are created explicitly from the workbench + menu.
    private func focusOrOpen(_ kind: WorkbenchLayoutState.TabKind) {
        if let existing = layout.tabs.last(where: { $0.kind == kind }) {
            layout.select(existing.id)
        } else {
            _ = openWorkbenchTab(kind)
        }
    }

    @discardableResult
    private func openWorkbenchTab(_ kind: WorkbenchLayoutState.TabKind) -> String {
        let id = layout.open(kind)
        if kind == .assistant,
           layout.tabs.first(where: { $0.id == id })?.linkedThreadID == nil,
           let tab = layout.tabs.first(where: { $0.id == id }) {
            let threadID = store.createAuxiliaryThread(parent: thread, title: tab.title)
            layout.linkThread(threadID, toTab: id)
        }
        return id
    }

    private func ensureAuxiliaryThreads() {
        for tab in layout.tabs where tab.kind == .assistant {
            let hasValidThread = tab.linkedThreadID.flatMap { id in
                store.liveThreads.first(where: { $0.id == id })
            }?.isAuxiliary == true
            if !hasValidThread {
                let threadID = store.createAuxiliaryThread(parent: thread, title: tab.title)
                layout.linkThread(threadID, toTab: tab.id)
            }
        }
        let referenced = Set(layout.tabs.compactMap(\.linkedThreadID))
        for orphan in store.liveThreads where orphan.isAuxiliary && !referenced.contains(orphan.id) {
            if !store.isThreadRunning(orphan.id) {
                store.deleteAuxiliaryThread(orphan.id)
            }
        }
    }

    private func closeWorkbenchTab(_ tab: WorkbenchLayoutState.Tab) {
        guard !isRunningAuxiliary(tab) else { return }
        if let threadID = tab.linkedThreadID { store.deleteAuxiliaryThread(threadID) }
        layout.close(tab.id)
    }

    private func closeOtherTabs(keeping id: String) {
        guard !hasRunningAuxiliary(excluding: id) else { return }
        removeAuxiliaryThreads(in: layout.tabs.filter { $0.id != id })
        layout.closeOthers(keeping: id)
    }

    private func removeAuxiliaryThreads(in tabs: [WorkbenchLayoutState.Tab]) {
        for tab in tabs where tab.kind == .assistant {
            if let threadID = tab.linkedThreadID, !store.isThreadRunning(threadID) {
                store.deleteAuxiliaryThread(threadID)
            }
        }
    }

    private func isRunningAuxiliary(_ tab: WorkbenchLayoutState.Tab) -> Bool {
        guard tab.kind == .assistant, let threadID = tab.linkedThreadID else { return false }
        return store.isThreadRunning(threadID)
    }

    private func hasRunningAuxiliary(excluding keptID: String?) -> Bool {
        layout.tabs.contains { tab in
            tab.id != keptID && isRunningAuxiliary(tab)
        }
    }

    private func persist() {
        guard didRestore,
              let data = try? JSONEncoder().encode(layout),
              let json = String(data: data, encoding: .utf8) else { return }
        persistedLayout = json
    }

    /// At narrow window widths SwiftUI has no legal split allocation for
    /// sidebar + chat + workbench + environment and will clip the trailing
    /// drawer. ZCode exposes the environment by extending the right side; do
    /// the same here, bounded by the current screen's visible frame.
    private func ensureHostWindowFitsEnvironment() {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible),
                  let screen = window.screen ?? NSScreen.main else { return }
            let minimumWidth: CGFloat = 1_220
            let availableWidth = screen.visibleFrame.width
            let targetWidth = min(availableWidth, max(window.frame.width, minimumWidth))
            guard targetWidth > window.frame.width + 1 else { return }
            var frame = window.frame
            frame.size.width = targetWidth
            if frame.maxX > screen.visibleFrame.maxX {
                frame.origin.x = screen.visibleFrame.maxX - targetWidth
            }
            frame.origin.x = max(screen.visibleFrame.minX, frame.origin.x)
            window.setFrame(frame, display: true, animate: true)
        }
    }
}

private struct WorkbenchReview: View {
    let thread: TapgoCore.Thread

    private var changes: [FileChange] {
        thread.turns
            .flatMap(\.items)
            .compactMap { item -> FileChange? in
                guard case .fileChange(let change) = item,
                      !item.isTurnDiffSnapshot else { return nil }
                return change
            }
            .reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("审查")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(changes.count) 个文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            Divider()
            if changes.isEmpty {
                ContentUnavailableView(
                    "暂无文件变更",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("任务产生文件修改后会在这里集中显示。")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(changes) { change in
                            VStack(alignment: .leading, spacing: 6) {
                                Label(change.path, systemImage: "doc.text")
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                DiffView(change: change)
                            }
                            .padding(10)
                            .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DSHTheme.border))
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(DSHTheme.bg)
    }
}

private struct WorkbenchAuxiliaryConversation: View {
    @EnvironmentObject private var store: SessionStore
    let tabID: String
    let threadID: String?
    @State private var draft = ""
    @State private var sendError: String?

    private var auxiliaryThread: TapgoCore.Thread? {
        guard let threadID else { return nil }
        return store.liveThreads.first(where: { $0.id == threadID && $0.isAuxiliary })
    }

    private var isRunning: Bool {
        threadID.map(store.isThreadRunning) ?? false
    }

    private var scrollRevision: Int {
        auxiliaryThread?.turns.reduce(0) { $0 + $1.items.count } ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("独立辅助对话", systemImage: "bubble.left.and.bubble.right")
                    .font(.caption.weight(.semibold))
                Spacer()
                if isRunning {
                    ProgressView().controlSize(.small)
                    Button {
                        if let threadID { store.cancelTurn(threadID: threadID) }
                    } label: {
                        Image(systemName: "stop.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("停止辅助对话")
                    .accessibilityLabel("停止辅助对话")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    if let auxiliaryThread {
                        if auxiliaryThread.turns.isEmpty {
                            ContentUnavailableView(
                                "开始独立对话",
                                systemImage: "bubble.left.and.bubble.right",
                                description: Text("此标签拥有独立上下文和历史，可与主任务并行运行。")
                            )
                            .frame(maxWidth: .infinity, minHeight: 260)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(auxiliaryThread.turns) { turn in
                                    auxiliaryTurn(turn)
                                }
                                Color.clear.frame(height: 1).id("auxiliary-bottom-\(tabID)")
                            }
                            .padding(12)
                        }
                    } else {
                        ContentUnavailableView(
                            "正在恢复辅助对话",
                            systemImage: "arrow.clockwise",
                            description: Text("工作台正在重建此标签的独立会话绑定。")
                        )
                        .frame(maxWidth: .infinity, minHeight: 260)
                    }
                }
                .onChange(of: scrollRevision) { _, _ in
                    proxy.scrollTo("auxiliary-bottom-\(tabID)", anchor: .bottom)
                }
            }
            if let sendError {
                Text(sendError)
                    .font(.caption)
                    // errorAccent (#E40014, 26 hits in ZCode asar) gives the
                    // auxiliary-conversation send-error banner the exact
                    // saturated red ZCode uses for the same surface, so it
                    // reads as "danger" rather than DSH's softer red.
                    .foregroundStyle(DSHTheme.errorAccent)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                TextField("向独立辅助对话发送消息", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .disabled(threadID == nil || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("发送到独立辅助对话")
            }
            .padding(10)
            .background(DSHTheme.surface)
        }
    }

    @ViewBuilder
    private func auxiliaryTurn(_ turn: Turn) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(TurnPresentation.compactBlocks(turn.items)) { block in
                switch block {
                case .item(let item):
                    MessageRow(
                        item: item,
                        isRunning: turn.status == .running,
                        userImagePaths: turn.userImagePaths,
                        startedAt: turn.startedAt,
                        onEdit: { text in
                            if let threadID { _ = store.sendUserMessage(text, toThreadID: threadID) }
                        }
                    )
                case .activity(let activity):
                    ActivityRollupView(activity: activity, turnIsRunning: turn.status == .running)
                case .fileBatch(let files):
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(files) { file in
                            FileChangeRowView(change: file)
                        }
                    }
                }
            }
            if turn.status == .running {
                Text("处理中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let threadID else { return }
        if store.sendUserMessage(text, toThreadID: threadID) {
            draft = ""
            sendError = nil
        } else {
            sendError = "辅助对话当前不可用，请检查运行设置后重试。"
        }
    }
}

private struct WorkbenchTerminal: View {
    let tabID: String
    @StateObject private var controller: WorkbenchTerminalController
    @State private var command = ""

    init(tabID: String, cwd: String?) {
        self.tabID = tabID
        _controller = StateObject(wrappedValue: WorkbenchTerminalController(cwd: cwd))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "terminal")
                Text("终端 zsh")
                    .font(.caption.weight(.semibold))
                Spacer()
                if controller.isRunning {
                    ProgressView().controlSize(.small)
                    Button {
                        controller.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("停止命令")
                    .accessibilityLabel("停止命令")
                }
                Button {
                    controller.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("清空终端")
                .accessibilityLabel("清空终端")
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    Text(controller.output)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .textColor))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(10)
                    Color.clear.frame(height: 1).id("terminal-bottom")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: controller.output) { _, _ in
                    proxy.scrollTo("terminal-bottom", anchor: .bottom)
                }
            }
            HStack(spacing: 7) {
                Text("❯")
                    .font(.system(size: 12, design: .monospaced).weight(.bold))
                    .foregroundStyle(DSHTheme.brand)
                TextField("Terminal input", text: $command)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .disabled(controller.isRunning)
                    .onSubmit(run)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(DSHTheme.surface)
        }
    }

    private func run() {
        let value = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        command = ""
        controller.run(value)
    }
}

@MainActor
private final class WorkbenchTerminalController: ObservableObject {
    @Published var output: String
    @Published var isRunning = false
    private let cwd: String?
    private var processBox: WorkbenchProcessBox?

    init(cwd: String?) {
        self.cwd = cwd
        self.output = "Tapgo 终端 · \(cwd ?? FileManager.default.homeDirectoryForCurrentUser.path)\n"
    }

    func clear() {
        output = ""
    }

    func run(_ command: String) {
        guard !isRunning else { return }
        isRunning = true
        output += "\n❯ \(command)\n"
        let cwd = self.cwd
        let box = WorkbenchProcessBox()
        processBox = box
        Task { [command, cwd, box] in
            let result = await Task.detached(priority: .userInitiated) {
                box.execute(command, cwd: cwd)
            }.value
            output += result.output
            if result.exitCode != 0 {
                output += "\n[退出码 \(result.exitCode)]\n"
            }
            if processBox === box { processBox = nil }
            isRunning = false
        }
    }

    func stop() {
        processBox?.terminate()
    }

    deinit {
        processBox?.terminate()
    }
}

/// Process is intentionally contained behind a lock and marked sendable: the
/// terminal controller owns it on the main actor while execution and pipe
/// draining happen off-main. Combining stdout/stderr into one drained pipe
/// avoids the classic full-pipe deadlock on large command output.
private final class WorkbenchProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var wasCancelled = false

    func execute(_ command: String, cwd: String?) -> (output: String, exitCode: Int32) {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        if let cwd, FileManager.default.fileExists(atPath: cwd) {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        }
        lock.lock()
        self.process = process
        let shouldCancel = wasCancelled
        lock.unlock()
        do {
            try process.run()
            if shouldCancel { process.terminate() }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            lock.lock()
            self.process = nil
            lock.unlock()
            return (String(decoding: data, as: UTF8.self), process.terminationStatus)
        } catch {
            lock.lock()
            self.process = nil
            lock.unlock()
            return ("无法启动命令：\(error.localizedDescription)\n", -1)
        }
    }

    func terminate() {
        lock.lock()
        wasCancelled = true
        let process = self.process
        lock.unlock()
        if process?.isRunning == true { process?.terminate() }
    }

    deinit {
        terminate()
    }
}

private struct WorkbenchBrowser: View {
    @StateObject private var controller = WorkbenchBrowserController()
    @State private var address = ""
    @State private var freeSize = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Button { controller.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!controller.canGoBack)
                    .accessibilityLabel("后退")
                Button { controller.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!controller.canGoForward)
                    .accessibilityLabel("前进")
                Button { controller.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(controller.currentURL == nil)
                    .accessibilityLabel("刷新")
                TextField("输入网址后回车", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { controller.navigate(address) }
                Toggle("自由尺寸", isOn: $freeSize)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Menu {
                    Button("在默认浏览器中打开") { controller.openExternally() }
                        .disabled(controller.currentURL == nil)
                    Button("复制网址") { controller.copyURL() }
                        .disabled(controller.currentURL == nil)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("更多浏览器操作")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
            .frame(height: 42)
            .background(DSHTheme.fidelityTitlebar)
            Divider()
            WorkbenchWebView(controller: controller)
                .padding(freeSize ? 16 : 0)
                .background(DSHTheme.moduleBg)
        }
        .onReceive(controller.$currentURL) { url in
            if let url { address = url.absoluteString }
        }
    }
}

@MainActor
private final class WorkbenchBrowserController: NSObject, ObservableObject, WKNavigationDelegate {
    let webView = WKWebView(frame: .zero)
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentURL: URL?

    override init() {
        super.init()
        webView.navigationDelegate = self
        webView.loadHTMLString("""
        <!doctype html><meta name='color-scheme' content='light dark'>
        <style>body{height:100vh;margin:0;display:grid;place-items:center;font:14px -apple-system;color:#8a8a8e;text-align:center}.g{font-size:54px;margin-bottom:14px}</style>
        <div><div class='g'>◎</div><b>浏览器</b><p>粘贴或输入 URL 以打开网页。</p></div>
        """, baseURL: nil)
    }

    func navigate(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: normalized) else { return }
        webView.load(URLRequest(url: url))
    }

    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }
    func reload() { webView.reload() }
    func openExternally() { if let currentURL { NSWorkspace.shared.open(currentURL) } }
    func copyURL() {
        guard let currentURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentURL.absoluteString, forType: .string)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { refreshState() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { refreshState() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { refreshState() }

    private func refreshState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        currentURL = webView.url
    }
}

private struct WorkbenchWebView: NSViewRepresentable {
    @ObservedObject var controller: WorkbenchBrowserController
    func makeNSView(context: Context) -> WKWebView { controller.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
