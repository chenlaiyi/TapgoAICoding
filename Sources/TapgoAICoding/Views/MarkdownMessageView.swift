import SwiftUI
import TapgoCore

/// Renders an assistant message with a lightweight markdown-lite pass:
/// fenced code blocks get a copyable monospaced container, inline code
/// and bold are styled inline, and bullet/numbered lists render with
/// proper markers. Plain text falls through unchanged.
struct MarkdownMessageView: View {
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    let text: String
    let isStreaming: Bool

    init(_ text: String, isStreaming: Bool = false) {
        self.text = text
        self.isStreaming = isStreaming
    }

    var body: some View {
        let blocks = Self.blocks(MarkdownLite.parse(text))
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .para(let segs):
                    paragraphView(segs: segs)
                case .code(let code, let lang):
                    CodeBlockView(code: code, lang: lang)
                case .list(let items, let ordered):
                    ListView(items: items, ordered: ordered)
                case .quote(let segs):
                    QuoteView(segs: segs)
                case .rule:
                    Divider().padding(.vertical, 2)
                case .table(let headers, let rows):
                    TableView(headers: headers, rows: rows)
                case .task(let items):
                    TaskListView(items: items)
                case .image(let alt, let url):
                    ImageView(alt: alt, url: url)
                case .heading(let level, let content):
                    HeadingView(level: level, content: content)
                }
            }
            if isStreaming {
                StreamingReplyCursor()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum Block {
        /// 段落 — 暂存原始 segs，渲染时根据 appFontScale 重新构造 AttributedString，
        /// 以保证 inline / bold / 行内代码的字号、字重、行内代码底色等跟随用户字号偏好。
        case para([MarkdownSegment])
        case code(code: String, lang: String?)
        case list(items: [[MarkdownSegment]], ordered: Bool)
        case quote([MarkdownSegment])
        case rule
        case table(headers: [String], rows: [[String]])
        case task([TaskItem])
        case image(alt: String, url: String)
        case heading(level: Int, content: [MarkdownSegment])
    }

    private static func blocks(_ segs: [MarkdownSegment]) -> [Block] {
        var out: [Block] = []
        var acc: [MarkdownSegment] = []
        for seg in segs {
            switch seg {
            case .codeFence(let code, let lang):
                appendPara(&out, &acc)
                out.append(.code(code: code, lang: lang))
            case .bulletList(let items):
                appendPara(&out, &acc)
                out.append(.list(items: items, ordered: false))
            case .numberedList(let items):
                appendPara(&out, &acc)
                out.append(.list(items: items, ordered: true))
            case .blockquote(let segs):
                appendPara(&out, &acc)
                out.append(.quote(segs))
            case .horizontalRule:
                appendPara(&out, &acc)
                out.append(.rule)
            case .table(let headers, let rows):
                appendPara(&out, &acc)
                out.append(.table(headers: headers, rows: rows))
            case .taskList(let items):
                appendPara(&out, &acc)
                out.append(.task(items))
            case .image(let alt, let url):
                appendPara(&out, &acc)
                out.append(.image(alt: alt, url: url))
            case .heading(let level, let content):
                appendPara(&out, &acc)
                out.append(.heading(level: level, content: content))
            case .text, .inline, .bold, .link, .strikethrough:
                acc.append(seg)
            }
        }
        appendPara(&out, &acc)
        return out
    }

    private static func appendPara(_ out: inout [Block], _ acc: inout [MarkdownSegment]) {
        if !acc.isEmpty {
            out.append(.para(acc))
            acc = []
        }
    }

    /// Convert an inline-level segment run (text / inline / bold) into an
    /// `AttributedString` so a paragraph or a list item can be rendered
    /// with mixed fonts in one drawing. `baseFontSize` 控制正文 / 行内代码 / 加粗
    /// 字号；三者皆按 appFontScale 计算，从而跟随用户字号偏好。
    fileprivate static func inlineAttributed(
        _ segs: [MarkdownSegment],
        baseFontSize: CGFloat = AppFont.pointSize(for: .body, multiplier: 1),
        baseWeight: Font.Weight = .regular
    ) -> AttributedString {
        var a = AttributedString()
        // 行内代码比正文略小一档，以中性色底纹保持区分，但不再渲染成高饱和标签。
        let inlineSize = max(baseFontSize - 1.5, 9)
        for seg in segs {
            switch seg {
            case .text(let s):
                var r = AttributedString(s)
                r.font = .system(size: baseFontSize, weight: baseWeight)
                a += r
            case .inline(let s):
                var r = AttributedString(s)
                r.font = .system(size: inlineSize, weight: .medium, design: .monospaced)
                r.foregroundColor = DSHTheme.labelDim
                r.backgroundColor = DSHTheme.inlineCodeBg
                a += r
            case .bold(let s):
                var r = AttributedString(s)
                r.font = .system(size: baseFontSize, weight: .semibold)
                a += r
            case .strikethrough(let s):
                var r = AttributedString(s)
                r.font = .system(size: baseFontSize)
                r.strikethroughStyle = .single
                a += r
            case .link(let title, let url):
                var r = AttributedString(title)
                r.link = URL(string: url)
                r.font = .system(size: baseFontSize)
                r.foregroundColor = DSHTheme.brand
                a += r
            case .codeFence, .bulletList, .numberedList, .blockquote, .horizontalRule, .table, .taskList, .image, .heading:
                break
            }
        }
        return a
    }

    /// Table cells also accept inline markdown. The previous plain-string
    /// renderer exposed literal `**bold**` and backticks in the transcript.
    fileprivate static func inlineSegments(_ text: String) -> [MarkdownSegment] {
        MarkdownLite.parse(text).filter { segment in
            switch segment {
            case .text, .inline, .bold, .link, .strikethrough: return true
            default: return false
            }
        }
    }


    /// 段落渲染：字号跟随 appFontScale，行间距放大到 3pt 让长段落在 chat 里更易扫读；
    /// `fixedSize(horizontal:false, vertical:true)` 确保段落被允许按内容撑开高度（避免某些容器
    /// 默认 single-line 行为）。
    @ViewBuilder
    private func paragraphView(segs: [MarkdownSegment]) -> some View {
        let bodySize = AppFont.pointSize(for: .body, multiplier: appFontScale.multiplier) + 0.5
        Text(Self.inlineAttributed(segs, baseFontSize: bodySize))
            .lineSpacing(4)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private struct ListView: View {
        @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale
        let items: [[MarkdownSegment]]
        let ordered: Bool

        var body: some View {
            // Marker 用 tertiary 弱化、字号比正文略小、靠右对齐的固定列宽；
            // 6pt 行距保留 ZCode 长列表的扫读节奏。
            let bodySize = AppFont.pointSize(for: .body, multiplier: appFontScale.multiplier) + 0.5
            let markerSize = AppFont.pointSize(for: .footnote, multiplier: appFontScale.multiplier)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(idx + 1)." : "•")
                            .font(.system(size: markerSize, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DSHTheme.labelTertiary)
                            .frame(minWidth: ordered ? 18 : 14, alignment: .trailing)
                        Text(MarkdownMessageView.inlineAttributed(item, baseFontSize: bodySize))
                            .textSelection(.enabled)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 2)
        }
    }
}

/// Monospaced, copyable code container for a fenced block.
private struct CodeBlockView: View {
    let code: String
    let lang: String?
    @State private var copied = false
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let lang, !lang.isEmpty {
                    Text(lang)
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Text("\(code.count) 字符")
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                Button {
                    copy(code)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.borderless)
                .help("复制代码")
                .accessibilityLabel("复制代码")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(DSHTheme.codeBlockBanner)
            // Long lines scroll horizontally instead of wrapping, so the
            // code keeps its real column layout (like the harness block).
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(AppFont.monoScaled(size: 11, multiplier: appFontScale.multiplier))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        }
        .background(DSHTheme.codeBlockBg, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: DSHTheme.radiusCard).stroke(DSHTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
    }

    private func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

/// Renders an ATX markdown heading (`#` … `######`) with a hierarchy-
/// aware font, like Codex.
private struct HeadingView: View {
    let level: Int
    let content: [MarkdownSegment]
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    var body: some View {
        Text(MarkdownMessageView.inlineAttributed(
            content,
            baseFontSize: pointSize,
            baseWeight: .semibold
        ))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, level <= 2 ? 8 : 4)
        .padding(.bottom, 1)
    }

    private var pointSize: CGFloat {
        let multiplier = appFontScale.multiplier
        switch level {
        case 1: return AppFont.pointSize(for: .title2, multiplier: multiplier)
        case 2: return AppFont.pointSize(for: .title3, multiplier: multiplier)
        case 3: return AppFont.pointSize(for: .headline, multiplier: multiplier) + 0.5
        default: return AppFont.pointSize(for: .body, multiplier: multiplier)
        }
    }
}

/// A restrained text caret for the partial markdown block. The composer owns
/// the stop control; the transcript only needs a subtle streaming cue.
private struct StreamingReplyCursor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        Capsule()
            .fill(DSHTheme.labelDim)
            .frame(width: 2, height: 13)
            .opacity(reduceMotion || visible ? 0.72 : 0.2)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                    visible = true
                }
            }
            .accessibilityLabel("正在生成回复")
    }
}

