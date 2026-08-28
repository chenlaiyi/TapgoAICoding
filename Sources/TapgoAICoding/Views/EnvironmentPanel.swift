import SwiftUI
import TapgoCore
import UniformTypeIdentifiers

/// Environment info (project, path, model, endpoint, sandbox, approval,
/// reasoning effort, context) shown in the right sidebar. Default-open but
/// collapsible; the sandbox / approval / effort rows are quick-switch menus
/// and the endpoint row opens the run settings.
struct EnvironmentPanel: View {
    @EnvironmentObject var workspace: WorkspaceStore
    let thread: TapgoCore.Thread
    @State private var expanded = true

    @AppStorage(TapgoConfig.sandboxKey) private var sandboxRaw = TapgoConfig.SandboxMode.dangerFullAccess.rawValue
    @AppStorage(TapgoConfig.approvalPolicyKey) private var approvalPolicyRaw = TapgoConfig.ApprovalPolicy.never.rawValue
    @AppStorage(TapgoConfig.reasoningEffortKey) private var reasoningEffort = ""
    @State private var branch: String? = nil
    @State private var changes: Int? = nil
    @State private var remoteURL: String? = nil
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                if let project = thread.projectId.flatMap({ workspace.project(byId: $0) }) {
                    if project.isRemote {
                        row(icon: "globe", label: "项目", value: project.displayName)
                    } else {
                        buttonRow(icon: "folder.fill", label: "项目", value: project.displayName) {
                            NSWorkspace.shared.open(project.worktreeRoot)
                        }
                    }
                    pathRow(icon: "arrow.triangle.branch", label: "路径", path: project.displayPath, clickable: !project.isRemote)
                    row(icon: "server.rack", label: "来源",
                        value: project.isRemote
                            ? ("远程 · " + (project.remoteHostId.flatMap { workspace.remoteHost(byId: $0)?.alias } ?? project.remoteHostId ?? ""))
                            : "本地")
                    if !project.isRemote {
                        row(icon: "arrow.triangle.branch.circle", label: "分支", value: branch ?? "—")
                        changesRow
                    }
                } else if let cwd = thread.cwd, !cwd.isEmpty {
                    pathRow(icon: "arrow.triangle.branch", label: "路径", path: cwd, clickable: true)
                    row(icon: "server.rack", label: "来源", value: "本地")
                    row(icon: "arrow.triangle.branch.circle", label: "分支", value: branch ?? "—")
                    changesRow
                }
                row(icon: "cpu", label: "模型", value: TapgoConfig.modelName)
                row(icon: "globe.asia.australia", label: "区域", value: TapgoConfig.defaultRegion.displayName)
                // Endpoint → open run settings.
                buttonRow(icon: "network", label: "端点", value: TapgoConfig.effectiveBaseURL) {
                    NotificationCenter.default.post(name: .tapgoRequestOpenSettings, object: nil)
                }
                buttonRow(icon: "doc.text", label: "配置", value: "config.toml") {
                    if FileManager.default.fileExists(atPath: TapgoConfig.configPath.path) {
                        NSWorkspace.shared.open(TapgoConfig.configPath)
                    } else {
                        NSWorkspace.shared.activateFileViewerSelecting([TapgoConfig.configPath])
                    }
                }
                if let project = thread.projectId.flatMap({ workspace.project(byId: $0) }), !project.isRemote {
                    let agents = project.worktreeRoot.appendingPathComponent("AGENTS.md")
                    let readme = project.worktreeRoot.appendingPathComponent("README.md")
                    if FileManager.default.fileExists(atPath: agents.path) {
                        buttonRow(icon: "doc.text", label: "文档", value: "AGENTS.md") {
                            NSWorkspace.shared.open(agents)
                        }
                    } else if FileManager.default.fileExists(atPath: readme.path) {
                        buttonRow(icon: "doc.text", label: "文档", value: "README.md") {
                            NSWorkspace.shared.open(readme)
                        }
                    }
                }
                if let remote = remoteURL {
                    buttonRow(icon: "globe", label: "远程仓库", value: remote) {
                        openRemote(remote)
                    }
                }
                menuRow(icon: "lock.shield", label: "沙箱",
                        value: TapgoConfig.SandboxMode(rawValue: sandboxRaw)?.displayName ?? "") {
                    ForEach(TapgoConfig.SandboxMode.allCases) { m in
                        Button { sandboxRaw = m.rawValue } label: {
                            Text(m.displayName)
                        }
                    }
                }
                menuRow(icon: "checkmark.shield", label: "批准",
                        value: TapgoConfig.ApprovalPolicy(rawValue: approvalPolicyRaw)?.displayName ?? "") {
                    ForEach(TapgoConfig.ApprovalPolicy.allCases) { p in
                        Button { approvalPolicyRaw = p.rawValue } label: {
                            Text(p.displayName)
                        }
                    }
                }
                menuRow(icon: "brain", label: "思考", value: self.effortLabel) {
                    Button { reasoningEffort = "" } label: { Text("默认 (模型定)") }
                    Button { reasoningEffort = "none" } label: { Text("无 (none)") }
                    Button { reasoningEffort = "low" } label: { Text("低 (low)") }
                    Button { reasoningEffort = "medium" } label: { Text("中 (medium)") }
                    Button { reasoningEffort = "high" } label: { Text("高 (high)") }
                }
                if let usage = thread.turns.last(where: { $0.usage != nil })?.usage,
                   let pct = usage.contextPercent {
                    contextMeter(percent: pct, level: usage.contextLevel)
                }
                if let cw = thread.turns.last(where: { $0.usage?.contextWindow != nil })?.usage?.contextWindow {
                    row(icon: "rectangle.3.group", label: "上下文上限", value: shortCount(cw))
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Text("环境信息")
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                    .bold()
                Spacer()
                Button {
                    branch = nil
                    changes = nil
                    Task { await loadBranch() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                }
                .buttonStyle(.borderless)
                .help("刷新环境信息")
                .accessibilityLabel("刷新环境信息")
                Button {
                    copyText(summaryText)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                }
                .buttonStyle(.borderless)
                .help("复制环境信息")
                .accessibilityLabel("复制环境信息")
            }
        }
        .padding(12)
        .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: DSHTheme.radiusCard).stroke(DSHTheme.border, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .task { await loadBranch() }
    }

    /// Reads the local project's git branch off the main thread once.
    private func loadBranch() async {
        let path: String
        if let project = thread.projectId.flatMap({ workspace.project(byId: $0) }),
           !project.isRemote {
            path = project.worktreeRoot.path
        } else {
            path = thread.cwd ?? ""
        }
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }
        let result = await Task.detached(priority: .utility) {
            (GitInfo.branch(at: path), GitInfo.changesCount(at: path), GitInfo.remoteURL(at: path))
        }.value
        if self.branch == nil { self.branch = result.0 }
        if self.changes == nil { self.changes = result.1 }
        if self.remoteURL == nil { self.remoteURL = result.2 }
    }

    /// Green "变更" count row (Codex-style), hidden when the repo is clean.
    @ViewBuilder
    private var changesRow: some View {
        let n = changes ?? 0
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "arrow.up.arrow.down")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text("变更")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(n > 0 ? "+\(n)" : "干净")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(n > 0 ? DSHTheme.success : .secondary)
                .lineLimit(1)
        }
    }

    private var effortLabel: String {
        switch reasoningEffort {
        case "none": return "无 (none)"
        case "low": return "低 (low)"
        case "medium": return "中 (medium)"
        case "high": return "高 (high)"
        default: return "默认"
        }
    }

    /// Context-usage meter: a full-width bar coloured by pressure, with
    /// the label + percentage above it. Mirrors Codex's context meter.
    @ViewBuilder
    private func contextMeter(percent: Int, level: TapgoCore.ContextLevel?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "gauge.medium")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text("上下文")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("\(percent)%")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.primary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.gray.opacity(0.15))
                    Capsule()
                        .fill(contextColor(level))
                        .frame(width: g.size.width * CGFloat(percent) / 100)
                }
            }
            .frame(height: 4)
            .padding(.leading, 22)
        }
    }

    private func contextColor(_ level: TapgoCore.ContextLevel?) -> Color {
        switch level {
        case .critical: return .red
        case .warn: return .orange
        case .normal: return .green
        case .none: return .secondary
        }
    }

    private func shortCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fk", Double(n) / 1_000) }
        return "\(n)"
    }

    /// Plain-text summary of the panel, copied via the header button.
    private var summaryText: String {
        var lines: [String] = []
        if let project = thread.projectId.flatMap({ workspace.project(byId: $0) }) {
            lines.append("项目: \(project.displayName)")
            lines.append("路径: \(project.displayPath)")
            lines.append("来源: \(project.isRemote ? ("远程 · " + (project.remoteHostId ?? "")) : "本地")")
            if !project.isRemote {
                if let b = branch { lines.append("分支: \(b)") }
                let n = changes ?? 0
                lines.append("变更: \(n > 0 ? "+\(n)" : "干净")")
            }
        } else if let cwd = thread.cwd, !cwd.isEmpty {
            lines.append("路径: \(cwd)")
            lines.append("来源: 本地")
        }
        lines.append("模型: \(TapgoConfig.modelName)")
        lines.append("端点: \(TapgoConfig.effectiveBaseURL)")
        lines.append("沙箱: \(TapgoConfig.SandboxMode(rawValue: sandboxRaw)?.displayName ?? "")")
        lines.append("批准: \(TapgoConfig.ApprovalPolicy(rawValue: approvalPolicyRaw)?.displayName ?? "")")
        lines.append("思考: \(effortLabel)")
        if let usage = thread.turns.last(where: { $0.usage != nil })?.usage {
            if let pct = usage.contextPercent { lines.append("上下文: \(pct)%") }
            if let cw = usage.contextWindow { lines.append("上下文上限: \(shortCount(cw))") }
        }
        return lines.joined(separator: "\n")
    }

    private func copyText(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    private func row(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    /// Path row that opens the local folder in Finder on click. Remote
    /// project rows render the path non-interactively (no local directory).
    private func pathRow(icon: String, label: String, path: String, clickable: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(path)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard clickable else { return }
                    openInFinder(path)
                }
                .contextMenu {
                    Button {
                        openInFinder(path)
                    } label: {
                        Label("在访达中显示", systemImage: "folder")
                    }
                    Button {
                        openInTerminal(path)
                    } label: {
                        Label("在终端中打开", systemImage: "terminal")
                    }
                }
        }
    }

    private func openInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openInTerminal(_ path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Terminal", path]
        try? p.run()
    }

    private var localWorktreePath: String {
        if let project = thread.projectId.flatMap({ workspace.project(byId: $0) }), !project.isRemote {
            return project.worktreeRoot.path
        }
        return thread.cwd ?? ""
    }

    private func openRemote(_ remote: String) {
        var u = remote
        if u.hasPrefix("git@") { u = "https://" + u.dropFirst(4).replacingOccurrences(of: ":", with: "/") }
        else if u.hasPrefix("git://") { u = "https://" + u.dropFirst(6) }
        if let url = URL(string: u) { NSWorkspace.shared.open(url) }
    }

    private func buttonRow(icon: String, label: String, value: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button(action: action) {
                HStack(spacing: 3) {
                    Text(value)
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private func menuRow(icon: String, label: String, value: String, @ViewBuilder menu: @escaping () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Menu {
                menu()
            } label: {
                HStack(spacing: 3) {
                    Text(value)
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.tertiary)
                }
            }
            .menuStyle(.borderlessButton)
        }
    }
}

