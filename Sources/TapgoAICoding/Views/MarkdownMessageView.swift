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
        VStack(alignment: .leading, spacing: 6) {
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
            // 流式光标紧贴最后一段（避免光标独立成行撑高卡片）。
            if isStreaming, let lastPara = lastParagraphRange() {
                InlineStreamingCursor()
                    .padding(.leading, 1)
                    .padding(.top, -3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(lastPara)
            } else if isStreaming {
                InlineStreamingCursor()
                    .padding(.top, -2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 当前助手消息的 markdown 块列表。缓存避免 `lastParagraphRange()` 重复解析。
    private var resolvedBlocks: [Block] {
        Self.blocks(MarkdownLite.parse(text))
    }

    /// 找到 blocks 中最后一个段落的位置（用于把光标定位到该段落末尾的同一行）。
    /// 仅在助手消息里有 .para 块时返回非空；否则光标退回到独立一行。
    private func lastParagraphRange() -> String? {
        for (offset, block) in resolvedBlocks.enumerated().reversed() {
            if case .para = block { return "cursor-after-\(offset)" }
        }
        return nil
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
            case .text(let text):
                appendText(text, to: &out, accumulator: &acc)
            case .inline, .bold, .link, .strikethrough:
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
        baseWeight: Font.Weight = .light
    ) -> AttributedString {
        var a = AttributedString()
        // 行内代码与正文同大，仅靠 monospace + 浅底色区分；
        // 字重抬到 medium，避免 monospace 在小字号下显得单薄、与正文形成可读对比。
        let inlineSize = baseFontSize
        let inlineWeight: Font.Weight = .medium
        for seg in segs {
            switch seg {
            case .text(let s):
                var r = AttributedString(s)
                r.font = .system(size: baseFontSize, weight: baseWeight)
                a += r
            case .inline(let s):
                var r = AttributedString(s)
                r.font = .system(size: inlineSize, weight: inlineWeight, design: .monospaced)
                r.foregroundColor = DSHTheme.messageText
                r.backgroundColor = DSHTheme.inlineCodeBg
                a += r
            case .bold(let s):
                var r = AttributedString(s)
                r.font = .system(size: baseFontSize, weight: .medium)
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


    /// 段落渲染：字号跟随 appFontScale，保持 Codex 的紧凑正文节奏；
    /// `fixedSize(horizontal:false, vertical:true)` 确保段落被允许按内容撑开高度（避免某些容器
    /// 默认 single-line 行为）。
    @ViewBuilder
    private func paragraphView(segs: [MarkdownSegment]) -> some View {
        let bodySize = AppFont.pointSize(for: .body, multiplier: appFontScale.multiplier)
        Text(Self.inlineAttributed(segs, baseFontSize: bodySize))
            .foregroundStyle(DSHTheme.messageText)
            .lineSpacing(2.5)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private struct ListView: View {
        @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale
        let items: [[MarkdownSegment]]
        let ordered: Bool

        var body: some View {
            // Codex uses a small but clearly visible marker and a compact row
            // rhythm; the previous 6pt gap amplified long tool inventories.
            let bodySize = AppFont.pointSize(for: .body, multiplier: appFontScale.multiplier)
            let markerSize = AppFont.pointSize(for: .footnote, multiplier: appFontScale.multiplier)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(idx + 1)." : "•")
                            // Bullet 比正文更淡一档（labelTertiary）+ 字重 .regular，
                            // 让眼睛把 bullet 当成"装饰"而不是"内容"。
                            .font(.system(size: markerSize, weight: .regular, design: .monospaced))
                            .foregroundStyle(DSHTheme.labelTertiary)
                            .frame(minWidth: ordered ? 18 : 14, alignment: .trailing)
                        Text(MarkdownMessageView.inlineAttributed(item, baseFontSize: bodySize))
                            .foregroundStyle(DSHTheme.messageText)
                            .textSelection(.enabled)
                            .lineSpacing(1.5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 2)
        }
    }
}


/// 按代码块的语言返回一个图标和品牌色（Codex 风格）。
/// 不支持的语言返回 nil，调用方退回到纯文本 lang 标签。
private func codeBlockLanguageBadge(_ lang: String?) -> (symbol: String, color: Color)? {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if let lang, !lang.isEmpty {
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
                    .font(AppFont.monoScaled(size: 12, multiplier: appFontScale.multiplier))
                    .foregroundStyle(DSHTheme.messageText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
            }
        }
        .background(DSHTheme.codeBlockBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DSHTheme.border, lineWidth: 1))
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

    var body: some View {
        Text(MarkdownMessageView.inlineAttributed(
            content,
            baseFontSize: pointSize,
            baseWeight: .medium
        ))
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(DSHTheme.messageText)
        .padding(.top, level <= 2 ? 5 : 2)
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

/// 行内流式光标：Codex 风格 2pt × 0.85em 文本高度，柔和呼吸，挂在最后一段
/// 同一行；多个段落时通过 SwiftUI 的 `lastTextBaseline` 锚定保持对齐。
private struct InlineStreamingCursor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale
    @State private var visible = false

    var body: some View {
        Capsule()
            .fill(DSHTheme.label)
            .frame(width: 2, height: 12 * appFontScale.multiplier)
            .opacity(reduceMotion || visible ? 0.85 : 0.18)
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
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
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
                    .padding(.vertical, 1)
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
        VStack(alignment: .leading, spacing: 3) {
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
