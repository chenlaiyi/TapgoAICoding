import SwiftUI
import TapgoCore
import UniformTypeIdentifiers

struct SidebarView: View {
    private enum Layout {
        static let projectIconWidth: CGFloat = 20
        static let threadTitleIndent: CGFloat = projectIconWidth + 6
    }

    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var workspace: WorkspaceStore
    @EnvironmentObject var authStore: AdminAuthStore
    @State private var isDropTargeted = false
    @State private var renamingThreadId: String?
    @State private var renameDraft: String = ""
    @State private var confirmingDelete: TapgoCore.Thread?
    @State private var confirmingProjectRemove: String? = nil
    @State private var editingProject: Project?
    @State private var searchQuery: String = ""
    @FocusState private var searchFocused: Bool
    @State private var searchScope = false
    @State private var showEvolutionLog = false
    @State private var showEvolutionRootMissing = false
    @State private var showConnectPhone = false
    @State private var showPluginManager = false
    @State private var hoveredThreadId: String? = nil
    @State private var hoveredProjectId: String? = nil
    @State private var collapsedGroups: Set<String> = []
    /// 每个分组的展开阈值：默认每组只展示最新 5 条；点一次"展开显示"按钮 +10。
    /// 搜索激活时不限制，全部命中结果都会展示，便于用户快速定位。
    @State private var expandedThreadLimits: [String: Int] = [:]
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    private enum ThreadLimit {
        static let `default`: Int = 5
        static let step: Int = 10
    }

