import SwiftUI
import TapgoCore

/// Renders an assistant message with a lightweight markdown-lite pass:
/// fenced code blocks get a copyable monospaced container, inline code
/// and bold are styled inline, and bullet/numbered lists render with
/// proper markers. Plain text falls through unchanged.
struct MarkdownMessageView: View {
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale
    @Environment(\.conversationBodySize) private var conversationBodySize

    let text: String
    let isStreaming: Bool

    init(_ text: String, isStreaming: Bool = false) {
        self.text = text
        self.isStreaming = isStreaming
    }

    var body: some View {
        let blocks = Self.blocks(MarkdownLite.parseCached(text))
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .para(let segs):
                    paragraphView(segs: segs)
                case .code(let code, let lang):
                    CodeBlockView(code: code, lang: lang)
                case .list(let items, let ordered, let depths, let startNumber):
                    ListView(items: items, ordered: ordered, depths: depths, startNumber: startNumber)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private enum Block {
        /// 段落 — 暂存原始 segs，渲染时根据 appFontScale 重新构造 AttributedString，
        /// 以保证 inline / bold / 行内代码的字号、字重、行内代码底色等跟随用户字号偏好。
        case para([MarkdownSegment])
        case code(code: String, lang: String?)
        case list(items: [[MarkdownSegment]], ordered: Bool, depths: [Int], startNumber: Int)
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
        // 有序列表跨块连续编号：作者常在 "1." 项下用 "- " 写子要点，旧逻辑
        // 遇嵌套 bullet 就把列表切断、每段从 1 重新编号，渲染成 "1. 1. 1."。
        // bullet 打断视为子列表（编号延续）；段落/标题/代码块等打断才重置。
        var orderedCounter = 0
        func resetOrderedCounter() { orderedCounter = 0 }
        for seg in segs {
            switch seg {
            case .codeFence(let code, let lang):
                appendPara(&out, &acc)
                out.append(.code(code: code, lang: lang))
                resetOrderedCounter()
            case .bulletList(let items, let depths):
                appendPara(&out, &acc)
                out.append(.list(items: items, ordered: false, depths: depths, startNumber: 1))
            case .numberedList(let items, let depths):
                appendPara(&out, &acc)
                let start = orderedCounter + 1
                out.append(.list(items: items, ordered: true, depths: depths, startNumber: start))
                orderedCounter = start + items.count - 1
            case .blockquote(let segs):
                appendPara(&out, &acc)
                out.append(.quote(segs))
                resetOrderedCounter()
            case .horizontalRule:
                appendPara(&out, &acc)
                out.append(.rule)
                resetOrderedCounter()
            case .table(let headers, let rows):
                appendPara(&out, &acc)
                out.append(.table(headers: headers, rows: rows))
                resetOrderedCounter()
            case .taskList(let items):
                appendPara(&out, &acc)
                out.append(.task(items))
                resetOrderedCounter()
            case .image(let alt, let url):
                appendPara(&out, &acc)
                out.append(.image(alt: alt, url: url))
                resetOrderedCounter()
            case .heading(let level, let content):
                appendPara(&out, &acc)
                out.append(.heading(level: level, content: content))
                resetOrderedCounter()
            case .text(let text):
                appendText(text, to: &out, accumulator: &acc)
                resetOrderedCounter()
            case .inline, .bold, .link, .strikethrough, .fileReference:
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

    /// Markdown blank lines delimit paragraphs. `MarkdownLite` deliberately
    /// keeps raw newlines inside text segments, so normalize them here before
    /// SwiftUI lays out the transcript. Otherwise a blank line contributes a
    /// full empty text row *and* the block gap, which is the main reason long
    /// Tapgo replies looked much looser than Codex.
    private static func appendText(
        _ text: String,
        to out: inout [Block],
        accumulator acc: inout [MarkdownSegment]
    ) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let hasLeadingBoundary = normalized.hasPrefix("\n")
        let hasTrailingBoundary = normalized.hasSuffix("\n")
        let core = normalized.trimmingCharacters(in: .newlines)

        if hasLeadingBoundary { appendPara(&out, &acc) }
        guard !core.isEmpty else {
            if hasTrailingBoundary { appendPara(&out, &acc) }
            return
        }

        let paragraphs = core.components(separatedBy: "\n\n")
        for (index, paragraph) in paragraphs.enumerated() {
            if index > 0 { appendPara(&out, &acc) }
            let content = paragraph.trimmingCharacters(in: .newlines)
            if !content.isEmpty { acc.append(.text(content)) }
        }
        if hasTrailingBoundary { appendPara(&out, &acc) }
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
        // Monospace is optically wider than body text. Keep it quiet so
        // paragraphs with paths remain readable rather than a grid of tiles.
        let inlineSize = baseFontSize * 0.95
        // ZCode 参考样式的行内代码胶囊。代码密集的消息（诊断报告、SQL 路径）
        // 一段能出现七八个胶囊：底色必须非常淡（正文字色 9% 透明度，GitHub
        // dark 风格），字号贴近正文、regular 字重，否则整段被实色灰块切碎、
        // 视觉上"花"得没法读。Text 的 backgroundColor 是平矩形且紧贴字形，
        // 前后各染一个空格充当水平内边距；断行后每行都保有底色。
        func pill(_ s: String) -> AttributedString {
            var r = AttributedString(" " + s + " ")
            r.font = .system(size: inlineSize, weight: .regular, design: .monospaced)
            r.foregroundColor = DSHTheme.messageText
            r.backgroundColor = DSHTheme.messageText.opacity(0.09)
            return r
        }
        for seg in segs {
            switch seg {
            case .text(let s):
                var r = AttributedString(s)
                r.font = .system(size: baseFontSize, weight: baseWeight)
                a += r
            case .inline(let s):
                a += pill(s)
            case .bold(let s):
                var r = AttributedString(s)
                r.font = .system(size: baseFontSize, weight: .semibold)
                a += r
            case .strikethrough(let s):
                var r = AttributedString(s)
                r.font = .system(size: baseFontSize, weight: baseWeight)
                r.strikethroughStyle = .single
                a += r
            case .link(let title, let url):
                var r = AttributedString(title)
                r.link = URL(string: url)
                r.font = .system(size: baseFontSize, weight: baseWeight)
                r.foregroundColor = DSHTheme.brand
                r.underlineStyle = .none
                a += r
            case .fileReference(let path, let line):
                // 路径引用：与行内代码同款胶囊，`:#` 行号尾巴用品牌色点出，
                // 与 ZCode 参考样式里可定位的 `path:42` 写法一致。
                var open = pill("")
                open.characters = AttributedString(" ").characters
                var pathRun = pill(path)
                pathRun.foregroundColor = DSHTheme.messageText
                a += open + pathRun
                if let line {
                    var tail = pill(":\(line)")
                    tail.foregroundColor = DSHTheme.brand
                    tail.font = .system(size: inlineSize, weight: .regular, design: .monospaced)
                    a += tail
                }
                var close = pill("")
                close.characters = AttributedString(" ").characters
                a += close
            case .codeFence, .bulletList, .numberedList, .blockquote, .horizontalRule, .table, .taskList, .image, .heading:
                break
            }
        }
        return a
    }

    /// Table cells also accept inline markdown. The previous plain-string
    /// renderer exposed literal `**bold**` and backticks in the transcript.
    fileprivate static func inlineSegments(_ text: String) -> [MarkdownSegment] {
        MarkdownLite.parseCached(text).filter { segment in
            switch segment {
            case .text, .inline, .bold, .link, .strikethrough, .fileReference: return true
            default: return false
            }
        }
    }


    /// 段落渲染：字号跟随 appFontScale，保持 Codex 的紧凑正文节奏；
    /// `fixedSize(horizontal:false, vertical:true)` 确保段落被允许按内容撑开高度（避免某些容器
    /// 默认 single-line 行为）。
    @ViewBuilder
    private func paragraphView(segs: [MarkdownSegment]) -> some View {
        let bodySize = conversationBodySize * appFontScale.multiplier
        Text(MarkdownMessageView.inlineAttributed(segs, baseFontSize: bodySize))
            .foregroundStyle(DSHTheme.messageText)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private struct ListView: View {
        @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale
        @Environment(\.conversationBodySize) private var conversationBodySize
        let items: [[MarkdownSegment]]
        let ordered: Bool
        var depths: [Int] = []
        /// 有序列表跨块延续的起始编号（见 `blocks(_:)` 的 orderedCounter）。
        var startNumber: Int = 1

        var body: some View {
            // Codex uses a small but clearly visible marker and a compact row
            // rhythm; the previous 6pt gap amplified long tool inventories.
            let bodySize = conversationBodySize * appFontScale.multiplier
            let markerSize = bodySize - 1
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    // 嵌套列表深度：每级缩进 16pt；depth ≥3 时正文降到 labelTertiary
                    // 档位，让眼睛立刻能分辨"主层级"和"更深层级"。
                    let depth = (idx < depths.count) ? depths[idx] : 0
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(startNumber + idx)." : "•")
                            .font(.system(size: markerSize, weight: .regular, design: .monospaced))
                            .foregroundStyle(DSHTheme.labelTertiary)
                            .frame(minWidth: ordered ? 18 : 14, alignment: .trailing)
                        Text(MarkdownMessageView.inlineAttributed(item, baseFontSize: bodySize))
                            .foregroundStyle(DSHTheme.messageText)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(depth >= 2 ? DSHTheme.label : DSHTheme.messageText)
                    }
                    // 每级 24pt ≈ 父项 marker 列宽，子列表起点落在父项文字
                    // 下方，与 Codex 桌面端的嵌套缩进一致。
                    .padding(.leading, CGFloat(depth) * 24)
                }
            }
            .padding(.leading, 2)
        }
    }
}


/// 解析 ```lang [filename[:line]]``` 形式的代码块顶栏 hint：第一个 token 当
/// 语言，后面作为文件名（可选带行号）。Codex 截图里 `Withdrawal.php (line 19)`
/// 就是这种"语言 + 文件名 + 行号"的组合，比单纯 `php` 标识更能定位代码。
struct CodeBlockHint: Equatable {
    let language: String
    let filename: String?
    let lineRange: String?
}

private func parseCodeBlockHint(_ lang: String?) -> CodeBlockHint? {
    guard let raw = lang?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
        return nil
    }
    let tokens = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard let first = tokens.first else { return nil }
    let language = String(first)
    var filename: String?
    var lineRange: String?
    if tokens.count > 1 {
        let rest = tokens[1].trimmingCharacters(in: .whitespaces)
        let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        filename = String(parts[0])
        if parts.count > 1 { lineRange = String(parts[1]) }
    }
    return CodeBlockHint(language: language, filename: filename, lineRange: lineRange)
}

