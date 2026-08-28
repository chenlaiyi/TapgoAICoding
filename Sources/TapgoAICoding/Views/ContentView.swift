import SwiftUI
import AppKit
import TapgoCore

struct ContentView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var workspace: WorkspaceStore
    @State private var showSettings = false
    @State private var showNewTask = false
    @AppStorage("tapgo.showTrajectory") private var showTrajectory = false
    @State private var showShortcuts = false
    @State private var showCommandPalette = false
    @AppStorage("tapgo.wideContent") private var wideContent = false
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let err = store.setupError {
                    SetupView(error: err) { store.revalidateSetup() }
                } else {
                    mainSplit(availableWidth: geometry.size.width)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .dynamicTypeSize(.xLarge)
        .frame(minWidth: 1100, minHeight: 720)
        .onReceive(NotificationCenter.default.publisher(for: .tapgoRequestOpenSettings)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapgoRequestOpenNewTask)) { _ in
            showNewTask = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapgoRequestOpenLocalFolder)) { _ in
            handleOpenLocalFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapgoToggleTrajectory)) { _ in
            showTrajectory.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapgoOpenCommandPalette)) { _ in
            showCommandPalette = true
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(workspace)
                .environmentObject(store)
        }
        .sheet(isPresented: $showNewTask) {
            NewTaskView { project in
                workspace.setActiveProject(project?.id)
                store.newThread()
            }
            .environmentObject(workspace)
            .environmentObject(store)
        }
        .sheet(isPresented: $showShortcuts) {
            ShortcutsView()
        }
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteView(
                onNewTask: { showNewTask = true },
                onSettings: { showSettings = true },
                onToggleTrajectory: { showTrajectory.toggle() }
            )
            .environmentObject(workspace)
            .environmentObject(store)
        }
    }

    @ViewBuilder
    private func mainSplit(availableWidth: CGFloat) -> some View {
        let showAdaptiveEnvironment = AdaptiveEnvironmentLayout.shouldShow(
            windowWidth: Double(availableWidth),
            preferredChatWidth: wideContent ? 980 : 720,
            hasActiveThread: store.activeThreadId != nil,
            manualDetailVisible: showTrajectory
        )
        Group {
            if showTrajectory {
                split(showDetail: true, showAdaptiveEnvironment: false)
            } else {
                split(showDetail: false, showAdaptiveEnvironment: showAdaptiveEnvironment)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCommandPalette = true
                } label: {
                    Image(systemName: "command")
                }
                .help("命令面板 (⌘⇧P)")
                .accessibilityLabel("命令面板")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showShortcuts = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .help("快捷键")
                .accessibilityLabel("快捷键")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showTrajectory.toggle()
                } label: {
                    Image(systemName: showTrajectory ? "sidebar.trailing" : "sidebar.right")
                }
                .help(showTrajectory ? "隐藏轨迹栏" : "显示轨迹栏")
                .accessibilityLabel(showTrajectory ? "隐藏轨迹栏" : "显示轨迹栏")
            }
        }
    }

    @ViewBuilder
    private func split(showDetail: Bool, showAdaptiveEnvironment: Bool) -> some View {
        if showDetail {
            NavigationSplitView {
                SidebarView(
                    showNewTask: { showNewTask = true },
                    showSettings: { showSettings = true }
                )
            } content: {
                ChatView()
            } detail: {
                trajectoryDetail
            }
            .navigationSplitViewStyle(.balanced)
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
            .navigationSplitViewColumnWidth(min: 380, ideal: 560)
            .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        } else {
            NavigationSplitView {
                SidebarView(
                    showNewTask: { showNewTask = true },
                    showSettings: { showSettings = true }
                )
            } detail: {
                adaptiveChat(showEnvironmentCard: showAdaptiveEnvironment)
            }
            .navigationSplitViewStyle(.balanced)
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        }
    }

    /// Keeps one structural ChatView while the window crosses the responsive
    /// threshold. Only the trailing inset appears/disappears, so resizing the
    /// window cannot recreate the composer or steal its text focus.
    @ViewBuilder
    private func adaptiveChat(showEnvironmentCard: Bool) -> some View {
        ChatView()
            .safeAreaInset(edge: .trailing, spacing: 0) {
                if showEnvironmentCard,
                   let threadId = store.activeThreadId,
                   let thread = store.liveThreads.first(where: { $0.id == threadId }) {
                    VStack(spacing: 0) {
                        AdaptiveEnvironmentCard(thread: thread)
                            .padding(.top, 10)
                            .padding(.horizontal, 10)
                        Spacer(minLength: 0)
                    }
                    .frame(width: CGFloat(AdaptiveEnvironmentLayout.cardWidth))
                    .background(DSHTheme.bg)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .accessibilityIdentifier("adaptive-environment-card")
                }
            }
            .animation(.easeOut(duration: 0.16), value: showEnvironmentCard)
    }

    @ViewBuilder
    private var trajectoryDetail: some View {
        if let threadId = store.activeThreadId,
           let thread = store.liveThreads.first(where: { $0.id == threadId }) {
            VStack(spacing: 0) {
                // Environment info is its own collapsible block on top,
                // separate from the execution trace below.
                EnvironmentPanel(thread: thread)
                Divider()
                TrajectoryView(thread: thread)
            }
        } else {
            Text(L10n.selectThreadHint)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Local folder pick

    private func handleOpenLocalFolder() {
        do {
            let result = try LocalDirectoryPicker.pickDirectory()
            addLocalProject(url: result.url, bookmark: result.bookmark)
        } catch {
            // User-cancel is fine; other errors show as a banner.
            NSLog("[ContentView] pickDirectory failed: \(error.localizedDescription)")
        }
    }

    private func addLocalProject(url: URL, bookmark: Data?) {
        let id = "local-" + UUID().uuidString
        let display = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        let project = Project(
            id: id,
            displayName: display,
            kind: .local,
            addedAt: Date(),
            lastUsedAt: Date(),
            worktreeRoot: url,
            bookmark: bookmark,
            remoteHostId: nil,
            remotePath: nil
        )
        workspace.addProject(project)
        // Bind the new thread to this directory so it becomes the working
        // /cwd of the task — the "设立目录" affordance.
        workspace.setActiveProject(project.id)
        store.newThread()
    }
}

/// Small "keyboard shortcuts" help sheet.
private struct ShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("快捷键").font(AppFont.scaled(.title2, multiplier: appFontScale.multiplier)).bold()
            Divider()
            shortcutRow("新建任务", "⌘N")
            shortcutRow("新任务 (选目录)", "⌘⇧N")
            shortcutRow("打开本地文件夹", "⌘O")
            shortcutRow("打开项目目录", "⌘⇧O")
            shortcutRow("发送消息", "⌘↩")
            shortcutRow("清空输入", "⌘⌫")
            shortcutRow("设置", "⌘,")
            shortcutRow("聚焦会话搜索", "⌘K")
            shortcutRow("聚焦输入框", "⌘⇧L")
            shortcutRow("上一个会话", "⌘⇧↑")
            shortcutRow("下一个会话", "⌘⇧↓")
            shortcutRow("任务计划", "⌘⇧G")
            shortcutRow("复制会话为 Markdown", "⌘⇧E")
            shortcutRow("中断当前任务", "⌘.")
            shortcutRow("在对话中查找", "⌘⇧F")
            shortcutRow("重试上一回合", "⌘⇧R")
            shortcutRow("切换外观", "⌘⇧D")
            shortcutRow("命令面板", "⌘⇧P")
            shortcutRow("切换到轨迹栏/收起", "⌘⇧T")
            Text("这些快捷键在应用菜单中同样可用。")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            Spacer()
            Button("完成") { dismiss() }
                .buttonStyle(DSHPrimaryButtonStyle())
        }
        .padding(20)
        .frame(width: 360, height: 300)
    }

    private func shortcutRow(_ label: String, _ key: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(key)
                .font(AppFont.monoScaled(size: 13, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// Spotlight-style command palette (⌘⇧P): a search field over the app's
/// actions plus a quick thread jumper. Selecting an item runs it and
/// dismisses the palette.
private struct CommandPaletteView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TapgoConfig.appearanceKey) private var appearance = "system"
    @State private var query = ""
    @State private var hoveredId: String? = nil
    @State private var selectedIndex = 0
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    let onNewTask: () -> Void
    let onSettings: () -> Void
    let onToggleTrajectory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                ArrowTextField(text: $query,
                               onUp: { moveSelection(-1) },
                               onDown: { moveSelection(1) },
                               onSubmit: runSelected)
                    .frame(height: 24)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("清空")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DSHTheme.border, lineWidth: 1))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { idx, e in
                            if idx == firstThreadIndex {
                                Divider().padding(.vertical, 4)
                                Text("会话")
                                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                            }
                            Button {
                                e.run()
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: e.icon)
                                        .foregroundStyle(e.destructive ? .red : .secondary)
                                        .frame(width: 16)
                                    Text(e.title)
                                        .lineLimit(1)
                                        .foregroundStyle(e.destructive ? .red : .primary)
                                    if e.isThread, let sc = e.statusColor {
                                        Circle().fill(sc).frame(width: 7, height: 7)
                                    }
                                    Spacer()
                                    if let k = e.key {
                                        Text(k).font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier)).foregroundStyle(.tertiary)
                                    } else if let c = e.context {
                                        Text("\(c)%").font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier)).foregroundStyle(.tertiary)
                                    } else if let p = e.project {
                                        Text(p).font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier)).foregroundStyle(.tertiary).lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                                .background(rowBg(idx, e), in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .id("row-\(idx)")
                            .onHover { hovering in
                                hoveredId = hovering ? e.id : (hoveredId == e.id ? nil : hoveredId)
                            }
                        }
                    }
                }
                .onChange(of: selectedIndex) { _, newValue in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("row-\(newValue)", anchor: .center)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 440, height: 420)
        .onAppear { selectedIndex = 0 }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
    }

    private struct Entry: Identifiable {
        let id: String
        let title: String
        let icon: String
        let key: String?
        let isThread: Bool
        let project: String?
        let context: Int?
        let statusColor: Color?
        let destructive: Bool
        let run: () -> Void
    }

    private var entries: [Entry] {
        var out: [Entry] = []
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            out.append(Entry(id: "new-\(q)", title: "新建会话: \(q)", icon: "plus.message",
                             key: nil, isThread: false, project: nil,
                             context: nil, statusColor: nil, destructive: false,
                             run: {
                                 store.newThread()
                                 store.sendUserMessage(q)
                                 dismiss()
                             }))
        }
        for a in filteredActions {
            out.append(Entry(id: "a-\(a.id)", title: a.title, icon: a.icon,
                             key: a.keyLabel, isThread: false, project: nil,
                             context: nil, statusColor: nil,
                             destructive: a.destructive, run: a.run))
        }
        for t in matchingThreads {
            let proj = t.projectId.flatMap { workspace.project(byId: $0) }?.displayName
            let target = t.id
            let title = t.title
            let last = t.turns.last
            let statusColor: Color? = {
                switch last?.status {
                case .running: return DSHTheme.brand
                case .completed: return DSHTheme.success
                case .failed: return DSHTheme.error
                case .awaitingApproval: return DSHTheme.warn
                case .interrupted: return DSHTheme.warn
                case .pending, .none: return .secondary
                }
            }()
            let ctx = t.turns.last(where: { $0.usage != nil })?.usage?.contextPercent
            out.append(Entry(id: "t-\(target)", title: title, icon: "bubble.left",
                             key: nil, isThread: true, project: proj,
                             context: ctx, statusColor: statusColor, destructive: false,
                             run: { store.selectThread(target) }))
        }
        return out
    }

    private var firstThreadIndex: Int? {
        entries.firstIndex(where: { $0.isThread })
    }

    private func rowBg(_ idx: Int, _ e: Entry) -> Color {
        if selectedIndex == idx { return DSHTheme.interactiveHoverStrong }
        if hoveredId == e.id { return DSHTheme.interactiveHover }
        return Color.clear
    }

    private func moveSelection(_ delta: Int) {
        guard !entries.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + entries.count) % entries.count
    }

    private func runSelected() {
        guard !entries.isEmpty else { return }
        let idx = min(max(selectedIndex, 0), entries.count - 1)
        entries[idx].run()
        dismiss()
    }

    private struct PaletteAction: Identifiable {
        let id: String
        let title: String
        let icon: String
        let keyLabel: String?
        let run: () -> Void
        var destructive: Bool = false
        init(_ id: String, _ title: String, _ icon: String, _ key: String? = nil, destructive: Bool = false, _ run: @escaping () -> Void) {
            self.id = id
            self.title = title
            self.icon = icon
            self.keyLabel = key
            self.destructive = destructive
            self.run = run
        }
    }

    private var actions: [PaletteAction] {
        [
            .init("new", "新建任务", "plus.message", "⌘N", { onNewTask() }),
            .init("focusSearch", "聚焦会话搜索", "magnifyingglass", "⌘K",
                  { NotificationCenter.default.post(name: .tapgoFocusSearch, object: nil) }),
            .init("focusComposer", "聚焦输入框", "text.cursor", "⌘⇧L",
                  { NotificationCenter.default.post(name: .tapgoFocusComposer, object: nil) }),
            .init("toggleTrajectory", "切换轨迹栏", "sidebar.right", "⌘⇧T", { onToggleTrajectory() }),
            .init("copy", "复制会话为 Markdown", "doc.on.doc", "⌘⇧E",
                  { NotificationCenter.default.post(name: .tapgoCopyConversation, object: nil) }),
            .init("copyTitle", "复制会话标题", "textformat", "",
                  { copyActiveThreadTitle() }),
            .init("settings", "打开运行设置", "gear", "⌘,", { onSettings() }),
            .init("folder", "打开本地文件夹", "folder", "⌘O",
                  { NotificationCenter.default.post(name: .tapgoRequestOpenLocalFolder, object: nil) }),
            .init("openProjectDir", "打开项目目录", "folder.badge.gearshape", "⌘⇧O",
                  { NotificationCenter.default.post(name: .tapgoOpenActiveProject, object: nil) }),
            .init("appearance", "切换外观", "sun.max", "⌘⇧D", { toggleAppearance() }),
            .init("openInTerminal", "在终端中打开项目", "terminal", "",
                  { openActiveProjectTerminal() }),
        ]
    }

    private func copyActiveThreadTitle() {
        if let id = store.activeThreadId,
           let t = store.liveThreads.first(where: { $0.id == id }) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(t.title, forType: .string)
        }
    }

    private func toggleAppearance() {
        let next: String
        switch appearance {
        case "dark": next = "light"
        case "light": next = "system"
        default: next = "dark"
        }
        appearance = next
    }

    private func openActiveProjectTerminal() {
        guard let project = workspace.state.activeProject, !project.isRemote else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Terminal", project.worktreeRoot.path]
        try? p.run()
    }

    private var filteredActions: [PaletteAction] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return actions }
        return actions.filter { $0.title.lowercased().contains(q) }
    }

    private var matchingThreads: [TapgoCore.Thread] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.liveThreads
            .filter { thread in
                if q.isEmpty { return true }
                if thread.title.lowercased().contains(q) { return true }
                if thread.turns.last?.userInput.lowercased().contains(q) == true { return true }
                if thread.turns.first?.userInput.lowercased().contains(q) == true { return true }
                // Match the assistant's latest reply text too.
                let lastReply = thread.turns.reversed().lazy
                    .flatMap { $0.items }
                    .compactMap { item -> String? in
                        if case .assistantMessage(_, let t) = item { return t }
                        return nil
                    }
                    .first
                if let lastReply, lastReply.lowercased().contains(q) { return true }
                return false
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(8)
            .map { $0 }
    }
}

/// A search text field that forwards ↑/↓/↩ so the palette can offer full
/// keyboard navigation, not just typing.
private struct ArrowTextField: NSViewRepresentable {
    @Binding var text: String
    var onUp: () -> Void
    var onDown: () -> Void
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.delegate = context.coordinator
        tf.placeholderString = "命令或会话…"
        tf.focusRingType = .none
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.controlSize = .regular
        DispatchQueue.main.async { tf.window?.makeFirstResponder(tf) }
        return tf
    }
    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ArrowTextField
        init(_ p: ArrowTextField) { parent = p }
        func controlTextDidChange(_ obj: Notification) {
            if let tf = obj.object as? NSTextField { parent.text = tf.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)): parent.onUp(); return true
            case #selector(NSResponder.moveDown(_:)): parent.onDown(); return true
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit(); return true
            default: return false
            }
        }
    }
}