    let showNewTask: () -> Void
    let showSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            searchField
            Divider()
            threadList
            Spacer(minLength: 0)
            userBar
        }
        .background(DSHTheme.bg)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DSHTheme.brand, style: StrokeStyle(lineWidth: 2, dash: [6]))
                .padding(4)
                .opacity(isDropTargeted ? 1 : 0)
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            acceptDroppedFolder(providers)
        }
        .alert("重命名会话", isPresented: Binding(
            get: { renamingThreadId != nil },
            set: { if !$0 { renamingThreadId = nil } }
        )) {
            TextField("标题", text: $renameDraft)
            Button("确定") {
                if let id = renamingThreadId {
                    store.renameThread(id, to: renameDraft)
                }
                renamingThreadId = nil
            }
            Button("取消", role: .cancel) { renamingThreadId = nil }
        } message: {
            Text("为这个会话起一个新标题。")
        }
        .confirmationDialog("删除会话?",
                            isPresented: Binding(
                                get: { confirmingDelete != nil },
                                set: { if !$0 { confirmingDelete = nil } }
                            ),
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let t = confirmingDelete { store.deleteThread(t.id) }
                confirmingDelete = nil
            }
            Button("取消", role: .cancel) { confirmingDelete = nil }
        } message: {
            Text("会话将从历史记录中移除,不会删除磁盘文件。")
        }
        .confirmationDialog("移除项目?", isPresented: Binding(
            get: { confirmingProjectRemove != nil },
            set: { if !$0 { confirmingProjectRemove = nil } }
        ), titleVisibility: .visible) {
            Button("移除", role: .destructive) {
                if let id = confirmingProjectRemove {
                    workspace.removeProject(id)
                }
                confirmingProjectRemove = nil
            }
            Button("取消", role: .cancel) { confirmingProjectRemove = nil }
        } message: {
            Text("将从列表中移除该项目。其下的会话会保留为未分类历史，不会删除磁盘文件。")
        }
        .sheet(item: $editingProject) { project in
            EditProjectSheet(project: project)
                .environmentObject(workspace)
        }
        .sheet(isPresented: $showEvolutionLog) {
            EvolutionLogView()
        }
        .alert("未找到自进化项目目录", isPresented: $showEvolutionRootMissing) {
            Button("好", role: .cancel) {}
        } message: {
            Text("自进化会话需要在 ~/TapgoAICoding 找到本项目（含 Package.swift 与 AGENTS.md）。请先在本机克隆或同步仓库。")
        }
        .sheet(isPresented: $showConnectPhone) {
            ConnectPhoneView()
        }
        .sheet(isPresented: $showPluginManager) {
            PluginManagerView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapgoFocusSearch)) { _ in
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapgoSelectPrevThread)) { _ in
            selectAdjacentThread(-1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapgoSelectNextThread)) { _ in
            selectAdjacentThread(1)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapgoOpenEvolution)) { _ in
            if !store.openEvolution() {
                showEvolutionRootMissing = true
            }
        }
    }

    // MARK: - Top bar (new task is the first button)

    @ViewBuilder
    private var topBar: some View {
        VStack(alignment: .leading, spacing: 2) {
            menuItem("自进化", "sparkles") {
                if !store.openEvolution() {
                    showEvolutionRootMissing = true
                }
            }
            .help("进入自进化专属会话：独立对话、独立开发 (⌘⌥E)")
            .accessibilityLabel("自进化会话")
            menuItem("连接手机", "iphone.gen3.radiowaves.left.and.right") {
                showConnectPhone = true
            }
            .help("连接点点够终端 iOS App (⌘⇧P)")
            .accessibilityLabel("连接手机")
            menuItem("插件", "puzzlepiece.extension") {
                showPluginManager = true
            }
            .help("管理 Codex 与 DeepSeek Harness 插件")
            .accessibilityLabel("插件管理")
            menuItem("新对话", "plus.message") {
                store.newThread()
            }
            .help("新对话 (⌘N)")
            .accessibilityLabel("新对话, 快捷键 ⌘N")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private func menuItem(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search

    @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
            TextField("搜索会话", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                .focused($searchFocused)
                .onExitCommand {
                    if !searchQuery.isEmpty { searchQuery = "" }
                }
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("清空搜索")
            }
            Button {
                searchScope.toggle()
            } label: {
                Image(systemName: searchScope ? "scope" : "circle")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(searchScope ? DSHTheme.brand : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(searchScope ? "仅当前项目 (点击切换为全部)" : "全部项目 (点击切换为仅当前)")
            .accessibilityLabel(searchScope ? "仅当前项目" : "全部项目")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: DSHTheme.radiusPill))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("搜索会话")
    }

    // MARK: - TapgoCore.Thread list

    @ViewBuilder
    private var threadList: some View {
        List(selection: Binding(
            get: { store.activeThreadId },
            set: { id in if let id = id { store.selectThread(id) } }
        )) {
            if grouped.isEmpty {
                emptyState
            } else {
                ForEach(grouped, id: \.project?.id) { group in
                    threadSection(for: group)
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// Render a single project (or the legacy "未分类" bucket) as a
    /// `Section`. The body honours the user's collapsed flag and the
    /// per-group pagination limit (default 5, +10 per "展开显示" tap).
    @ViewBuilder
    private func threadSection(for group: ThreadGroup) -> some View {
        let visible = visibleThreads(in: group)
        let limit = threadLimit(for: group)
        Section {
            if !collapsedGroups.contains(group.id) {
                // Keep project children visually flat and compact:
                // one title per row, ordered by recency.
                ForEach(Array(visible)) { t in
                    threadRow(t)
                        .tag(t.id)
                        .contextMenu { contextMenu(for: t) }
                }
                if !isSearching, group.threads.count > limit {
                    expandThreadsButton(for: group)
                }
            }
        } header: {
            projectGroupHeader(group)
        }
    }

    /// 搜索激活时永远返回全部线程，让用户能看到所有命中；
    /// 否则按当前分组阈值切片。
    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func threadLimit(for group: ThreadGroup) -> Int {
        expandedThreadLimits[group.id] ?? ThreadLimit.default
    }

    private func visibleThreads(in group: ThreadGroup) -> [TapgoCore.Thread] {
        if isSearching { return group.threads }
        let limit = threadLimit(for: group)
        return Array(group.threads.prefix(limit))
    }

    private func expandThreads(in group: ThreadGroup) {
        let current = threadLimit(for: group)
        expandedThreadLimits[group.id] = current + ThreadLimit.step
    }

    /// 渲染"展开显示 N 条"按钮。N 是点击后实际会达到的阈值
    /// (current+10，但不会超过该组线程总数)。
    @ViewBuilder
    private func expandThreadsButton(for group: ThreadGroup) -> some View {
        let current = threadLimit(for: group)
        let target = min(current + ThreadLimit.step, group.threads.count)
        let remaining = group.threads.count - current
        Button {
            expandThreads(in: group)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                Text("展开显示 \(target) 条")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                Text("(还剩 \(remaining) 条)")
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(DSHTheme.brand)
            .padding(.vertical, 4)
            .padding(.leading, Layout.threadTitleIndent)
        }
        .buttonStyle(.plain)
        .help("点击展开，再多显示 10 条会话")
        .accessibilityLabel("展开显示 \(target) 条会话，当前 \(current) 条，共 \(group.threads.count) 条")
    }

    @ViewBuilder
    private func contextMenu(for t: TapgoCore.Thread) -> some View {
        Button {
            copyToPasteboard(t.title)
        } label: {
            Label("复制会话标题", systemImage: "doc.on.doc")
        }
        Button {
            let md = t.turns.map { TurnMarkdown.render($0) }.joined(separator: "\n\n---\n\n")
            copyToPasteboard(md)
        } label: {
            Label("复制会话为 Markdown", systemImage: "doc.on.doc")
        }
        Button {
            var s = t.id
            if let h = t.harnessThreadId { s += "\nharness: " + h }
            copyToPasteboard(s)
        } label: {
            Label("复制会话 ID", systemImage: "number")
        }
        Button {
            store.togglePinned(t.id)
        } label: {
            Label(t.isPinned ? "取消置顶" : "置顶", systemImage: "pin")
        }
        Button {
            renamingThreadId = t.id
            renameDraft = t.title
        } label: {
            Label(L10n.rename, systemImage: "pencil")
        }
        if let p = t.projectId.flatMap({ workspace.project(byId: $0) }), !p.isRemote {
            Button {
                NSWorkspace.shared.open(p.worktreeRoot)
            } label: {
                Label("打开项目目录", systemImage: "folder")
            }
        }
        Button(role: .destructive) {
            confirmingDelete = t
        } label: {
            Label("删除会话", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func projectGroupHeader(_ group: ThreadGroup) -> some View {
        if group.isEvolutionGroup {
            evolutionGroupHeader(group)
        } else if let p = group.project {
            HStack(spacing: 6) {
                Image(systemName: p.isRemote ? "globe" : "folder.fill")
                    .font(AppFont.scaled(.title3, multiplier: appFontScale.multiplier))
                    .foregroundStyle(p.isRemote ? .blue : DSHTheme.brand)
                    .frame(width: Layout.projectIconWidth, alignment: .leading)
                Text(p.displayName)
                    .font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if workspace.isProjectPinned(p.id) {
                    Image(systemName: "pin.fill")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(DSHTheme.brand)
                }
                if groupHasRunningTask(group) {
                    runningDot
                }
                if workspace.state.activeProjectId == p.id {
                    activeBadge
                }
                Spacer()
                if hoveredProjectId == p.id {
                    projectMoreMenu(p)
                }
                projectCollapseButton(group.id)
            }
            .contentShape(Rectangle())
            .background(hoveredProjectId == p.id ? DSHTheme.interactiveHover : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .onHover { hovering in
                hoveredProjectId = hovering ? p.id : (hoveredProjectId == p.id ? nil : hoveredProjectId)
            }
            .onTapGesture {
                // Clicking the project header switches the active
                // project. The chevron button toggles collapse/expand.
                store.setActiveProject(p.id)
            }
            .contextMenu {
                Button {
                    editingProject = p
                } label: {
                    Label("重命名项目", systemImage: "pencil")
                }
                Button {
                    workspace.togglePinProject(p.id)
                } label: {
                    Label(workspace.isProjectPinned(p.id) ? "取消置顶项目" : "置顶项目", systemImage: "pin")
                }
                if !p.isRemote {
                    Button {
                        NSWorkspace.shared.open(p.worktreeRoot)
                    } label: {
                        Label("在访达中显示", systemImage: "folder")
                    }
                }
                Divider()
                Button {
                    confirmingProjectRemove = p.id
                } label: {
                    Label("移除项目…", systemImage: "trash")
                }
                .foregroundStyle(.red)
            }
            .help(p.isRemote ? "远程项目 · 点击切换" : "点击切换项目")
            .accessibilityLabel("项目 \(p.displayName), \(group.threads.count) 个会话")        } else {
            HStack(spacing: 4) {
                Image(systemName: "tray")
                Text(L10n.legacyGroupTitle)
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                Spacer()
                Text("\(group.threads.count)")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
                Button {
                    toggleGroup(group.id)
                } label: {
                    Image(systemName: collapsedGroups.contains(group.id) ? "chevron.right" : "chevron.down")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                }
                .buttonStyle(.borderless)
            }
            .accessibilityLabel("未分类会话, \(group.threads.count) 个")
        }
    }

    /// 自进化分组的专属头部：sparkles 图标 +「自进化」，点击进入最新的
    /// 自进化会话；同样支持折叠/展开。
    private func evolutionGroupHeader(_ group: ThreadGroup) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(AppFont.scaled(.title3, multiplier: appFontScale.multiplier))
                .foregroundStyle(DSHTheme.brand)
                .frame(width: Layout.projectIconWidth, alignment: .leading)
            Text("自进化")
                .font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if groupHasRunningTask(group) {
                runningDot
            }
            Spacer()
            Button {
                toggleGroup(group.id)
            } label: {
                Image(systemName: collapsedGroups.contains(group.id) ? "chevron.right" : "chevron.down")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(collapsedGroups.contains(group.id) ? "展开自进化分组" : "收起自进化分组")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // 点击头部直接进入（或创建）最新的自进化会话。
            if !store.openEvolution() {
                showEvolutionRootMissing = true
            }
        }
        .help("自进化专属会话 · 点击进入 (⌘⌥E)")
        .accessibilityLabel("自进化会话分组, \(group.threads.count) 个")
    }

    private func toggleGroup(_ id: String) {
        if collapsedGroups.contains(id) {
            collapsedGroups.remove(id)
        } else {
            collapsedGroups.insert(id)
        }
    }

    /// True when any thread in the group has a turn running or awaiting
    /// approval — drives the blue "running" dot on the project header.
    private func groupHasRunningTask(_ group: ThreadGroup) -> Bool {
        group.threads.contains { t in
            switch t.turns.last?.status {
            case .running, .awaitingApproval: return true
            default: return false
            }
        }
    }

    // MARK: - Project header sub-views (kept small so the type-checker can cope)

    private var runningDot: some View {
        Circle()
            .fill(DSHTheme.brand)
            .frame(width: 7, height: 7)
            .help("该项目有任务正在执行")
            .accessibilityLabel("该项目有任务正在执行")
    }

    private var activeBadge: some View {
        Text("当前")
            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
            .foregroundStyle(DSHTheme.brand)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(DSHTheme.brand.opacity(0.12), in: Capsule())
    }

    private func projectMoreMenu(_ p: Project) -> some View {
        Menu {
            Button {
                store.setActiveProject(p.id)
            } label: {
                Label("设为当前项目", systemImage: "checkmark.circle")
            }
            Button {
                workspace.togglePinProject(p.id)
            } label: {
                Label(workspace.isProjectPinned(p.id) ? "取消置顶项目" : "置顶项目", systemImage: "pin")
            }
            Divider()
            Button {
                editingProject = p
            } label: {
                Label("编辑项目", systemImage: "pencil")
            }
            if !p.isRemote {
                Button {
                    NSWorkspace.shared.open(p.worktreeRoot)
                } label: {
                    Label("在访达中显示", systemImage: "folder")
                }
            }
            Button {
                copyToPasteboard(p.displayPath)
            } label: {
                Label("复制路径", systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive) {
                confirmingProjectRemove = p.id
            } label: {
                Label("移除项目…", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .help("项目操作")
        .accessibilityLabel("项目操作")
    }

    private func projectCollapseButton(_ id: String) -> some View {
        Button {
            toggleGroup(id)
        } label: {
            Image(systemName: collapsedGroups.contains(id) ? "chevron.right" : "chevron.down")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(collapsedGroups.contains(id) ? "展开项目" : "收起项目")
    }

    /// Pinned threads first, then most-recent.
    private func sortedThreads(_ threads: [TapgoCore.Thread]) -> [TapgoCore.Thread] {
        threads.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    @ViewBuilder
    private func threadRow(_ t: TapgoCore.Thread) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(t.title)
                .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                .lineLimit(1)
                .truncationMode(.tail)
            if t.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(DSHTheme.brand)
            }
            Spacer(minLength: 6)
            if shouldShowStatus(for: t) {
                statusDot(t)
            }
        }
        .padding(.vertical, 5)
        .padding(.leading, Layout.threadTitleIndent)
        .padding(.trailing, 2)
        .contentShape(Rectangle())
        .background(hoveredThreadId == t.id ? DSHTheme.interactiveHover : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            hoveredThreadId = hovering ? t.id : (hoveredThreadId == t.id ? nil : hoveredThreadId)
        }
        .accessibilityLabel("会话 \(t.title), \(sidebarSubtitle(for: t))")
    }

    private func shouldShowStatus(for t: TapgoCore.Thread) -> Bool {
        switch t.turns.last?.status {
        case .running, .awaitingApproval, .failed:
            return true
        default:
            return false
        }
    }

    private func sidebarSubtitle(for t: TapgoCore.Thread) -> String {
        let s = t.latestPreview
        if !s.isEmpty { return s }
        return t.turns.isEmpty ? "(新会话)" : "(无输入)"
    }

    @ViewBuilder
    private func statusDot(_ t: TapgoCore.Thread) -> some View {
        let last = t.turns.last
        let color = colorFor(last?.status)
        let isRunning = last?.status == .running
        // Codex-style animated pulse for in-flight turns: an
        // outer ring that grows and fades while a solid dot stays
        // at the center. Disabled turns get a static dot so we
        // don't burn battery on a thread that's idle.
        ZStack {
            if isRunning {
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulseScale)
                    .opacity(1 - pulseProgress)
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
        }
        .help(statusTooltip(last?.status) ?? "")
        .accessibilityLabel(statusTooltip(last?.status) ?? "")
        .onAppear {
            // Drive the pulse only while at least one turn in any
            // visible thread is still .running. The animation
            // itself is global to the view so it stays in sync.
            if isRunning { startPulseIfNeeded() }
        }
    }

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseProgress: CGFloat = 0.0
    @State private var pulseTask: Task<Void, Never>? = nil

    private func startPulseIfNeeded() {
        guard pulseTask == nil else { return }
        pulseTask = Task { @MainActor in
            while !Task.isCancelled {
                withAnimation(.easeOut(duration: 1.2)) {
                    pulseScale = 2.4
                    pulseProgress = 1
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if Task.isCancelled { break }
                pulseScale = 1.0
                pulseProgress = 0
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
            pulseTask = nil
        }
    }

    private func colorFor(_ s: Turn.Status?) -> Color {
        switch s {
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .awaitingApproval: return .yellow
        case .interrupted: return .orange
        default: return .gray.opacity(0.4)
        }
    }
    private func statusTooltip(_ s: Turn.Status?) -> String? {
        switch s {
        case .running: return "执行中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .awaitingApproval: return "等待批准"
        case .interrupted: return "中断"
        default: return nil
        }
    }

    private func copyToPasteboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }


    /// Accept a folder dropped onto the sidebar: add it as a project, make it
    /// active, and start a thread in it — the drag-and-drop "设立目录" path.
    private func acceptDroppedFolder(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            var isDir: ObjCBool = false
            guard let url = url,
                  FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { return }
            DispatchQueue.main.async {
                let id = "local-" + UUID().uuidString
                let display = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
                let project = Project(
                    id: id, displayName: display, kind: .local,
                    addedAt: Date(), lastUsedAt: Date(),
                    worktreeRoot: url, bookmark: nil,
                    remoteHostId: nil, remotePath: nil
                )
                workspace.addProject(project)
                workspace.setActiveProject(id)
                store.newThread()
            }
        }
        return true
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(L10n.noThreadsYet)
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                Button(L10n.startANewThread) { showNewTask() }
                    .buttonStyle(DSHPrimaryButtonStyle())
            } else {
                Text("无匹配的会话")
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                Button {
                    searchQuery = ""
                } label: {
                    Label("清空搜索", systemImage: "xmark.circle")
                        .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Footer

    /// 左下角灰色行: 当前模型供应商 / 套餐名 / 周余量百分比。
    private var modelQuotaSummary: String {
        var parts = ["MiniMax"]
        let snapshot = store.rateLimits
        parts.append(snapshot?.planLabel ?? "Token Plan")
        if let weekly = snapshot?.secondary, weekly.windowDurationMins == 10080 {
            parts.append("周余量 \(max(0, 100 - weekly.usedPercent))%")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var userBar: some View {
        HStack(spacing: 8) {
            if let user = authStore.currentUser {
                // Logged-in Tapgo admin (from 扫码登录): show avatar + nickname.
                UserAvatar(url: user.avatarURL, name: user.displayName, size: 28)
                    .accessibilityLabel("当前登录用户")
                VStack(alignment: .leading, spacing: 0) {
                    Text(user.displayName)
                        .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                        .lineLimit(1)
                    Text(modelQuotaSummary)
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .task {
                    // 进侧栏立即拉额度, 之后每 5 分钟刷新 (周余量/套餐名)。
                    store.refreshRateLimits()
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 300_000_000_000)
                        store.refreshRateLimits()
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        authStore.logout()
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    Button {
                        showSettings()
                    } label: {
                        Label("设置", systemImage: "gear")
                    }
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(AppFont.scaled(.title3, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("当前用户")
                VStack(alignment: .leading, spacing: 0) {
                    Text(NSUserName())
                        .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                        .lineLimit(1)
                    Text("Tapgo AICoding")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Circle()
                .fill(runnerStatusColor)
                .frame(width: 8, height: 8)
                .help(runnerStatusHelp)
                .accessibilityLabel(runnerStatusHelp)
            Button {
                showSettings()
            } label: {
                Image(systemName: "gear")
                    .font(AppFont.scaled(.title3, multiplier: appFontScale.multiplier))
            }
            .buttonStyle(.borderless)
            .help(L10n.tooltipSettings)
            .accessibilityLabel(L10n.tooltipSettings)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private var runnerStatusColor: Color {
        if store.hasAnyRunningTasks { return .blue }
        switch store.runnerState {
        case .running: return .blue
        case .failed: return DSHTheme.error
        case .idle, .finished: return DSHTheme.success
        }
    }
    private var runnerStatusHelp: String {
        if store.hasAnyRunningTasks { return "执行中（\(store.inProgressTasks)）" }
        switch store.runnerState {
        case .running: return "执行中"
        case .failed: return "异常"
        case .idle, .finished: return "就绪"
        }
    }

    // MARK: - Grouping

    private struct ThreadGroup: Identifiable {
        let project: Project?
        let threads: [TapgoCore.Thread]
        /// True for the pinned 自进化 group: independent of projects,
        /// always sorted to the very top of the sidebar.
        var isEvolutionGroup: Bool = false
        var id: String { isEvolutionGroup ? "_evolution" : (project?.id ?? "_legacy") }
    }

    private var grouped: [ThreadGroup] {
        let activeId = workspace.state.activeProjectId
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Threads grouped by project. Search filter narrows the set;
        // empty groups are dropped so the sidebar doesn't show dead
        // project headers when nothing matches.
        var byProject: [String?: [TapgoCore.Thread]] = [:]
        // 自进化会话不参与项目分组——它们有独立的置顶分组。
        let evolutionThreads = store.liveThreads.filter {
            $0.isEvolution && (!isSearching || threadMatchesSearch($0, query: trimmedQuery))
        }
        for t in store.liveThreads where !t.isEvolution {
            // "仅当前项目" scope narrows to the active project's threads.
            if searchScope, t.projectId != workspace.state.activeProjectId { continue }
            // Match against title, first user input, and the project
            // display name. Codex's sidebar search is broad on
            // content; we mirror that.
            if !trimmedQuery.isEmpty,
               !threadMatchesSearch(t, query: trimmedQuery) { continue }
            let key: String? = (t.projectId == nil) ? nil : t.projectId
            byProject[key, default: []].append(t)
        }
        var groups: [ThreadGroup] = []
        var seenProjectIds: Set<String> = []
        // Orphan threads (projectId points at a project that no
        // longer exists in the workspace) are all collapsed into a
        // single "未分类" group. Without this collapse, every unique
        // orphan projectId would render as its own "未分类" header.
        var legacyOrphans: [TapgoCore.Thread] = []
        for (pid, list) in byProject {
            if pid == nil {
                // Truly project-less thread — also goes into the
                // legacy bucket so the user always sees one "未分类"
                // group rather than several.
                legacyOrphans.append(contentsOf: list)
                continue
            }
            let p = workspace.project(byId: pid ?? "")
            if p == nil {
                legacyOrphans.append(contentsOf: list)
            } else if let p = p {
                groups.append(ThreadGroup(
                    project: p,
                    threads: sortedThreads(list)
                ))
                seenProjectIds.insert(p.id)
            }
        }
        if !legacyOrphans.isEmpty {
            groups.append(ThreadGroup(
                project: nil,
                threads: sortedThreads(legacyOrphans)
            ))
        }
        // Also surface any workspace project that has no threads (and
        // is not filtered by the search), so the user can switch to a
        // remote project they added but haven't started a turn on.
        // These stay at the bottom under their project header.
        if trimmedQuery.isEmpty {
            let emptyProjects = workspace.state.projects
                .filter { !seenProjectIds.contains($0.id) }
                .sorted { $0.lastUsedAt > $1.lastUsedAt }
            for p in emptyProjects {
                groups.append(ThreadGroup(project: p, threads: []))
            }
        }
        // 自进化分组：独立于项目，只要存在（或搜索命中）就置顶展示。
        if !evolutionThreads.isEmpty {
            groups.append(ThreadGroup(
                project: nil,
                threads: sortedThreads(evolutionThreads),
                isEvolutionGroup: true
            ))
        }
        // Active project always at the top.
        groups.sort { lhs, rhs in
            if lhs.isEvolutionGroup != rhs.isEvolutionGroup { return lhs.isEvolutionGroup }
            if lhs.project?.id == activeId { return true }
            if rhs.project?.id == activeId { return false }
            let lp = lhs.project.map { workspace.isProjectPinned($0.id) } ?? false
            let rp = rhs.project.map { workspace.isProjectPinned($0.id) } ?? false
            if lp != rp { return lp }
            let lk = lhs.threads.isEmpty ? "_zz" : (lhs.project?.displayName ?? "_z")
            let rk = rhs.threads.isEmpty ? "_zz" : (rhs.project?.displayName ?? "_z")
            return lk < rk
        }
        return groups
    }

    /// Decide whether a thread should be visible in the sidebar
    /// when the user has typed a search query. Matches the title,
    /// the first user input, and (for remote threads) the host
    /// alias so the user can type `jk` to narrow down to remotehost.
    private func threadMatchesSearch(_ t: TapgoCore.Thread, query: String) -> Bool {
        if t.title.lowercased().contains(query) { return true }
        if let firstInput = t.turns.first?.userInput.lowercased(),
           firstInput.contains(query) { return true }
        if let pid = t.projectId,
           let p = workspace.project(byId: pid),
           p.displayName.lowercased().contains(query) { return true }
        if let last = t.turns.last?.userInput.lowercased(),
           last.contains(query) { return true }
        if t.latestPreview.lowercased().contains(query) { return true }
        return false
    }

    /// Select the previous / next thread in the sidebar's visual order,
    /// so ⌘⇧↑ / ⌘⇧↓ let the user hop between conversations by keyboard.
    private func selectAdjacentThread(_ delta: Int) {
        let ordered = grouped.flatMap(\.threads)
        guard !ordered.isEmpty else { return }
        let active = store.activeThreadId
        let idx = ordered.firstIndex { $0.id == active } ?? 0
        let next = (idx + delta + ordered.count) % ordered.count
        store.selectThread(ordered[next].id)
    }
}

/// Circular user avatar with a graceful fallback (initial letter) when the
/// image is missing, loading, or fails to load.
struct UserAvatar: View {
    let url: URL?
    let name: String
    let size: CGFloat

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                default:
                    fallback
                }
            }
            .frame(width: size, height: size)
        } else {
            fallback
        }
    }

    private var fallback: some View {
        ZStack {
            Circle().fill(DSHTheme.brand.opacity(0.18))
            Text(initial)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(DSHTheme.brand)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1)).uppercased()
    }
}
