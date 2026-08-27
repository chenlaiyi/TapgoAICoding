import SwiftUI
import TapgoCore

/// Codex-style batched file-edit block: a single "已编辑 N 个文件" card that
/// folds a run of consecutive file changes into one collapsible list, with
/// an applied/awaiting badge and a "再显示 N 个文件" expander for long runs.
struct FileEditBatchView: View {
    let files: [FileChange]
    @EnvironmentObject var workspace: WorkspaceStore
    @State private var expanded = true
    @State private var showAll = false
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale
    private static let foldThreshold = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundStyle(.indigo)
                Text("已编辑 \(files.count) 个文件")
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                    .bold()
                Spacer()
                HStack(spacing: 3) {
                    Text(badgeLabel)
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(badgeColor)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badgeColor.opacity(0.16), in: Capsule())
                Button {
                    copy(pathsText)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                }
                .buttonStyle(.borderless)
                .help("复制文件路径列表")
                .accessibilityLabel("复制文件路径列表")
                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(expanded ? "折叠文件列表" : "展开文件列表")
            }
            if expanded {
                Divider().padding(.top, 6)
                ForEach(Array(visibleFiles.enumerated()), id: \.offset) { _, f in
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: f.kind))
                            .foregroundStyle(color(for: f.kind))
                            .frame(width: 14)
                        Text(f.path)
                            .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Text(kindLabel(f.kind))
                            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let url = resolvedURL(for: f.path)
                        if FileManager.default.fileExists(atPath: url.path) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .contextMenu {
                        Button {
                            copy(f.path)
                        } label: {
                            Label("复制路径", systemImage: "doc.on.doc")
                        }
                        Button {
                            let url = resolvedURL(for: f.path)
                            if FileManager.default.fileExists(atPath: url.path) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Label("打开文件", systemImage: "doc")
                        }
                        Button {
                            let url = resolvedURL(for: f.path)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Label("在访达中显示", systemImage: "folder")
                        }
                    }
                    .padding(.vertical, 3)
                }
                if files.count > Self.foldThreshold {
                    Button {
                        showAll = true
                    } label: {
                        Text("再显示 \(files.count - Self.foldThreshold) 个文件")
                            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DSHTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: DSHTheme.radiusCard).stroke(DSHTheme.border, lineWidth: 1))
        .shadow(color: DSHTheme.cardShadow, radius: 3, x: 0, y: 1)
    }

    private var visibleFiles: [FileChange] {
        showAll ? files : Array(files.prefix(Self.foldThreshold))
    }

    private var pathsText: String {
        files.map(\.path).joined(separator: "\n")
    }
    private func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    /// Resolve a (possibly relative) changed-file path to an absolute one
    /// against the active project's worktree, so "打开文件" works for the
    /// relative paths the harness reports.
    static func resolve(_ path: String, in workspace: WorkspaceStore) -> URL {
        // Treat a leading "/" (or a Foundation absolute-path) as absolute.
        if !path.isEmpty && path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        let base = workspace.state.activeProject?.worktreeRoot
            ?? workspace.state.projects.first?.worktreeRoot
        if let base { return base.appendingPathComponent(path) }
        return URL(fileURLWithPath: path)
    }

    func resolvedURL(for path: String) -> URL {
        Self.resolve(path, in: workspace)
    }

    private var badgeLabel: String {
        switch batchStatus {
        case .applied: return "已应用"
        case .awaitingApproval: return "等待批准"
        case .failed, .denied: return "失败"
        case .pending: return "待处理"
        }
    }
    private var badgeColor: Color {
        switch batchStatus {
        case .applied: return .green
        case .awaitingApproval: return .orange
        case .failed, .denied: return .red
        case .pending: return .secondary
        }
    }
    /// Representative status: an awaiting / failed edit outranks applied.
    private var batchStatus: FileChange.Status {
        if files.contains(where: { $0.status == .awaitingApproval }) { return .awaitingApproval }
        if files.contains(where: { $0.status == .failed || $0.status == .denied }) { return .failed }
        if files.contains(where: { $0.status == .pending }) { return .pending }
        return .applied
    }

    private func icon(for kind: FileChange.Kind) -> String {
        switch kind {
        case .create: return "doc.badge.plus"
        case .update: return "pencil"
        case .delete: return "trash"
        }
    }
    private func color(for kind: FileChange.Kind) -> Color {
        switch kind {
        case .create: return .green
        case .update: return .blue
        case .delete: return .red
        }
    }
    private func kindLabel(_ kind: FileChange.Kind) -> String {
        switch kind {
        case .create: return "添加"
        case .update: return "修改"
        case .delete: return "删除"
        }
    }
}