/// 按代码块的语言返回一个图标和品牌色（Codex 风格）。
/// 不支持的语言返回 nil，调用方退回到纯文本 lang 标签。
func codeBlockLanguageBadge(_ lang: String?) -> (symbol: String, color: Color)? {
    guard let raw = lang?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
        return nil
    }
    switch raw {
    case "php":
        return ("chevron.left.forwardslash.chevron.right", Color(hex: 0x777BB4))
    case "js", "javascript":
        return ("curlybraces", Color(hex: 0xF7DF1E))
    case "ts", "typescript":
        return ("curlybraces", Color(hex: 0x3178C6))
    case "tsx":
        return ("curlybraces", Color(hex: 0x3178C6))
    case "jsx":
        return ("curlybraces", Color(hex: 0x61DAFB))
    case "swift":
        return ("swift", Color(hex: 0xFA7343))
    case "py", "python":
        return ("chevron.left.and.right", Color(hex: 0x3776AB))
    case "go":
        return ("circle.hexagongrid.fill", Color(hex: 0x00ADD8))
    case "rs", "rust":
        return ("gearshape.2.fill", Color(hex: 0xDEA584))
    case "rb", "ruby":
        return ("diamond.fill", Color(hex: 0xCC342D))
    case "java":
        return ("cup.and.saucer.fill", Color(hex: 0xE76F00))
    case "kt", "kotlin":
        return ("k.circle.fill", Color(hex: 0x7F52FF))
    case "vue":
        return ("v.square.fill", Color(hex: 0x42B883))
    case "html":
        return ("chevron.left.forwardslash.chevron.right", Color(hex: 0xE34F26))
    case "css":
        return ("paintbrush.fill", Color(hex: 0x1572B6))
    case "scss", "sass":
        return ("paintbrush.fill", Color(hex: 0xCD6799))
    case "json":
        return ("curlybraces", Color(hex: 0x9CA3AF))
    case "yaml", "yml":
        return ("list.bullet.indent", Color(hex: 0xCB171E))
    case "toml":
        return ("list.bullet.indent", Color(hex: 0x9C4221))
    case "xml":
        return ("chevron.left.forwardslash.chevron.right", Color(hex: 0x0060AC))
    case "sql":
        return ("cylinder.split.1x2.fill", Color(hex: 0xE38C00))
    case "sh", "bash", "zsh", "shell", "console":
        return ("terminal.fill", Color(hex: 0x4EAA25))
    case "dockerfile", "docker":
        return ("cube.transparent.fill", Color(hex: 0x2496ED))
    case "md", "markdown":
        return ("text.alignleft", Color(hex: 0x9CA3AF))
    case "ini", "conf", "env":
        return ("gearshape.fill", Color(hex: 0x6B7280))
    default:
        return ("doc.text.fill", Color(hex: 0x6B7280))
    }
}

