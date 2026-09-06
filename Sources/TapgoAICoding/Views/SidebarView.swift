import SwiftUI
import TapgoCore
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var workspace: WorkspaceStore
    @EnvironmentObject var authStore: AdminAuthStore
    @EnvironmentObject var updater: AppUpdateController
    @State private var isDropTargeted = false
    @State private var renamingThreadId: String?
    @State private var renameDraft: String = ""
    @State private var confirmingDelete: TapgoCore.Thread?
    @State private var confirmingProjectRemove: String? = nil
    @State private var editingProject: Project?
    @State private var searchQuery: String = ""
    @State private var showSearchField = false
    @AppStorage("tapgo.sidebarViewMode") private var sidebarViewModeRaw = "groups"
    @FocusState private var searchFocused: Bool
    @State private var searchScope = false
    @State private var showEvolutionLog = false
    @State private var showEvolutionRootMissing = false
    @State private var showConnectPhone = false
    @State private var showPluginManager = false
    @State private var showScheduledTasks = false
    @State private var hoveredProjectId: String? = nil
    @AppStorage("tapgo.sidebarCollapsedProjects") private var collapsedGroupsJSON = "[]"
    @State private var showViewOptions = false
    @State private var showAccountMenu = false
    private var collapsedGroups: Set<String> {
        get { SidebarPresentation.collapsedIDs(collapsedGroupsJSON) }
        nonmutating set { collapsedGroupsJSON = SidebarPresentation.encodeCollapsedIDs(newValue) }
    }
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
            sidebarViewControl
            if showSearchField || !searchQuery.isEmpty {
                searchField
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            threadList
            Spacer(minLength: 0)
            userBar
        }
        .background(DSHTheme.sidebarBg)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                // brandBlueAccent (#4099FF, 28 hits in ZCode asar) is ZCode's
                // canonical drop-target ring colour. We use it here instead
                // of DSHTheme.brand so the indicator matches the upstream
                // renderer exactly — see DesktopDesignParityTests.
                .stroke(DSHTheme.brandBlueAccent, style: StrokeStyle(lineWidth: 2, dash: [6]))
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
        .sheet(isPresented: $showScheduledTasks) {
            ScheduledTasksView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapgoFocusSearch)) { _ in
            showSearchField = true
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

    // MARK: - ZCode desktop navigation

    @ViewBuilder
    private var topBar: some View {
        VStack(alignment: .leading, spacing: 2) {
            menuItem("新建任务", "square.and.pencil", shortcut: "⌘N") {
                showNewTask()
            }
            .help("新建任务 (⌘N)")
            .accessibilityLabel("新建任务, 快捷键 ⌘N")
            menuItem("搜索", "magnifyingglass", shortcut: "⌘K") {
                withAnimation(.easeOut(duration: 0.16)) { showSearchField = true }
                searchFocused = true
            }
            .help("搜索任务 (⌘K)")
            .accessibilityLabel("搜索, 快捷键 ⌘K")
            // 「自进化日志」是只读历史页，不进一级导航；保留在底部用户菜单里就够了。
            menuItem("插件市场", "shippingbox") {
                showPluginManager = true
            }
            .help("浏览和管理插件")
            .accessibilityLabel("插件市场")
            menuItem("定时任务", "clock.arrow.circlepath") {
                showScheduledTasks = true
            }
            .help("定时任务：到点自动注入提示词")
            .accessibilityLabel("定时任务")
        }
        .padding(.horizontal, SidebarMetrics.inset)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func menuItem(_ title: String, _ icon: String, shortcut: String? = nil, action: @escaping () -> Void) -> some View {
        SidebarNavigationRow(title: title, icon: icon, shortcut: shortcut, action: action)
    }

    private var sidebarViewMode: SidebarViewMode {
        SidebarViewMode(rawValue: sidebarViewModeRaw) ?? .groups
    }

    private var sidebarViewControl: some View {
        HStack(spacing: 8) {
            Text("任务").font(.system(size: 11 * appFontScale.multiplier, weight: .medium)).foregroundStyle(DSHTheme.labelDim)
            Spacer()
            Button { showViewOptions = true } label: {
                Image(systemName: "line.3.horizontal.decrease").frame(width: 22, height: 24)
            }
            .buttonStyle(.plain)
            .help("显示方式与筛选")
            .accessibilityLabel("显示方式与筛选")
            .popover(isPresented: $showViewOptions) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(SidebarViewMode.allCases) { mode in
                        accountAction(mode.title, icon: sidebarViewMode == mode ? "checkmark" : "circle") {
                            sidebarViewModeRaw = mode.rawValue
                            showViewOptions = false
                        }
                    }
                    Divider()
                    accountAction("搜索任务", icon: "magnifyingglass") {
                        showViewOptions = false; showSearchField = true; searchFocused = true
                    }
                    if sidebarViewMode == .projects {
                        accountAction("全部展开或收起", icon: "rectangle.compress.vertical") {
                            let ids = Set(grouped.filter { $0.project != nil }.map(\.id))
                            if ids.isSubset(of: collapsedGroups) { collapsedGroups.subtract(ids) }
                            else { collapsedGroups.formUnion(ids) }
                            showViewOptions = false
                        }
                    }
                    accountAction("浏览远程目录与更多项目…", icon: "globe") {
                        showViewOptions = false
                        NotificationCenter.default.post(name: .tapgoRequestProjectPicker, object: nil)
                    }
                }.padding(8).frame(width: 250)
            }
            Button {
                NotificationCenter.default.post(name: .tapgoRequestOpenLocalFolder, object: nil)
            } label: { Image(systemName: "folder.badge.plus").frame(width: 22, height: 24) }
            .buttonStyle(.plain)
            .help("添加项目")
            .accessibilityLabel("添加项目")
        }
        .font(.system(size: 12))
        .foregroundStyle(DSHTheme.labelDim)
        .padding(.horizontal, 18)
        .padding(.top, 12).padding(.bottom, 6)
    }

    private enum SidebarViewMode: String, CaseIterable, Identifiable {
        case groups
        case projects
        var id: String { rawValue }
        var title: String { self == .groups ? "所有任务" : "按项目分组" }
    }

    // MARK: - Search

    @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
            TextField("搜索任务", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                .focused($searchFocused)
                .onExitCommand {
                    if !searchQuery.isEmpty { searchQuery = "" }
                    else { showSearchField = false; searchFocused = false }
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
        .padding(.bottom, 7)
        .accessibilityLabel("搜索任务")
    }

    // MARK: - TapgoCore.Thread list

    @ViewBuilder
    private var threadList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
            if grouped.isEmpty || (sidebarViewMode == .groups && flattenedThreads.isEmpty) {
                emptyState
            } else if sidebarViewMode == .groups {
                ForEach(flattenedThreads) { thread in
                    Button {
                        store.selectThread(thread.id)
                    } label: {
                        threadRow(thread, indented: false)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { contextMenu(for: thread) }
                }
            } else {
                ForEach(grouped.filter { $0.project != nil }, id: \.id) { group in
                    threadSection(for: group)
                }
                if !flatTaskThreads.isEmpty {
                    sidebarSectionHeading("其他任务", actionIcon: "plus") { showNewTask() }
                }
                ForEach(flatTaskThreads) { thread in
                    Button {
                        store.selectThread(thread.id)
                    } label: {
                        threadRow(thread, indented: false)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { contextMenu(for: thread) }
                }
            }
            }
            .padding(.horizontal, SidebarMetrics.inset)
            .padding(.bottom, 10)
        }
        .background(DSHTheme.sidebarBg)
    }

    private func sidebarSectionHeading(_ title: String, actionIcon: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier).weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: action) {
                Image(systemName: actionIcon)
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(title == "项目" ? "添加项目" : "新建任务")
        }
        .padding(.top, 14).padding(.bottom, 4)
        .padding(.horizontal, SidebarMetrics.rowInset)
    }

    /// Render a single project (or the legacy "未分类" bucket) as a
    /// `Section`. The body honours the user's collapsed flag and the
    /// per-group pagination limit (default 5, +10 per "展开显示" tap).
    @ViewBuilder
    private func threadSection(for group: ThreadGroup) -> some View {
        let visible = visibleThreads(in: group)
        let limit = threadLimit(for: group)
        VStack(alignment: .leading, spacing: 2) {
            projectGroupHeader(group)
            if isSearching || !collapsedGroups.contains(group.id) {
                // Keep project children visually flat and compact:
                // one title per row, ordered by recency.
                ForEach(Array(visible)) { t in
                    Button {
                        store.selectThread(t.id)
                    } label: {
                        threadRow(t)
                    }
                        .buttonStyle(.plain)
                        .contextMenu { contextMenu(for: t) }
                }
                if !isSearching, group.threads.count > limit {
                    expandThreadsButton(for: group)
                }
            }
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
                Text("显示更多")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                Text("\(remaining)")
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(DSHTheme.labelDim)
            .padding(.vertical, 7)
            .padding(.leading, SidebarMetrics.childInset)
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
            HStack(spacing: 2) {
                Button { toggleGroup(group.id) } label: {
                    SidebarProjectLabel(title: p.displayName, remote: p.isRemote,
                                        collapsed: !isSearching && collapsedGroups.contains(group.id),
                                        pinned: workspace.isProjectPinned(p.id), running: groupHasRunningTask(group),
                                        hovering: hoveredProjectId == p.id)
                }
                .buttonStyle(.plain)
                .disabled(isSearching)
                .accessibilityLabel("项目：\(p.displayName)")
                .accessibilityValue(isSearching || !collapsedGroups.contains(group.id) ? "已展开" : "已折叠")
                Button {
                    store.setActiveProject(p.id)
                    showNewTask()
                } label: { Image(systemName: "plus").font(.system(size: 11)).frame(width: 20, height: 24) }
                .buttonStyle(.plain)
                .accessibilityLabel("在 \(p.displayName) 中新建任务")
                .help("在此项目中新建任务")
                .opacity(hoveredProjectId == p.id ? 1 : 0.25)
                projectMoreMenu(p)
                    .frame(width: 20)
                    .opacity(hoveredProjectId == p.id ? 1 : 0.25)
            }
            .padding(.horizontal, SidebarMetrics.rowInset)
            .frame(height: 32 * appFontScale.multiplier)
            .contentShape(Rectangle())
            .background(hoveredProjectId == p.id ? DSHTheme.sidebarHover : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .onHover { hovering in
                hoveredProjectId = hovering ? p.id : (hoveredProjectId == p.id ? nil : hoveredProjectId)
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
            .help(p.displayPath)
            } else {
            HStack(spacing: 4) {
                Image(systemName: "tray")
                Text(group.customTitle ?? L10n.legacyGroupTitle)
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
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
                .frame(width: SidebarMetrics.icon, alignment: .leading)
            Text("自进化")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier).weight(.semibold))
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
        .menuIndicator(.hidden)
        .help("项目操作")
        .accessibilityLabel("项目操作")
    }

    /// Pinned threads first, then most-recent.
    private func sortedThreads(_ threads: [TapgoCore.Thread]) -> [TapgoCore.Thread] {
        threads.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    @ViewBuilder
    private func threadRow(_ t: TapgoCore.Thread, indented: Bool = true) -> some View {
        SidebarTaskLabel(title: t.title, date: relativeDate(for: t.updatedAt),
                         status: t.turns.last?.status, pinned: t.isPinned,
                         selected: store.activeThreadId == t.id, indented: indented)
    }

    private func relativeDate(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "今天" }
        if Calendar.current.isDateInYesterday(date) { return "昨天" }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 7 { return "\(max(1, days))天" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
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

    /// 左下角灰色行: 当前模型供应商 / 套餐名或余额 / 「5小时余量%/周余量%」。
    /// 供应商跟随当前选中的模型 (v0.5.31)。v0.5.33 起 GLM 接 BigModel
    /// 官方余量接口 (planLabel 如 Lite); v0.5.35 起 DeepSeek 按量计费,
    /// 显示接口返回的余额 (如 ¥17.95 CNY), 无窗口百分比。
    private var modelQuotaSummary: String {
        var parts: [String]
        let snapshot = store.rateLimits
        let selected = TapgoConfig.resolveSelected()
        switch selected.builtIn {
        case .minimaxM3:
            // MiniMax 接口不返回套餐名, 用本地常量 (实际订阅 Ultra)。
            parts = ["MiniMax", TapgoConfig.planDisplayName]
        case .glm53Flash:
            parts = ["GLM", snapshot?.planLabel ?? "Coding Plan"]
        case .deepSeekV4Flash, .deepSeekV4Pro:
            parts = ["DeepSeek"]
            if let credits = snapshot?.credits, credits.isVisible, !credits.balance.isEmpty {
                parts.append("余额 \(credits.balance)")
            }
            return parts.joined(separator: "·")
        case nil:
            return "\(selected.displayName)·自定义"
        }
        var quota: [String] = []
        if let primary = snapshot?.primary {
            quota.append("\(max(0, 100 - primary.usedPercent))%")
        }
        if let weekly = snapshot?.secondary, weekly.windowDurationMins == 10080 {
            quota.append("\(max(0, 100 - weekly.usedPercent))%")
        }
        if !quota.isEmpty { parts.append(quota.joined(separator: "/")) }
        return parts.joined(separator: "·")
    }

    @ViewBuilder
    private var userBar: some View {
        HStack(alignment: .center, spacing: 2) {
            Button { showAccountMenu = true } label: {
                SidebarAccountLabel(name: authStore.currentUser?.displayName ?? NSUserName()) {
                    if let user = authStore.currentUser {
                        UserAvatar(url: user.avatarURL, name: user.displayName, size: 24)
                    } else {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 24)).foregroundStyle(DSHTheme.labelDim)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("账户与快捷操作\n\(modelQuotaSummary)")
            .accessibilityLabel("用户与快捷操作菜单")
            .popover(isPresented: $showAccountMenu) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(authStore.currentUser?.displayName ?? NSUserName()).font(.headline).padding(8)
                    Divider()
                    accountAction("设置", icon: "gearshape") { showSettings() }
                    accountAction("连接手机", icon: "iphone.gen3.radiowaves.left.and.right") { showConnectPhone = true }
                    accountAction("自进化日志", icon: "clock.arrow.circlepath") { showEvolutionLog = true }
                    accountAction("自进化", icon: "sparkles") {
                        if !store.openEvolution() { showEvolutionRootMissing = true }
                    }
                    if authStore.currentUser != nil {
                        Divider()
                        accountAction("退出登录", icon: "rectangle.portrait.and.arrow.right", role: .destructive) { authStore.logout() }
                    }
                }.padding(8).frame(width: 250)
            }
            updateBadgeButton
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(DSHTheme.sidebarBg)
        .overlay(alignment: .top) { Rectangle().fill(DSHTheme.border.opacity(0.5)).frame(height: 0.5) }
        .task {
            // Keep quota truth fresh for the tooltip without reserving a
            // permanent second row in the compact footer.
            store.refreshRateLimits()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                store.refreshRateLimits()
            }
        }
    }

    private func accountAction(_ title: String, icon: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        SidebarNavigationRow(title: title, icon: icon, role: role) {
            showAccountMenu = false
            action()
        }
    }

    /// Codex 风格的次要更新入口：昵称右侧保留紧凑图标，有新版本时再用品牌色强调。
    /// 图标，否则是灰色的向上箭头；点击执行检查更新。不放进账户菜单。
    private var updateBadgeButton: some View {
        Button {
            updater.checkForUpdates()
        } label: {
            Image(systemName: updater.updateFound ? "arrow.down.circle.fill" : "arrow.up.circle")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(updater.updateFound ? DSHTheme.brand : Color.secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(!updater.canCheckForUpdates)
        .help(updater.updateFound ? "有可用更新，点击查看" : "检查更新")
        .accessibilityLabel(updater.updateFound ? "有可用更新" : "检查更新")
    }

    // MARK: - Grouping

    private struct ThreadGroup: Identifiable {
        let project: Project?
        let threads: [TapgoCore.Thread]
        /// True for the pinned 自进化 group: independent of projects,
        /// always sorted to the very top of the sidebar.
        var isEvolutionGroup: Bool = false
        var customTitle: String? = nil
        var customId: String? = nil
        var id: String { customId ?? (isEvolutionGroup ? "_evolution" : (project?.id ?? "_legacy")) }
    }

    /// ZCode「分组」页的默认形态是无项目标题的扁平任务列表。
    private var flattenedThreads: [TapgoCore.Thread] {
        sortedThreads(grouped.flatMap(\.threads))
    }

    /// ZCode「项目」页把无项目任务放在独立的「任务」分区；Tapgo 的
    /// 自进化任务也归在这里，而不是伪装成项目。
    private var flatTaskThreads: [TapgoCore.Thread] {
        sortedThreads(grouped.filter { $0.project == nil }.flatMap(\.threads))
    }

    private var grouped: [ThreadGroup] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Threads grouped by project. Search filter narrows the set;
        // empty groups are dropped so the sidebar doesn't show dead
        // project headers when nothing matches.
        var byProject: [String?: [TapgoCore.Thread]] = [:]
        // 自进化会话不参与项目分组——它们有独立的置顶分组。
        let evolutionThreads = store.liveThreads.filter {
            $0.isEvolution && (!showSearchField || !searchScope || $0.projectId == workspace.state.activeProjectId) && (!isSearching || threadMatchesSearch($0, query: trimmedQuery))
        }
        for t in store.liveThreads where !t.isEvolution && !t.isAuxiliary {
            // "仅当前项目" scope narrows to the active project's threads.
            if showSearchField && searchScope, t.projectId != workspace.state.activeProjectId { continue }
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
                .filter { !seenProjectIds.contains($0.id) && (!showSearchField || !searchScope || $0.id == workspace.state.activeProjectId) }
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
        let orderedIDs = SidebarPresentation.projectIDs(workspace.state.projects.map(\.id),
                                                        pinned: Set(workspace.state.projects.filter { workspace.isProjectPinned($0.id) }.map(\.id)))
        let ranks = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($0.element, $0.offset) })
        groups.sort { lhs, rhs in
            if lhs.isEvolutionGroup != rhs.isEvolutionGroup { return lhs.isEvolutionGroup }
            return (ranks[lhs.project?.id ?? ""] ?? Int.max) < (ranks[rhs.project?.id ?? ""] ?? Int.max)
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
        let ordered = sidebarViewMode == .groups ? flattenedThreads :
            grouped.filter { $0.project != nil && (isSearching || !collapsedGroups.contains($0.id)) }
                .flatMap { visibleThreads(in: $0) } + flatTaskThreads
        guard !ordered.isEmpty else { return }
        let active = store.activeThreadId
        let idx = ordered.firstIndex { $0.id == active } ?? (delta > 0 ? -1 : 0)
        let next = (idx + delta + ordered.count) % ordered.count
        store.selectThread(ordered[next].id)
    }
}

/// Circular user avatar with a graceful fallback (initial letter) when the
/// image is missing, loading, or fails to load.
///
/// macOS 26 的 Menu 只保留 label 里的 Text 和 Image 节点、其余视图全部丢弃，
/// 且 Image 按位图原尺寸绘制（frame/clipShape/overlay 一律被绕过，v0.5.62 侧栏
/// 头像因此被撑成 132pt 原图）。所以头像必须在进视图树之前就由
/// `UserAvatarRenderer` 渲染成目标尺寸的圆形小图。
struct UserAvatar: View {
    let url: URL?
    let name: String
    let size: CGFloat

    @State private var rendered: NSImage?

    var body: some View {
        ZStack {
            if let rendered {
                Image(nsImage: rendered)
                    .resizable()
                    .interpolation(.high)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .clipped()
        .task(id: url) {
            rendered = await UserAvatarRenderer.image(url: url, name: name, size: size)
        }
    }
}

/// 在视图树之外把头像（下载的原图或首字母占位）渲染成"最终尺寸 + 圆形"的
/// NSImage，并对 (url, size) / (name, size) 做进程内缓存。
@MainActor
enum UserAvatarRenderer {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(url: URL?, name: String, size: CGFloat) async -> NSImage {
        if let url {
            let key = "\(url.absoluteString)#\(Int(size))" as NSString
            if let hit = cache.object(forKey: key) { return hit }
            if let (data, response) = try? await URLSession.shared.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let raw = NSImage(data: data),
               let rendered = render(Image(nsImage: raw).resizable().scaledToFill(),
                                     name: name, size: size) {
                cache.setObject(rendered, forKey: key)
                return rendered
            }
        }
        let fallbackKey = "initial|\(name)|\(Int(size))" as NSString
        if let hit = cache.object(forKey: fallbackKey) { return hit }
        let rendered = render(fallback(name: name, size: size), name: name, size: size)
            ?? placeholder(size: size)
        cache.setObject(rendered, forKey: fallbackKey)
        return rendered
    }

    private static func render(_ content: some View, name: String, size: CGFloat) -> NSImage? {
        let renderer = ImageRenderer(
            content: content
                .frame(width: size, height: size)
                .clipShape(Circle())
        )
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: size, height: size)
        return renderer.nsImage
    }

    private static func fallback(name: String, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(DSHTheme.brand.opacity(0.18))
            Text(initial(of: name))
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(DSHTheme.brand)
        }
    }

    private static func placeholder(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        image.unlockFocus()
        return image
    }

    private static func initial(of name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1)).uppercased()
    }
}