struct FileChangeView: View {
    let change: FileChange
    @EnvironmentObject var workspace: WorkspaceStore
    // Codex-style: short diffs stay expanded so the user can review
    // the change at a glance; long diffs default collapsed so the
    // chat doesn't get buried under a giant patch.
    @State private var isExpanded: Bool
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    init(change: FileChange) {
        self.change = change
        self._isExpanded = State(initialValue: change.diff.count < 400)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                Text(change.path)
                    .font(AppFont.monoScaled(size: 13, multiplier: appFontScale.multiplier))
                    .bold()
                    .lineLimit(1)
                Spacer()
                if isExpanded && !change.diff.isEmpty {
                    CopyIconButton(text: change.diff, help: "复制差异")
                }
                statusBadge
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isExpanded ? "折叠差异" : "展开差异")
            }
            if isExpanded && !change.diff.isEmpty {
                // Structured diff view: parses the unified diff, lets
                // the reviewer toggle unified / split / raw, and add
                // per-line review comments. Replaces the previous
                // naive `DiffText` colorizer (kept inside DiffView as
                // the "Raw" mode for users who want the literal text).
                DiffView(change: change)
                    .frame(maxHeight: 360)
                    .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DSHTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: DSHTheme.radiusCard).stroke(DSHTheme.border, lineWidth: 1))
            .shadow(color: DSHTheme.cardShadow, radius: 3, x: 0, y: 1)
        .contextMenu {
            Button {
                let url = FileEditBatchView.resolve(change.path, in: workspace)
                if FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("打开文件", systemImage: "doc")
            }
            Button {
                let url = FileEditBatchView.resolve(change.path, in: workspace)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label("在访达中显示", systemImage: "folder")
            }
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(change.path, forType: .string)
            } label: {
                Label("复制路径", systemImage: "doc.on.doc")
            }
            if !change.diff.isEmpty {
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(change.diff, forType: .string)
                } label: {
                    Label("复制差异", systemImage: "doc.on.doc")
                }
            }
        }
    }

    private var icon: String {
        switch change.kind {
        case .create: return "doc.badge.plus"
        case .update: return "pencil"
        case .delete: return "trash"
        }
    }
    private var iconColor: Color {
        switch change.kind {
        case .create: return .green
        case .update: return .blue
        case .delete: return .red
        }
    }
    private var statusBadge: some View {
        let (label, icon, color): (String, String, Color) = {
            switch change.status {
            case .applied: return ("已应用", "checkmark", .green)
            case .failed: return ("失败", "xmark", .red)
            case .denied: return ("已拒绝", "hand.raised.slash", .red)
            case .awaitingApproval: return ("待批准", "hand.raised", .orange)
            case .pending: return ("待应用", "clock", .secondary)
            }
        }()
        return HStack(spacing: 3) {
            Image(systemName: icon).font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
            Text(label).font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.18), in: Capsule())
        .foregroundStyle(color)
        .accessibilityLabel(label)
    }
}

/// Very small unified-diff colorizer. Not a full parser — just lines starting
/// with `+` and `-` get tinted.
struct DiffText: View {
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    let diff: String
    var body: some View {
        let lines = diff.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
                    .foregroundStyle(color(for: line))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .background(bg(for: line))
            }
        }
    }
    private func color(for line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return .secondary }
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        if line.hasPrefix("@@") { return .blue }
        return .primary
    }
    private func bg(for line: String) -> Color {
        if line.hasPrefix("+") { return Color.green.opacity(0.10) }
        if line.hasPrefix("-") { return Color.red.opacity(0.10) }
        return Color.clear
    }
}
