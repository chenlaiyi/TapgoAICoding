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

    @State private var showLocalPicker = false
    @State private var error: String?
    @State private var showRemoteSheet = false
    @State private var hoveredProjectId: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    primaryActions
                    Divider()
                    recentSection
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 460)
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
                store.newThread()
                onCreate(p)
                dismiss()
            }
            .environmentObject(workspace)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        HStack {
            Text(L10n.newTaskTitle).font(.title3).bold()
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
            Text(L10n.newTaskChooseProject).font(.headline)
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
                    title: L10n.quickNoProject,
                    system: "bolt.fill",
                    color: .secondary
                ) {
                    onCreate(nil)
                    store.newThread()
                    dismiss()
                }
            }
            Text(L10n.quickNoProjectHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.recentProjects).font(.headline)
                Spacer()
                Text("\(workspace.recentProjects.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if workspace.recentProjects.isEmpty {
                Text(L10n.noRecentProjects)
                    .font(.subheadline)
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
            workspace.setActiveProject(p.id)
            store.newThread()
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
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(RelativeDateTimeFormatter().localizedString(for: p.lastUsedAt, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(hoveredProjectId == p.id ? DSHTheme.interactiveHover : DSHTheme.surface,
                        in: RoundedRectangle(cornerRadius: 6))
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
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: system)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(DSHTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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
            store.newThread()
            onCreate(project)
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