/// Monospaced, copyable code container for a fenced block.
private struct CodeBlockView: View {
    let code: String
    let lang: String?
    @State private var copied = false
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale
    @Environment(\.conversationBodySize) private var conversationBodySize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if let hint = parseCodeBlockHint(lang) {
                    if let badge = codeBlockLanguageBadge(hint.language) {
                        Image(systemName: badge.symbol)
                            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                            .foregroundStyle(badge.color)
                            .accessibilityHidden(true)
                    }
                    Text(hint.language)
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let name = hint.filename {
                        Text(name)
                            .font(AppFont.systemScaled(.caption2, weight: .medium, multiplier: appFontScale.multiplier))
                            .foregroundStyle(DSHTheme.messageText.opacity(0.82))
                            .textSelection(.enabled)
                    }
                    if let line = hint.lineRange {
                        Text("(line \(line))")
                            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                            .foregroundStyle(DSHTheme.labelTertiary)
                            .textSelection(.enabled)
                    }
                } else if let lang, !lang.isEmpty {
                    if let badge = codeBlockLanguageBadge(lang) {
                        Image(systemName: badge.symbol)
                            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                            .foregroundStyle(badge.color)
                            .accessibilityHidden(true)
                    }
                    Text(lang)
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
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
                    .font(AppFont.monoScaled(size: 13, multiplier: appFontScale.multiplier))
                    .foregroundStyle(DSHTheme.messageText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
            }
        }
        .background(DSHTheme.codeBlockBg, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
    @Environment(\.conversationBodySize) private var conversationBodySize

    var body: some View {
        // ZCode 参考样式：标题就是一整行加粗文字，不带品牌色竖条或其它装饰，
        // 层级感全靠字号差与字重。
        MarkdownInlineFlow(
            segments: content,
            baseFontSize: pointSize,
            baseWeight: .semibold
        )
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, level == 1 ? 14 : (level == 2 ? 10 : 6))
        .padding(.bottom, 2)
    }

