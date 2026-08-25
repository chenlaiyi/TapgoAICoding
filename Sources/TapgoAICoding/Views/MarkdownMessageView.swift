import SwiftUI
import TapgoCore

/// Renders an assistant message with a lightweight markdown-lite pass:
/// fenced code blocks get a copyable monospaced container, inline code
/// and bold are styled inline, and bullet/numbered lists render with
/// proper markers. Plain text falls through unchanged.
struct MarkdownMessageView: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        let blocks = Self.blocks(MarkdownLite.parse(text))
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .para(let attr):
                    Text(attr).textSelection(.enabled)
                case .code(let code, let lang):
                    CodeBlockView(code: code, lang: lang)
                case .list(let items, let ordered):
                    ListView(items: items, ordered: ordered)
                case .quote(let attr):
                    QuoteView(attr: attr)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum Block {
        case para(AttributedString)
        case code(code: String, lang: String?)
        case list(items: [[MarkdownSegment]], ordered: Bool)
        case quote(AttributedString)
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
                out.append(.quote(inlineAttributed(segs)))
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
            out.append(.para(inlineAttributed(acc)))
            acc = []
        }
    }

    /// Convert an inline-level segment run (text / inline / bold) into an
    /// `AttributedString` so a paragraph or a list item can be rendered
    /// with mixed fonts in one drawing.
    fileprivate static func inlineAttributed(_ segs: [MarkdownSegment]) -> AttributedString {
        var a = AttributedString()
        for seg in segs {
            switch seg {
            case .text(let s):
                a += AttributedString(s)
            case .inline(let s):
                var r = AttributedString(s)
                r.font = .system(.body, design: .monospaced)
                r.backgroundColor = DSHTheme.codeBlockBanner
                a += r
            case .bold(let s):
                var r = AttributedString(s)
                r.font = .body.bold()
                a += r
            case .strikethrough(let s):
                var r = AttributedString(s)
                r.font = .body
                r.strikethroughStyle = .single
                a += r
            case .link(let title, let url):
                var r = AttributedString(title)
                r.link = URL(string: url)
                r.foregroundColor = DSHTheme.brand
                r.underlineStyle = .single
                a += r
            case .codeFence, .bulletList, .numberedList, .blockquote, .horizontalRule, .table, .taskList, .image, .heading:
                break
            }
        }
        return a
    }

    private struct ListView: View {
        let items: [[MarkdownSegment]]
        let ordered: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(ordered ? "\(idx + 1)." : "•")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(MarkdownMessageView.inlineAttributed(item))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

/// Monospaced, copyable code container for a fenced block.
private struct CodeBlockView: View {
    let code: String
    let lang: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let lang, !lang.isEmpty {
                    Text(lang)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Text("\(code.count) 字符")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                Button {
                    copy(code)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
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
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        }
        .background(DSHTheme.codeBlockBg, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: DSHTheme.radiusCard).stroke(DSHTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
        .shadow(color: DSHTheme.cardShadow, radius: 3, x: 0, y: 1)
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

    var body: some View {
        Text(MarkdownMessageView.inlineAttributed(content))
            .font(font)
            .bold()
            .padding(.top, 6)
    }

    private var font: Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
        }
    }
}

/// Left-bordered, muted quote block for `> …` lines. Rendered as a Codex-
/// style info callout card (quote icon + bordered surface) rather than a
/// bare italic blockquote.
private struct QuoteView: View {
    let attr: AttributedString

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "quote.opening")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(attr)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DSHTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: DSHTheme.radiusCard).stroke(DSHTheme.border, lineWidth: 1))
    }
}

/// Lightweight pipe-table renderer (`| a | b |` with a `|---|` header
/// separator). Cells are plain text; column count follows the header.
private struct TableView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                // Header row sits on a raised surface for a Codex-like table.
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                        Text(h)
                            .font(.subheadline)
                            .bold()
                    }
                }
                .padding(.vertical, 4)
                .background(DSHTheme.surfaceRaised)
                if !rows.isEmpty {
                    Divider()
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    GridRow {
                        ForEach(Array(headers.enumerated()), id: \.offset) { i, _ in
                            Text(i < row.count ? row[i] : "")
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 2)
                    .background(idx % 2 == 1 ? DSHTheme.moduleBg.opacity(0.35) : Color.clear)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: DSHTheme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: DSHTheme.radiusCard).stroke(DSHTheme.border, lineWidth: 1))
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

/// Checklist for `- [ ]` / `- [x]` task lines.
private struct TaskListView: View {
    let items: [TaskItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                        .font(.caption)
                        .foregroundStyle(item.checked ? .green : .secondary)
                    Text(MarkdownMessageView.inlineAttributed(item.content))
                        .textSelection(.enabled)
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

    var body: some View {
        Group {
            if failed {
                Text(alt.isEmpty ? "图片加载失败" : alt)
                    .font(.caption)
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