/// Codex-style compact environment/source card used only when the main
/// window has enough horizontal room. The complete EnvironmentPanel and
/// TrajectoryView remain available through the toolbar; this card is a
/// glanceable, responsive summary rather than a replacement for them.
struct AdaptiveEnvironmentCard: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @EnvironmentObject private var store: SessionStore
    let thread: TapgoCore.Thread

    @State private var branch: String?
    @State private var remoteURL: String?
    @State private var changeSummary: GitChangeSummary?
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("环境信息", actionLabel: "打开完整轨迹栏") {
                NotificationCenter.default.post(name: .tapgoToggleTrajectory, object: nil)
            }

            VStack(alignment: .leading, spacing: 10) {
                changeRow
                actionRow(
                    icon: project?.isRemote == true ? "globe" : "externaldrive",
                    label: sourceLabel,
                    trailingIcon: "chevron.down"
                ) {
                    openWorkspace()
                }
                valueRow(icon: "arrow.triangle.branch", value: branch ?? "—", trailingIcon: "chevron.down")
                actionRow(icon: "slider.horizontal.3", label: "提交或推送") {
                    openInTerminal()
                }
                actionRow(icon: "arrow.triangle.pull", label: "比较分支", trailingIcon: "arrow.up.right") {
                    openComparison()
                }
            }

            Divider()

            sectionHeader("来源", actionLabel: "添加图片来源") {
                pickSources()
            }

            if sourceURLs.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                    Text("暂无图片来源")
                }
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.tertiary)
                .padding(.vertical, 3)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(sourceURLs.prefix(3)), id: \.path) { url in
                        sourceRow(url)
                    }
                    Button {
                        revealAllSources()
                    } label: {
                        Label("查看全部", systemImage: "link")
                            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DSHTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .task(id: refreshKey) {
            await refreshGitSummary()
        }
    }

    private var project: Project? {
        thread.projectId.flatMap { workspace.project(byId: $0) }
    }

    private var worktreePath: String {
        if let project, !project.isRemote { return project.worktreeRoot.path }
        return thread.cwd ?? ""
    }

    private var sourceLabel: String {
        guard let project else { return "本地" }
        if project.isRemote {
            let host = project.remoteHostId.flatMap { workspace.remoteHost(byId: $0)?.alias }
                ?? project.remoteHostId
                ?? "远程"
            return host
        }
        return "本地"
    }

    private var refreshKey: String {
        let last = thread.turns.last
        return "\(thread.id):\(last?.items.count ?? 0):\(last?.status.rawValue ?? "none")"
    }

    private var sourceURLs: [URL] {
        let persisted = thread.turns.flatMap(\.userImagePaths).map { URL(fileURLWithPath: $0) }
        let candidates = persisted + store.attachedImages
        var seen: Set<String> = []
        return candidates.reversed().compactMap { url in
            guard seen.insert(url.path).inserted else { return nil }
            return url
        }
    }

    @ViewBuilder
    private var changeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plusminus.square")
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text("变更")
                .font(AppFont.scaled(.callout, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let summary = changeSummary, summary.files > 0 {
                Text("+\(summary.additions)")
                    .foregroundStyle(DSHTheme.success)
                Text("-\(summary.deletions)")
                    .foregroundStyle(DSHTheme.error)
            } else {
                Text("干净")
                    .foregroundStyle(.secondary)
            }
        }
        .font(AppFont.monoScaled(size: 12, multiplier: appFontScale.multiplier))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(changeAccessibilityLabel)
    }

    private var changeAccessibilityLabel: String {
        guard let summary = changeSummary, summary.files > 0 else { return "工作树干净" }
        return "\(summary.files) 个文件已更改，增加 \(summary.additions) 行，删除 \(summary.deletions) 行"
    }

    private func sectionHeader(
        _ title: String,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: action) {
                Image(systemName: "plus")
                    .font(AppFont.scaled(.callout, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(actionLabel)
            .accessibilityLabel(actionLabel)
        }
    }

    private func valueRow(icon: String, value: String, trailingIcon: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppFont.scaled(.callout, multiplier: appFontScale.multiplier))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func actionRow(
        icon: String,
        label: String,
        trailingIcon: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            valueRow(icon: icon, value: label, trailingIcon: trailingIcon)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sourceRow(_ url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 9) {
                Group {
                    if let image = NSImage(contentsOf: url) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                Text(url.lastPathComponent)
                    .font(AppFont.scaled(.callout, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("打开 \(url.lastPathComponent)")
    }

    private func refreshGitSummary() async {
        let path = worktreePath
        guard !path.isEmpty, project?.isRemote != true else { return }
        let result = await Task.detached(priority: .utility) {
            (
                GitInfo.branch(at: path),
                GitInfo.remoteURL(at: path),
                GitInfo.changeSummary(at: path)
            )
        }.value
        branch = result.0
        remoteURL = result.1
        changeSummary = result.2
    }

    private func openWorkspace() {
        if let project, project.isRemote {
            openComparison()
            return
        }
        let path = worktreePath
        guard !path.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    private func openInTerminal() {
        let path = worktreePath
        guard !path.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", path]
        try? process.run()
    }

    private func openComparison() {
        guard let remoteURL else {
            openInTerminal()
            return
        }
        var value = remoteURL
        if value.hasPrefix("git@") {
            value = "https://" + value.dropFirst(4).replacingOccurrences(of: ":", with: "/")
        } else if value.hasPrefix("git://") {
            value = "https://" + value.dropFirst(6)
        }
        if value.hasSuffix(".git") { value.removeLast(4) }
        if let url = URL(string: value) { NSWorkspace.shared.open(url) }
    }

    private func pickSources() {
        let panel = NSOpenPanel()
        panel.title = "添加图片来源"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            store.addImages(panel.urls)
        }
    }

    private func revealAllSources() {
        let urls = sourceURLs
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
