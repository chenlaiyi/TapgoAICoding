import SwiftUI
import TapgoCore

// MARK: - Codex-style quiet file-change row
//
// A single muted transcript line: "编辑 Info.plist AppBuilder +8 -2", with
// the diff available on click and a failure suffix when the edit failed.

struct FileChangeRowView: View {
    let change: FileChange
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var showDiff = false
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    private var added: Int { Self.addedLines(in: change.diff) }
    private var removed: Int { Self.removedLines(in: change.diff) }
    private var failed: Bool { change.status == .failed || change.status == .denied }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(iconColor)
                    .frame(width: 16)
                Text(verb)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                Text(basename)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(directory)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                if added > 0 {
                    Text("+\(added)")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.green)
                }
                if removed > 0 {
                    Text("-\(removed)")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.red)
                }
                if failed {
                    Text("执行失败")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        // warnAccent (#CD8900, 16 hits in ZCode asar) is the
                        // ZCode-amber tone for "tool failure" badges. The
                        // previous `.tertiary` grey blended into the row
                        // background and made failed edits easy to miss
                        // during review.
                        .foregroundStyle(DSHTheme.warnAccent)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { showDiff.toggle() }
            .contextMenu {
                Button { copy(change.path) } label: {
                    Label("复制路径", systemImage: "doc.on.doc")
                }
                Button { openFile() } label: {
                    Label("打开文件", systemImage: "doc")
                }
                Button { revealInFinder() } label: {
                    Label("在访达中显示", systemImage: "folder")
                }
                if !change.diff.isEmpty {
                    Button { copy(change.diff) } label: {
                        Label("复制差异", systemImage: "doc.on.doc")
                    }
                }
            }

            if showDiff, !change.diff.isEmpty {
                DiffView(change: change)
                    .frame(maxHeight: 320)
            }
        }
        .padding(.vertical, 3)
        .accessibilityLabel(change.path)
    }

    private var icon: String {
        switch change.kind {
        case .create: return "doc.badge.plus"
        case .update: return "pencil"
        case .delete: return "trash"
        }
    }
    private var iconColor: Color { failed ? DSHTheme.error : DSHTheme.labelTertiary }
    private var verb: String {
        switch change.kind {
        case .create: return "新建"
        case .update: return "编辑"
        case .delete: return "删除"
        }
    }
    private var basename: String {
        (change.path as NSString).lastPathComponent
    }
    private var directory: String {
        let dir = (change.path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }

    private func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
    private func openFile() {
        let url = FileEditBatchView.resolve(change.path, in: workspace)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        }
    }
    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(
            [FileEditBatchView.resolve(change.path, in: workspace)]
        )
    }

    static func addedLines(in diff: String) -> Int {
        diff.components(separatedBy: "\n").filter { line in
            line.hasPrefix("+") && !line.hasPrefix("+++")
        }.count
    }
    static func removedLines(in diff: String) -> Int {
        diff.components(separatedBy: "\n").filter { line in
            line.hasPrefix("-") && !line.hasPrefix("---")
        }.count
    }
}

/// End-of-turn summary bar: "5 个文件已更改 +47 -8" with an expand toggle,
/// matching Codex's collapsed change summary.
struct FileChangeSummaryBar: View {
    let count: Int
    let additions: Int
    let deletions: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text("\(count) 个文件已更改")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                if additions > 0 {
                    Text("+\(additions)")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.green)
                }
                if deletions > 0 {
                    Text("-\(deletions)")
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) 个文件已更改")
        .accessibilityHint(isExpanded ? "折叠文件列表" : "展开文件列表")
    }
}

/// Codex-style batched file-edit block: one persistent result card with the
/// aggregate line delta and a three-file preview. The detailed diffs remain
/// available from each row without flooding the surrounding transcript.
struct FileEditBatchView: View {
    let files: [FileChange]
    @State private var expanded = false
    @State private var showAll = false
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale
    private static let foldThreshold = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: files.count == 1 ? singleIcon : "doc.on.doc")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(DSHTheme.labelDim)
                    .frame(width: 26, height: 26)
                    .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 3) {
                    Text(summaryTitle)
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .fontWeight(.medium)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if additions > 0 {
                            Text("+\(additions)").foregroundStyle(DSHTheme.success)
                        }
                        if deletions > 0 {
                            Text("-\(deletions)").foregroundStyle(DSHTheme.error)
                        }
                        if batchStatus != .applied {
                            Text(badgeLabel).foregroundStyle(badgeColor)
                        }
                    }
                    .font(AppFont.monoScaled(size: 10, weight: .medium, multiplier: appFontScale.multiplier))
                }
                Spacer(minLength: 8)
                if files.contains(where: { !$0.diff.isEmpty }) {
                    Button(expanded ? "收起" : "审核") { expanded.toggle() }
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .buttonStyle(.plain)
                        .foregroundStyle(DSHTheme.labelDim)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(DSHTheme.border, lineWidth: 1))
                        .accessibilityLabel(expanded ? "收起文件审核" : "审核文件变更")
                }
            }
            if expanded {
                Divider().padding(.vertical, 8)
                if files.count == 1, let file = files.first, !file.diff.isEmpty {
                    DiffView(change: file)
                        .frame(maxHeight: 360)
                } else {
                    ForEach(Array(visibleFiles.enumerated()), id: \.offset) { _, file in
                        FileChangeRowView(change: file)
                    }
                }
                if files.count > Self.foldThreshold {
                    Button {
                        showAll.toggle()
                    } label: {
                        Text(showAll ? "收起文件" : "再显示 \(files.count - Self.foldThreshold) 个文件")
                            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(DSHTheme.bgLayer1, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DSHTheme.border, lineWidth: 1))
        .contextMenu {
            Button { copy(pathsText) } label: {
                Label("复制文件路径", systemImage: "doc.on.doc")
            }
            Button { copy(files.map(\.diff).filter { !$0.isEmpty }.joined(separator: "\n")) } label: {
                Label("复制全部差异", systemImage: "doc.on.doc")
            }
            .disabled(files.allSatisfy { $0.diff.isEmpty })
        }
    }

    private var visibleFiles: [FileChange] {
        showAll ? files : Array(files.prefix(Self.foldThreshold))
    }

    private var pathsText: String {
        files.map(\.path).joined(separator: "\n")
    }

    private var additions: Int {
        files.reduce(0) { $0 + FileChangeRowView.addedLines(in: $1.diff) }
    }

    private var deletions: Int {
        files.reduce(0) { $0 + FileChangeRowView.removedLines(in: $1.diff) }
    }

    private var summaryTitle: String {
        guard files.count == 1, let file = files.first else {
            return "已编辑 \(files.count) 个文件"
        }
        return "已\(verb(for: file.kind)) \((file.path as NSString).lastPathComponent)"
    }

    private var singleIcon: String {
        guard let kind = files.first?.kind else { return "doc.text" }
        switch kind {
        case .create: return "doc.badge.plus"
        case .update: return "doc.text"
        case .delete: return "trash"
        }
    }

    private func verb(for kind: FileChange.Kind) -> String {
        switch kind {
        case .create: return "新建"
        case .update: return "编辑"
        case .delete: return "删除"
        }
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
