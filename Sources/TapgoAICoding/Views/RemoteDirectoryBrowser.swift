import SwiftUI
import TapgoCore

/// Codex-style "pick a remote directory" sheet.
///
/// Flow:
///   1. Pick a host (defaults to the first registered remote host).
///   2. Start in `$HOME` (validated as `~`) — no plain `ls ~` dump
///      of every entry, just the immediate sub-directories the user
///      can navigate into.
///   3. Each list tap is a new SSH call. We debounce by only
///      loading on a deliberate row click or Enter in the path
///      field; the user never has to wait for a hidden background
///      re-fetch.
///   4. "Up" button walks one level at a time. Typed input lets
///      power users paste a path and Enter.
///   5. The confirm button is disabled until the path has been
///      successfully listed (so we don't commit a path the remote
///      can't see).
struct RemoteDirectoryBrowser: View {
    @EnvironmentObject var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    let onCommit: (RemoteHost, String) -> Void

    @State private var hostId: String = ""
    @State private var currentPath: String = "~"
    @State private var draftPath: String = "~"
    @State private var entries: [RemoteDirectoryLister.Entry] = []
    @State private var isLoading: Bool = false
    @State private var error: String?
    /// Recent paths the user has confirmed on this host, in MRU
    /// order. Capped at 5 to keep the UI slim; persisted in
    /// memory only (UserDefaults is overkill for navigation
    /// recents).
    @State private var recent: [String] = []
    @State private var didLoadOnce: Bool = false
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    private let lister = RemoteDirectoryLister()
    private let sshPath = RemoteCodexHomeSync.findSSH()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 540, height: 520)
        .onAppear {
            if hostId.isEmpty {
                hostId = workspace.state.remoteHosts.first?.id ?? ""
            }
            if !didLoadOnce {
                didLoadOnce = true
                Task { await refresh() }
            }
        }
        .onChange(of: hostId) { _, new in
            guard !new.isEmpty else { return }
            // Switching hosts resets the view to the new host's
            // home and clears the recents (they're per-host).
            currentPath = "~"
            draftPath = "~"
            recent = []
            entries = []
            error = nil
            Task { await refresh() }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("添加远程项目").font(AppFont.scaled(.title3, multiplier: appFontScale.multiplier)).bold()
                Text("选择主机,然后逐级浏览远程目录。")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("关闭")
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            hostPicker
            pathField
            navRow
            if isLoading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在读取 \(currentPath) …")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let err = error {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
            }
            directoryList
        }
        .padding(16)
    }

    @ViewBuilder
    private var hostPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe").foregroundStyle(.blue)
            Picker("主机", selection: $hostId) {
                if workspace.state.remoteHosts.isEmpty {
                    Text("未配置主机").tag("")
                }
                ForEach(workspace.state.remoteHosts) { h in
                    Text("\(h.alias)  (\(h.user)@\(h.host))").tag(h.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var pathField: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
            TextField("远程路径", text: $draftPath, onCommit: commitDraft)
                .textFieldStyle(.roundedBorder)
                .font(AppFont.monoScaled(size: 13, multiplier: appFontScale.multiplier))
                .onSubmit(commitDraft)
        }
    }

    @ViewBuilder
    private var navRow: some View {
        HStack(spacing: 8) {
            Button {
                Task { await goUp() }
            } label: {
                Label("上级", systemImage: "arrow.up")
            }
            .buttonStyle(.bordered)
            .help("返回上级目录")
            .disabled(isLoading || currentPath == "/" || currentPath.isEmpty)

            Button {
                draftPath = "~"
                commitDraft()
            } label: {
                Label("主目录", systemImage: "house")
            }
            .buttonStyle(.bordered)
            .help("跳到远程用户的 $HOME")
            .disabled(isLoading)

            Button {
                Task { await refresh() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("重新读取当前目录")
            .disabled(isLoading)

            Spacer()
        }
    }

    @ViewBuilder
    private var directoryList: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("子目录")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier)).bold()
                    .foregroundStyle(.secondary)
                Spacer()
                if !entries.isEmpty {
                    Text("\(entries.count) 个")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.tertiary)
                }
            }
            if entries.isEmpty && !isLoading && error == nil {
                Text("(空目录)")
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(entries) { e in
                            entryRow(e)
                        }
                    }
                }
                .frame(maxHeight: 180)
                .background(.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            if !recent.isEmpty {
                Divider().padding(.vertical, 2)
                Text("最近确认")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier)).bold()
                    .foregroundStyle(.secondary)
                ForEach(recent, id: \.self) { p in
                    Button {
                        draftPath = p
                        commitDraft()
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                                .foregroundStyle(.tertiary)
                            Text(p)
                                .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("跳到最近确认的路径 \(p)")
                }
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ e: RemoteDirectoryLister.Entry) -> some View {
        Button {
            // Concatenate using "/" rather than `URL.appendingPathComponent`
            // because we want POSIX paths verbatim; the remote
            // shell will resolve them. Always insert a slash
            // between currentPath and the entry, even when
            // currentPath is just `/`.
            let next: String
            if currentPath == "/" || currentPath.isEmpty {
                next = "/\(e.id)"
            } else if currentPath.hasSuffix("/") {
                next = currentPath + e.id
            } else {
                next = currentPath + "/" + e.id
            }
            draftPath = next
            currentPath = next
            Task { await refresh() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.blue)
                Text(e.id)
                    .font(AppFont.monoScaled(size: 13, multiplier: appFontScale.multiplier))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("进入 \(e.id)")
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Text(currentPath)
                .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("取消") { dismiss() }
            Button("以此目录创建") { commit() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || entries.isEmpty && error != nil
                          || hostId.isEmpty || currentPath.isEmpty)
        }
        .padding(16)
    }

    // MARK: - Actions

    private func commitDraft() {
        let trimmed = draftPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard RemoteCommandBuilder.validatePath(trimmed) != nil else {
            error = "路径含非法字符"
            return
        }
        currentPath = trimmed
        error = nil
        Task { await refresh() }
    }

    private func commit() {
        guard let host = workspace.remoteHost(byId: hostId) else {
            error = "未选主机"
            return
        }
        guard RemoteCommandBuilder.validatePath(currentPath) != nil else {
            error = "路径含非法字符"
            return
        }
        // Push to the recents list (MRU), dedup, cap at 5.
        var r = recent.filter { $0 != currentPath }
        r.insert(currentPath, at: 0)
        if r.count > 5 { r = Array(r.prefix(5)) }
        recent = r
        onCommit(host, currentPath)
        dismiss()
    }

    private func refresh() async {
        guard let host = workspace.remoteHost(byId: hostId) else {
            entries = []
            error = workspace.state.remoteHosts.isEmpty
                ? "尚未配置远程主机,先在 设置 → 远程主机 添加"
                : "未选主机"
            return
        }
        error = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await lister.listDirectories(
                sshPath: sshPath, host: host, path: currentPath
            )
            entries = result
        } catch let e as RemoteDirectoryLister.ListError {
            entries = []
            error = e.errorDescription
        } catch {
            entries = []
            self.error = error.localizedDescription
        }
    }

    private func goUp() async {
        var p = currentPath
        if p == "~" { p = "/Users/" + (workspace.remoteHost(byId: hostId)?.user ?? "") }
        if p == "/" || p.isEmpty { return }
        // Drop the last component. Handles both `/a/b/c` and
        // `/a/b/c/`. For `~` we special-case it to the user's
        // home (already handled above).
        if p.hasSuffix("/") && p.count > 1 {
            p = String(p.dropLast())
        }
        if let lastSlash = p.lastIndex(of: "/") {
            let parent = String(p[..<lastSlash])
            currentPath = parent.isEmpty ? "/" : parent
        } else {
            currentPath = "/"
        }
        draftPath = currentPath
        await refresh()
    }
}