/// Codex-style blockquote: one quiet leading rule and secondary text, without
/// turning ordinary quoted prose into another card.
private struct QuoteView: View {
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    let segs: [MarkdownSegment]

    var body: some View {
        let bodySize = AppFont.pointSize(for: .body, multiplier: appFontScale.multiplier)
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1)
                .fill(DSHTheme.borderStrong)
                .frame(width: 2)
            Text(MarkdownMessageView.inlineAttributed(segs, baseFontSize: bodySize))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

/// Lightweight pipe-table renderer (`| a | b |` with a `|---|` header
/// separator). It stays flat in the transcript and renders inline markdown.
private struct TableView: View {
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    let headers: [String]
    let rows: [[String]]

    var body: some View {
        let bodySize = AppFont.pointSize(for: .body, multiplier: appFontScale.multiplier) - 0.5
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                        Text(MarkdownMessageView.inlineAttributed(
                            MarkdownMessageView.inlineSegments(h),
                            baseFontSize: bodySize,
                            baseWeight: .semibold
                        ))
                        .textSelection(.enabled)
                    }
                }
                .padding(.bottom, 2)
                if !rows.isEmpty {
                    Divider()
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(headers.enumerated()), id: \.offset) { i, _ in
                            Text(MarkdownMessageView.inlineAttributed(
                                MarkdownMessageView.inlineSegments(i < row.count ? row[i] : ""),
                                baseFontSize: bodySize
                            ))
                            .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .contextMenu {
            Button {
                copy(tableText)
            } label: {
                Label("复制表格", systemImage: "doc.on.doc")
            }
        }
    }

