import SwiftUI
import TapgoCore

/// Modal sheet for creating a new task. Two flows:
///   1. Pick a local directory (NSOpenPanel) → new local project +
///      first thread.
///   2. Pick an existing local/remote project from the recent list.
///   3. "Quick" option creates a project-less thread.
struct NewTaskView: View {
    @EnvironmentObject var workspace: WorkspaceStore
    @EnvironmentObject var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    /// Called with the selected project (or nil for quick).
    let onCreate: (Project?) -> Void
    /// v0.5.171: 从 sidebar 项目组 + 按钮进入时预选 active project。nil = 不预选（user 自己选）。
    /// v0.5.172: 改为 let（caller 设），user 取消预选走下面的 @State override。
    let preselectedProject: Project?
    /// v0.5.172: 本地可写覆盖 — user 在 preselectedHint 点 X 取消预选。
    @State private var preselectedOverride: Project?

    @State private var showLocalPicker = false
    @State private var error: String?
    @State private var showRemoteSheet = false
    @State private var hoveredProjectId: String? = nil
    // v0.5.179: 默认 focus 在 footer 取消按钮（避免 Enter 误触发"本地项目"选择）。
    @FocusState private var cancelFocused: Bool
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    primaryActions
                    if preselectedOverride ?? preselectedProject != nil {
                        preselectedHint
                    }
                    Divider()
                    recentSection
                }
                .padding(20)
            }
            // v0.5.163: 加 footer，左下"取消"按钮（之前只有右上 X，太隐蔽）。
            Divider()
            footer
        }
        .frame(width: 520, height: 480)
        // v0.5.179: sheet 显示时默认 focus 取消按钮。
        .onAppear { cancelFocused = true }
        .alert("打开本地目录失败", isPresented: Binding(
            get: { error != nil }, set: { _ in error = nil }
        )) {
            Button("确定") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .sheet(isPresented: $showRemoteSheet) {
            RemoteDirectoryBrowser { host, path in
                let p = Project(
                    id: "remote-" + UUID().uuidString,
                    displayName: "\(host.alias):\(path)",
                    kind: .remote,
                    addedAt: Date(),
                    lastUsedAt: Date(),
                    worktreeRoot: localMirrorDir(for: host, path: path),
                    bookmark: nil,
                    remoteHostId: host.id,
                    remotePath: path
                )
                workspace.addProject(p)
                onCreate(workspace.state.projects.first(where: { $0.remoteHostId == p.remoteHostId && $0.remotePath == p.remotePath }) ?? p)
                dismiss()
            }
            .environmentObject(workspace)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    /// v0.5.171: 预选提示 — 从 sidebar + 按钮进入时显示当前 project 让 user 确认。
    /// v0.5.172: 改用 preselectedOverride 允许 user 点 X 取消预选。
    private var preselectedHint: some View {
        if let p = preselectedOverride ?? preselectedProject {
            HStack(spacing: 8) {
                Image(systemName: p.isRemote ? "globe" : "folder")
                    .foregroundStyle(.blue)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text("将在以下项目创建任务")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                    Text(p.displayName)
                        .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                        .bold()
                        .lineLimit(1)
                }
                Spacer()
                // v0.5.172: 点 X 取消预选（让 user 走 NewTaskView 默认行为）
                Button {
                    preselectedOverride = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("取消预选项目")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DSHTheme.interactiveHover, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("取消")
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            // v0.5.179: 打开时默认 focus 这个按钮（按 Enter 取消而不是选"本地项目"）。
            .focused($cancelFocused)
            .accessibilityLabel("取消新建任务")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Text(L10n.newTaskTitle).font(AppFont.scaled(.title3, multiplier: appFontScale.multiplier)).bold()
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("关闭")
        }
        .padding(20)
    }

    @ViewBuilder
    private var primaryActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.newTaskChooseProject).font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier))
            HStack(spacing: 12) {
                actionCard(
                    title: L10n.localFolder,
                    system: "folder.badge.plus",
                    color: .accentColor
                ) {
                    handlePickLocal()
                }
                actionCard(
                    title: L10n.remoteProject,
                    system: "globe.americas.fill",
                    color: .blue
                ) {
                    showRemoteSheet = true
                }
                actionCard(
                    // v0.5.174: 有 preselectedProject（sidebar + 按钮）时标题改"在 X 项目中创建"，
                    // 让 user 看到 preselectedOverride ?? preselectedProject 还在用。
                    title: {
                        if let p = preselectedOverride ?? preselectedProject {
                            return "\u{201C}" + p.displayName + "\u{201D}中创建"
                        }
                        return L10n.quickNoProject
                    }(),
                    system: "bolt.fill",
                    color: .secondary
                ) {
                    // v0.5.173: 选"快速"时如果 preselectedOverride 或 preselectedProject 仍有值，
                    // 用它而不是 nil（避免 sidebar + 按钮"我要在 X 项目创建"的意图被覆盖）。
                    let project = preselectedOverride ?? preselectedProject
                    onCreate(project)
                    dismiss()
                }
            }
            Text(L10n.quickNoProjectHint)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.recentProjects).font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier))
                Spacer()
                Text("\(workspace.recentProjects.count)")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
            }
            if workspace.recentProjects.isEmpty {
                Text(L10n.noRecentProjects)
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(workspace.recentProjects.prefix(6)) { p in
                        recentRow(p)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recentRow(_ p: Project) -> some View {
        Button {
            onCreate(p)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: p.isRemote ? "globe" : "folder")
                    .foregroundStyle(p.isRemote ? .blue : .accentColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.displayName).lineLimit(1)
                    Text(p.displayPath)
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(RelativeDateTimeFormatter().localizedString(for: p.lastUsedAt, relativeTo: Date()))
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(hoveredProjectId == p.id ? DSHTheme.interactiveHover : DSHTheme.surface,
                        in: RoundedRectangle(cornerRadius: 6))
            // v0.5.162: hover 时加 border 提示可点，跟 v0.5.160-161 actionCard 风格一致。
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(hoveredProjectId == p.id ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1.5)
            )
            .onHover { hovering in
                hoveredProjectId = hovering ? p.id : (hoveredProjectId == p.id ? nil : hoveredProjectId)
            }
            .accessibilityLabel("选择项目 \(p.displayName)")
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func actionCard(
        title: String, system: String, color: Color,
        action: @escaping () -> Void
    ) -> some View {
        ActionCard(title: title, system: system, color: color, action: action)
    }

    // v0.5.161 修：v0.5.160 把 @State 放在 func 里（编译器忽略，导致 hover 反馈不工作）。
    // 把 actionCard 改成 View struct，@State 写在 struct 属性里才能正确持有。
    private struct ActionCard: View {
        let title: String
        let system: String
        let color: Color
        let action: () -> Void
        @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale
        @State private var hovering = false
        var body: some View {
            Button(action: action) {
                VStack(spacing: 6) {
                    Image(systemName: system)
                        .font(AppFont.scaled(.title2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(color)
                    Text(title)
                        .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                }
                .frame(maxWidth: .infinity, minHeight: 80)
                .background(
                    hovering ? DSHTheme.interactiveHover : DSHTheme.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
                .overlay(
                    RoundedRectangle(cornerRadius: DSHTheme.radiusCard)
                        .stroke(hovering ? color.opacity(0.4) : .clear, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityLabel(title)
        }
    }

    // MARK: - Local pick

    private func handlePickLocal() {
        do {
            let result = try LocalDirectoryPicker.pickDirectory()
            let id = "local-" + UUID().uuidString
            let display = result.url.lastPathComponent.isEmpty ? result.url.path : result.url.lastPathComponent
            let project = Project(
                id: id,
                displayName: display,
                kind: .local,
                addedAt: Date(),
                lastUsedAt: Date(),
                worktreeRoot: result.url,
                bookmark: result.bookmark,
                remoteHostId: nil,
                remotePath: nil
            )
            workspace.addProject(project)
            onCreate(workspace.state.projects.first(where: { !$0.isRemote && $0.worktreeRoot == project.worktreeRoot }) ?? project)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Local mirror dir used as `cwd` for remote projects. The
    /// harness needs *some* local directory; we create a private
    /// one under the app support dir and never put real content
    /// there — remote exec goes through SSH.
    private func localMirrorDir(for host: RemoteHost, path: String) -> URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Tapgo AICoding/mirrors", isDirectory: true)
        let sanitizedAlias = host.alias.replacingOccurrences(of: "/", with: "_")
        let sanitizedPath = path
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let dir = base.appendingPathComponent("\(sanitizedAlias)__\(sanitizedPath)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
