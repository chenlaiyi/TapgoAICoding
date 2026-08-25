import SwiftUI
import TapgoCore

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
                    .font(.subheadline)
                    .bold()
                Spacer()
                Button {
                    branch = nil
                    changes = nil
                    Task { await loadBranch() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("刷新环境信息")
                .accessibilityLabel("刷新环境信息")
                Button {
                    copyText(summaryText)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
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
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text("变更")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(n > 0 ? "+\(n)" : "干净")
                .font(.caption)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text("上下文")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("\(percent)%")
                    .font(.caption)
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
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption)
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
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(path)
                .font(.caption)
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
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button(action: action) {
                HStack(spacing: 3) {
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private func menuRow(icon: String, label: String, value: String, @ViewBuilder menu: @escaping () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Menu {
                menu()
            } label: {
                HStack(spacing: 3) {
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .menuStyle(.borderlessButton)
        }
    }
}