    private var pointSize: CGFloat {
        let multiplier = appFontScale.multiplier
        switch level {
        case 1: return (conversationBodySize + 5) * multiplier
        case 2: return (conversationBodySize + 3) * multiplier
        case 3: return (conversationBodySize + 1) * multiplier
        default: return conversationBodySize * multiplier
        }
    }
}

/// Codex-style blockquote: one quiet leading rule and secondary text, without
/// turning ordinary quoted prose into another card.
private struct QuoteView: View {
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale
    @Environment(\.conversationBodySize) private var conversationBodySize

    let segs: [MarkdownSegment]

    var body: some View {
        let bodySize = conversationBodySize * appFontScale.multiplier
        Text(MarkdownMessageView.inlineAttributed(segs, baseFontSize: bodySize))
            .foregroundStyle(DSHTheme.labelDim)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1).fill(DSHTheme.borderStrong).frame(width: 2)
            }
            .padding(.vertical, 3)
    }
}

/// Lightweight pipe-table renderer (`| a | b |` with a `|---|` header
/// separator). It stays flat in the transcript and renders inline markdown.
private struct TableView: View {
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale
    @Environment(\.conversationBodySize) private var conversationBodySize

    let headers: [String]
    let rows: [[String]]

    var body: some View {
        let bodySize = conversationBodySize * appFontScale.multiplier - 0.5
        // 不包横向 ScrollView：LazyVStack 行内嵌套滚动容器会让行高无法缓存，
        // 滚动经过时每帧重新排版整张表（主线程被打满、App 卡死）。cell 文本
        // 直接换行铺开，与 Codex 桌面端一致。
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                    MarkdownInlineFlow(
                        segments: MarkdownMessageView.inlineSegments(h),
                        baseFontSize: bodySize,
                        baseWeight: .semibold
                    )
                    // ZCode 参考样式：表头是暗灰小字，与数据行亮白正文拉开层次。
                    .foregroundStyle(DSHTheme.labelDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
                }
            }
            Rectangle()
                .fill(DSHTheme.border)
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { i, _ in
                        MarkdownInlineFlow(
                            segments: MarkdownMessageView.inlineSegments(i < row.count ? row[i] : ""),
                            baseFontSize: bodySize,
                            baseWeight: .regular
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 7)
                    }
                }
                if rowIndex < rows.count - 1 {
                    // 不用 Divider：无界宽度环境下它的宽度解算可能反复失效。
                    // 定高 Rectangle 的尺寸完全确定。
                    Rectangle()
                        .fill(DSHTheme.border.opacity(0.6))
                        .frame(height: 0.5)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    @Environment(\.conversationBodySize) private var conversationBodySize

    let items: [TaskItem]

    var body: some View {
        let bodySize = conversationBodySize * appFontScale.multiplier
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                        .font(.system(size: bodySize, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(item.checked ? DSHTheme.labelDim : DSHTheme.labelTertiary)
                        .frame(width: bodySize + 2, alignment: .leading)
                    MarkdownInlineFlow(segments: item.content, baseFontSize: bodySize, baseWeight: .regular)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(item.checked ? 0.66 : 1)
                        // 已勾选项视觉上略暗；SwiftUI Text 自身支持 strikethrough，这里靠
                        // segment 走 inlineAttributed 的 strikethrough 段，未来若 segment 模型
                        // 暴露 done 字段，再加整行删除线。
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(item.checked ? "已完成" : "待处理")
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
    @Environment(\.conversationBodySize) private var conversationBodySize

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

/// Codex-style inline flow: paints inline code spans as rounded pills that
/// sit on the text baseline, with the surrounding plain text rendered as
/// regular `Text`. Wraps `Layout` so SwiftUI handles line-breaking exactly
/// the same way `Text` does, but lets us layer real rounded backgrounds on
/// individual spans — `AttributedString.backgroundColor` only paints a flat
/// rectangle behind the glyphs, which is the v0.5.107 shortcoming.
struct MarkdownInlineFlow: View {
    let segments: [MarkdownSegment]
    let baseFontSize: CGFloat
    let baseWeight: Font.Weight
    var depth: Int = 0

    var body: some View {
        Text(MarkdownMessageView.inlineAttributed(segments, baseFontSize: baseFontSize, baseWeight: baseWeight))
            .foregroundStyle(DSHTheme.messageText)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ConversationBodySizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = 15
}
extension EnvironmentValues {
    var conversationBodySize: CGFloat {
        get { self[ConversationBodySizeKey.self] }
        set { self[ConversationBodySizeKey.self] = newValue }
    }
}
