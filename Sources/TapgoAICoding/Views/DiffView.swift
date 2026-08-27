import SwiftUI
import TapgoCore

// MARK: - DiffView
//
// Structured, reviewable diff renderer. Replaces the old naive
// `DiffText` colorizer that just painted +/- backgrounds. This view:
//
//   • parses the raw unified diff via `DiffParser`
//   • renders each file with one of three modes (unified, split, raw)
//   • lets the reviewer add per-line notes via a small inline editor
//
// Comments live in a per-view `ReviewCommentStore` instance; the next
// iteration will lift that to an app-level EnvironmentObject so notes
// survive when the same `FileChange` is rendered again (e.g. scroll
// away and back). For v0.5.0 the store is local to each render so the
// UI wiring stays simple.

struct DiffView: View {
    let change: FileChange
    @StateObject private var commentStore = ReviewCommentStore()
    @State private var mode: Mode = .unified
    @State private var commentTarget: CommentTarget? = nil
    @State private var draftText: String = ""
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    enum Mode: String, CaseIterable, Identifiable {
        case unified = "Unified"
        case split = "Split"
        case raw = "Raw"
        var id: String { rawValue }
    }

    /// A pinned location in the diff. Used to drive the inline
    /// comment composer: which line / side / hunk the user wants
    /// to comment on.
    struct CommentTarget: Equatable {
        let lineKey: String
        let oldLine: Int?
        let newLine: Int?
        let side: ReviewAnchorSide
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
            composer
        }
    }

    // MARK: - Header (mode toggle + stats)

    private var header: some View {
        HStack(spacing: 8) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            Spacer(minLength: 8)
            Text(parsed.statsLabel)
                .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        if change.diff.isEmpty {
            Text("(空 diff)")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        } else if parsed.isBinary {
            Text("二进制文件差异 — 无行级预览")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        } else {
            switch mode {
            case .unified: unifiedBody
            case .split: splitBody
            case .raw: rawBody
            }
        }
    }

    private var unifiedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(parsed.hunks.indices, id: \.self) { hi in
                let hunk = parsed.hunks[hi]
                HStack(spacing: 0) {
                    Text(hunk.header)
                        .font(AppFont.monoScaled(size: 10, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DSHTheme.moduleBg)
                ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                    unifiedLineRow(line: line)
                }
            }
        }
        .background(DSHTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(DSHTheme.border, lineWidth: 1)
        )
    }

    private func unifiedLineRow(line: DiffLine) -> some View {
        let comments = commentStore.comments(for: change.id, lineKey: line.stableKey)
        let isCommenting = commentTarget?.lineKey == line.stableKey
        return HStack(spacing: 0) {
            gutterNumber(line.oldLineNumber)
            gutterNumber(line.newLineNumber)
            kindGlyph(line.kind)
            Text(line.content.isEmpty ? " " : line.content)
                .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
                .foregroundStyle(kindForeground(line.kind))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            if !comments.isEmpty {
                Image(systemName: "bubble.right.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(DSHTheme.brand)
                    .help(commentSummary(comments))
            }
            Button {
                beginComment(for: line)
            } label: {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .opacity(isCommenting ? 1 : 0.5)
            .help("为这一行添加评论")
        }
        .background(rowBackground(line.kind))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginComment(for: line) }
    }

    private var splitBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(parsed.hunks.indices, id: \.self) { hi in
                let hunk = parsed.hunks[hi]
                HStack(spacing: 0) {
                    Text(hunk.header)
                        .font(AppFont.monoScaled(size: 10, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DSHTheme.moduleBg)
                splitHunkRows(hunk: hunk)
            }
        }
        .background(DSHTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(DSHTheme.border, lineWidth: 1)
        )
    }

    /// Render a hunk as alternating left/right rows: each `remove` line
    /// becomes a left-cell with an empty right-cell; each `add` line
    /// becomes an empty left-cell with a right-cell; each `context`
    /// line fills both sides.
    private func splitHunkRows(hunk: DiffHunk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                switch line.kind {
                case .remove:
                    splitPair(left: line, right: nil)
                case .add:
                    splitPair(left: nil, right: line)
                case .context:
                    splitPair(left: line, right: line)
                case .noNewLine:
                    splitPair(left: nil, right: nil, midLabel: line.content)
                }
            }
        }
    }

    private func splitPair(left: DiffLine?, right: DiffLine?, midLabel: String? = nil) -> some View {
        HStack(spacing: 0) {
            splitSide(line: left, isLeft: true)
            Rectangle()
                .fill(DSHTheme.border)
                .frame(width: 1)
            splitSide(line: right, isLeft: false)
        }
    }

    @ViewBuilder
    private func splitSide(line: DiffLine?, isLeft: Bool) -> some View {
        if let line {
            HStack(spacing: 0) {
                gutterNumber(line.oldLineNumber)
                gutterNumber(line.newLineNumber)
                Text(line.content.isEmpty ? " " : line.content)
                    .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
                    .foregroundStyle(kindForeground(line.kind))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                Button {
                    beginComment(for: line)
                } label: {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .opacity(0.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(splitRowBackground(line: line, isLeft: isLeft))
        } else {
            HStack(spacing: 0) {
                Spacer()
                Text("")
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 18)
        }
    }

    private func splitRowBackground(line: DiffLine, isLeft: Bool) -> Color {
        // On the right side, removed lines should be EMPTY (no
        // background) so they show as gaps between the unchanged
        // context rows. On the left side, added lines should be empty.
        if isLeft && line.kind == .add { return Color.clear }
        if !isLeft && line.kind == .remove { return Color.clear }
        return rowBackground(line.kind)
    }

    // MARK: - Raw fallback (previous naive renderer, kept for power users)

    private var rawBody: some View {
        ScrollView {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(change.diff)
                    .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
                    .textSelection(.enabled)
                    .padding(8)
            }
        }
        .frame(maxHeight: 280)
        .background(DSHTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(DSHTheme.border, lineWidth: 1)
        )
    }

    // MARK: - Inline comment composer

    @ViewBuilder
    private var composer: some View {
        if let target = commentTarget {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left")
                        .foregroundStyle(DSHTheme.brand)
                    Text(targetDescription(target))
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("取消") {
                        commentTarget = nil
                        draftText = ""
                    }
                    .buttonStyle(.borderless)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                }
                TextField("写下你的评论…", text: $draftText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                HStack {
                    Spacer()
                    Button("保存评论") { saveDraft(target: target) }
                        .buttonStyle(DSHPrimaryButtonStyle())
                        .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                }
            }
            .padding(8)
            .background(DSHTheme.moduleBg, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6).stroke(DSHTheme.border, lineWidth: 1)
            )
        }
    }

    private func targetDescription(_ t: CommentTarget) -> String {
        let side: String
        switch t.side {
        case .old: side = "旧行"
        case .new: side = "新行"
        case .both: side = "整段"
        }
        if let n = t.oldLine, let m = t.newLine {
            return "\(side) 第 \(n) / \(m) 行"
        } else if let n = t.oldLine {
            return "\(side) 第 \(n) 行"
        } else if let m = t.newLine {
            return "\(side) 第 \(m) 行"
        }
        return side
    }

    private func beginComment(for line: DiffLine) {
        let side: ReviewAnchorSide
        switch line.kind {
        case .add: side = .new
        case .remove: side = .old
        case .context: side = .new   // arbitrary: pick .new so we have a number
        case .noNewLine: side = .both
        }
        commentTarget = CommentTarget(
            lineKey: line.stableKey,
            oldLine: line.oldLineNumber,
            newLine: line.newLineNumber,
            side: side)
        draftText = ""
    }

    private func saveDraft(target: CommentTarget) {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        commentStore.add(ReviewComment(
            fileChangeId: change.id,
            lineKey: target.lineKey,
            oldLineNumber: target.oldLine,
            newLineNumber: target.newLine,
            side: target.side,
            text: trimmed))
        commentTarget = nil
        draftText = ""
    }

    private func commentSummary(_ comments: [ReviewComment]) -> String {
        comments.map(\.text).joined(separator: " • ")
    }

    // MARK: - Parsing (cached on `change`)

    /// Re-parse the raw diff text whenever the underlying string changes.
    /// Cheap (small diffs, in-memory) so we don't memoize.
    private var parsed: DiffFile {
        DiffParser.parse(change.diff).first ?? DiffFile(
            oldPath: change.path, newPath: change.path, hunks: [], isBinary: false)
    }

    // MARK: - Gutter / kind helpers

    private func gutterNumber(_ n: Int?) -> some View {
        Text(n.map { String($0) } ?? "")
            .font(AppFont.monoScaled(size: 10, multiplier: appFontScale.multiplier))
            .foregroundStyle(.secondary)
            .frame(width: 30, alignment: .trailing)
            .padding(.horizontal, 2)
    }

    private func kindGlyph(_ kind: DiffLine.Kind) -> some View {
        Text(glyph(for: kind))
            .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
            .foregroundStyle(kindForeground(kind))
            .frame(width: 12)
    }

    private func glyph(for kind: DiffLine.Kind) -> String {
        switch kind {
        case .context: return " "
        case .add: return "+"
        case .remove: return "−"
        case .noNewLine: return "\\"
        }
    }

    private func rowBackground(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .add: return Color.green.opacity(0.12)
        case .remove: return Color.red.opacity(0.12)
        case .context: return Color.clear
        case .noNewLine: return DSHTheme.moduleBg
        }
    }

    private func kindForeground(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .add: return Color.green
        case .remove: return Color.red
        case .context: return DSHTheme.label
        case .noNewLine: return DSHTheme.labelDim
        }
    }
}