    private var tableText: String {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "\\|") }
        var lines = [headers.map(esc).joined(separator: " | ")]
        for row in rows {
            lines.append(row.map(esc).joined(separator: " | "))
        }
        return lines.joined(separator: "\n")
    }
    private func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

/// Checklist for `- [ ]` / `- [x]` task lines. checkbox 用 hierarchical 渲染 + 与正文
/// 同步字号比例；unchecked 时落到 DSHTheme.labelTertiary，整体视觉比纯色二级图标更克制。
private struct TaskListView: View {
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    let items: [TaskItem]

    var body: some View {
        let bodySize = AppFont.pointSize(for: .body, multiplier: appFontScale.multiplier)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                        .font(.system(size: bodySize, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(item.checked ? DSHTheme.success : DSHTheme.labelTertiary)
                        .frame(width: bodySize + 2, alignment: .leading)
                    Text(MarkdownMessageView.inlineAttributed(item.content, baseFontSize: bodySize))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        // 已勾选项视觉上略暗；SwiftUI Text 自身支持 strikethrough，这里靠
                        // segment 走 inlineAttributed 的 strikethrough 段，未来若 segment 模型
                        // 暴露 done 字段，再加整行删除线。
                }
            }
        }
    }
}

/// Renders an `![alt](url)` image, capped to a readable width. Falls
/// back to the alt text on load failure.
private struct ImageView: View {
    let alt: String
    let url: String
    @State private var failed = false
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    var body: some View {
        Group {
            if failed {
                Text(alt.isEmpty ? "图片加载失败" : alt)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
            } else {
                AsyncImage(url: URL(string: url)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().controlSize(.small).padding(8)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    case .failure:
                        Color.clear
                            .frame(height: 12)
                            .onAppear { failed = true }
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .accessibilityLabel(alt.isEmpty ? "图片" : alt)
        .contextMenu {
            Button {
                if let u = URL(string: url) {
                    NSWorkspace.shared.open(u)
                }
            } label: {
                Label("在浏览器中打开", systemImage: "safari")
            }
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(url, forType: .string)
            } label: {
                Label("复制图片 URL", systemImage: "doc.on.doc")
            }
        }
    }
}
