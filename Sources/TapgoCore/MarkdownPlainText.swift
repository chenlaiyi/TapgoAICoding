import Foundation

/// Copy readable content without losing code or interpreting its syntax as prose.
public enum MarkdownPlainText {
    public static func render(_ text: String) -> String {
        renderSegments(MarkdownLite.parse(text)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func renderSegments(_ segments: [MarkdownSegment]) -> String {
        segments.map { segment in
            switch segment {
            case .text(let text), .inline(let text): return text
            case .bold(let text), .strikethrough(let text): return renderSegments(MarkdownLite.parseInline(text))
            case .fileReference(let path, let line): return line.map { "\(path):\($0)" } ?? path
            case .image(_, let url): return url
            case .link(let title, _): return title
            case .image(let alt, _): return alt
            case .codeFence(let code, _): return "\n\n" + code + "\n\n"
            case .heading(_, let content), .blockquote(let content): return "\n\n" + renderSegments(content) + "\n\n"
            case .horizontalRule: return "\n\n"
            case .bulletList(let items, _): return "\n" + items.map { "• " + renderSegments($0) }.joined(separator: "\n") + "\n"
            case .numberedList(let items, _): return "\n" + items.enumerated().map { "\($0.offset + 1). " + renderSegments($0.element) }.joined(separator: "\n") + "\n"
            case .taskList(let items): return "\n" + items.map { ($0.checked ? "☑ " : "☐ ") + renderSegments($0.content) }.joined(separator: "\n") + "\n"
            case .table(let headers, let rows): return "\n" + ([headers] + rows).map { $0.map { renderSegments(MarkdownLite.parseInline($0)) }.joined(separator: "\t") }.joined(separator: "\n") + "\n"
            }
        }.joined()
    }
}
