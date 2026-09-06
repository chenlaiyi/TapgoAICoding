import Foundation

/// A small, dependency-free markdown-lite tokenizer. It understands the
/// subset Codex-style assistant messages actually use most: fenced code
/// blocks (``` … ```), inline code (`…`), and bold (**…**). Everything
/// else passes through as plain `.text`. We deliberately don't pull in a
/// full markdown framework — the app is a tiny SwiftPM package with no
/// dependencies, and this covers the cases that make a reply readable.
/// One task-list entry: a checkbox state plus the (inline-parsed) label.
public struct TaskItem: Equatable {
    public let checked: Bool
    public let content: [MarkdownSegment]
    public init(checked: Bool, content: [MarkdownSegment]) {
        self.checked = checked
        self.content = content
    }
}

public enum MarkdownSegment: Equatable {
    case text(String)
    case codeFence(String, lang: String?)
    case inline(String)
    case bold(String)
    case strikethrough(String)
    case link(title: String, url: String)
    /// 路径 + 可选行号：识别 `path/to/file.ext:line` 与
    /// `path/to/file.ext (line N)` 两种 Codex 截图里的写法；不带行号时 line=nil。
    case fileReference(path: String, line: Int?)
    case image(alt: String, url: String)
    case heading(level: Int, content: [MarkdownSegment])
    case blockquote([MarkdownSegment])
    case horizontalRule
    case bulletList(items: [[MarkdownSegment]], depths: [Int])
    case numberedList(items: [[MarkdownSegment]], depths: [Int])
    case taskList([TaskItem])
    case table(headers: [String], rows: [[String]])
}



public enum MarkdownLite {
    /// 解析结果缓存。消息视图每次刷新都会对同一段文本重新 parse，超大消息
    /// （数十万字符）会把主线程拖死；keyed by (count, hash)，命中即免解析。
    private static let cacheLock = NSLock()
    private static var cachedParses: [ParseKey: [MarkdownSegment]] = [:]
    private static let parseCacheLimit = 32

    private struct ParseKey: Hashable {
        let charCount: Int
        let hash: Int
    }

    /// `parse` 的缓存版本，供渲染层高频调用。流式增量会不断产生新 key，
    /// 超过上限后随机逐出，避免缓存无界增长。
    public static func parseCached(_ s: String) -> [MarkdownSegment] {
        let key = ParseKey(charCount: s.count, hash: s.hashValue)
        cacheLock.lock()
        if let hit = cachedParses[key] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        let parsed = parse(s)

        cacheLock.lock()
        if cachedParses.count >= parseCacheLimit {
            cachedParses.removeValue(forKey: cachedParses.keys.first!)
        }
        cachedParses[key] = parsed
        cacheLock.unlock()
        return parsed
    }

    /// Tokenize a whole message. Fenced code blocks become `.codeFence`,
    /// contiguous bullet/numbered lines become a `.bulletList` /
    /// `.numberedList`, and the surrounding text is split into
    /// `.text` / `.inline` / `.bold` runs.
    public static func parse(_ s: String) -> [MarkdownSegment] {
        var segs: [MarkdownSegment] = []
        let lines = s.components(separatedBy: "\n")
        var i = 0
        let n = lines.count

        func flushText(_ buf: [String]) {
            if !buf.isEmpty {
                segs.append(contentsOf: parseInline(buf.joined(separator: "\n")))
            }
        }

        while i < n {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                var closed = false
                while i < n {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        closed = true
                        i += 1
                        break
                    }
                    code.append(lines[i])
                    i += 1
                }
                if !closed && code.isEmpty {
                    segs.append(.text("```"))
                } else {
                    segs.append(.codeFence(code.joined(separator: "\n"), lang: lang.isEmpty ? nil : lang))
                }
                continue
            }

            // Horizontal rule (--- / *** / ___ as its own line).
            if isHorizontalRule(trimmed) {
                segs.append(.horizontalRule)
                i += 1
                continue
            }

            // ATX heading (# … / ## …).
            if let level = headingLevel(trimmed) {
                let content = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                segs.append(.heading(level: level, content: parseInline(content)))
                i += 1
                continue
            }

            // Blockquote (> …), grouping consecutive lines.
            if trimmed.hasPrefix(">") {
                var quote: [String] = []
                while i < n {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix(">") {
                        var content = String(t.dropFirst())
                        if content.hasPrefix(" ") { content.removeFirst() }
                        quote.append(content)
                        i += 1
                    } else {
                        break
                    }
                }
                segs.append(.blockquote(parseInline(quote.joined(separator: "\n"))))
                continue
            }

            // Table (| a | b | … with a |---| separator).
            if trimmed.hasPrefix("|"), let tbl = parseTable(lines, at: i) {
                segs.append(.table(headers: tbl.headers, rows: tbl.rows))
                i = tbl.end
                continue
            }

            // Task list (- [ ] item / - [x] done).
            if classifyTask(line) != nil {
                var items: [TaskItem] = []
                while i < n {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("```") || isHorizontalRule(t) { break }
                    if t.hasPrefix("|") { break }
                    guard let it = classifyTask(lines[i]) else { break }
                    items.append(TaskItem(checked: it.checked, content: parseInline(it.content)))
                    i += 1
                }
                segs.append(.taskList(items))
                continue
            }

            if let item = classifyList(line) {
                var items: [[MarkdownSegment]] = []
                var depths: [Int] = []
                let ordered = item.ordered
                while i < n {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("```") { break }
                    if isHorizontalRule(t) { break }
                    if headingLevel(t) != nil { break }
                    if t.hasPrefix(">") { break }
                    if t.hasPrefix("|"), parseTable(lines, at: i) != nil { break }
                    guard let it = classifyList(lines[i]), it.ordered == ordered, classifyTask(lines[i]) == nil else { break }
                    items.append(parseInline(it.content))
                    depths.append(listDepth(of: lines[i]))
                    i += 1
                }
                if ordered {
                    segs.append(.numberedList(items: items, depths: depths))
                } else {
                    segs.append(.bulletList(items: items, depths: depths))
                }
                continue
            }

            var buf: [String] = []
            while i < n {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("```") { break }
                if isHorizontalRule(t) { break }
                if headingLevel(t) != nil { break }
                if t.hasPrefix(">") { break }
                if t.hasPrefix("|"), parseTable(lines, at: i) != nil { break }
                if classifyList(lines[i]) != nil { break }
                buf.append(lines[i])
                i += 1
            }
            flushText(buf)
        }
        return segs
    }

    /// True when a line is a horizontal rule: `---`, `***`, or `___`
    /// (3+ of the same marker).
    static func isHorizontalRule(_ trimmed: String) -> Bool {
        let s = trimmed.trimmingCharacters(in: .whitespaces)
        guard s.count >= 3 else { return false }
        let c = s.first!
        return (c == "-" || c == "*" || c == "_") && s.allSatisfy { $0 == c }
    }

    /// ATX heading level (`#` … `######`), or nil if the line isn't a
    /// heading. The `#` run must be followed by a space (or be the whole
    /// line) so `#notheading` stays text.
    static func headingLevel(_ trimmed: String) -> Int? {
        var i = 0
        for c in trimmed {
            if c == "#" { i += 1 } else { break }
        }
        guard i >= 1, i <= 6 else { return nil }
        let after = trimmed.index(trimmed.startIndex, offsetBy: i)
        if after == trimmed.endIndex { return i }
        if trimmed[after] == " " { return i }
        return nil
    }

    /// Parse a markdown pipe table starting at `i`. Returns the header
    /// row, the body rows, and the index just past the last table line.
    /// Returns nil if the block isn't a well-formed table (needs ≥ 2
    /// `|` lines and a separator at index 1).
    static func parseTable(_ lines: [String], at i: Int) -> (headers: [String], rows: [[String]], end: Int)? {
        let n = lines.count
        guard i < n else { return nil }
        var block: [String] = []
        var j = i
        while j < n {
            let t = lines[j].trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") {
                block.append(t)
                j += 1
            } else {
                break
            }
        }
        guard block.count >= 2 else { return nil }
        guard let headers = tableCells(block[0]), headers.count >= 2 else { return nil }
        guard isTableSeparator(block[1]) else { return nil }
        let rows = block[2...].compactMap { tableCells($0) }
        return (headers, rows, j)
    }

    /// Split a `| a | b |` line into trimmed cell strings.
    static func tableCells(_ line: String) -> [String]? {
        var t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("|") else { return nil }
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// True when a line is a table separator (`|---|---|` or `|:--:|`).
    static func isTableSeparator(_ line: String) -> Bool {
        guard let c = tableCells(line) else { return false }
        return c.allSatisfy { $0.isEmpty || $0.allSatisfy { $0 == "-" || $0 == ":" } }
    }

    /// Classify a task-list line (`- [ ] label` / `- [x] label`) as
    /// (checked, label). Returns nil for anything else.
    static func classifyTask(_ line: String) -> (checked: Bool, content: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Markers: -, *, or +.
        guard trimmed.count > 2 else { return nil }
        let markers: [Character] = ["-", "*", "+"]
        guard let first = trimmed.first, markers.contains(first) else { return nil }
        let afterMarker = trimmed.dropFirst().trimmingCharacters(in: .whitespaces) // drop "-"/"*"/"+", then spaces
        guard afterMarker.hasPrefix("[") else { return nil }
        let afterBracket = afterMarker.dropFirst() // drop "["
        let checkChar = afterBracket.first
        let checked: Bool
        if checkChar == "x" || checkChar == "X" { checked = true }
        else if checkChar == " " || checkChar == nil { checked = false }
        else { return nil }
        // Next char must be "]".
        guard afterBracket.count > 1 else { return nil }
        let idx = afterBracket.index(after: afterBracket.startIndex)
        guard afterBracket[idx] == "]" else { return nil }
        // Content after "] ".
        var content = String(afterBracket[afterBracket.index(after: idx)...])
        if content.hasPrefix(" ") { content.removeFirst() }
        return (checked, content)
    }

    /// Classify a line as a list item, returning the marker-stripped
    /// content and whether it's an ordered list. Unordered markers:
    /// `- ` / `* ` / `+ `. Ordered markers: `<number>. ` / `<number>) `.
    static func classifyList(_ line: String) -> (content: String, ordered: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        for marker in ["- ", "* ", "+ "] {
            if trimmed.hasPrefix(marker) {
                return (String(trimmed.dropFirst(marker.count)), false)
            }
        }
        if let r = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
            return (String(trimmed[r.upperBound...]), true)
        }
        return nil
    }

    /// Count nested-list depth by measuring the leading whitespace before the
    /// marker. Each 2-space indent is one depth level (matches the common
    /// markdown convention and is forgiving for both 2- and 4-space authors).
    /// Lines that are already trimmed at column 0 stay at depth 0.
    static func listDepth(of line: String) -> Int {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let leading = line.distance(from: line.startIndex, to: line.range(of: trimmed)?.lowerBound ?? line.startIndex)
        return max(0, leading / 2)
    }

    /// Split a run of text into `.text` / `.inline` / `.bold` /
    /// `.link` segments. Inline code takes a single backtick on each
    /// side and never spans newlines; bold uses double asterisks; links
    /// are either `[title](url)` or a bare `http(s)://…` URL.
    public static func parseInline(_ text: String) -> [MarkdownSegment] {
        var out: [MarkdownSegment] = []
        var literal = ""
        var i = text.startIndex
        let n = text.endIndex

        func flushLiteral() {
            if !literal.isEmpty {
                out.append(contentsOf: splitFileReferences(splitAutolinks(literal)))
                literal = ""
            }
        }

        while i < n {
            let rest = text[i...]
            if rest.hasPrefix("**") {
                let after = text.index(i, offsetBy: 2)
                if let close = text[after...].range(of: "**") {
                    let inner = String(text[after..<close.lowerBound])
                    flushLiteral()
                    out.append(.bold(inner))
                    i = close.upperBound
                    continue
                }
            }
            if rest.hasPrefix("~~") {
                let after = text.index(i, offsetBy: 2)
                if let close = text[after...].range(of: "~~") {
                    let inner = String(text[after..<close.lowerBound])
                    flushLiteral()
                    out.append(.strikethrough(inner))
                    i = close.upperBound
                    continue
                }
            }
            if text[i] == "`" {
                let after = text.index(after: i)
                if let close = text[after...].range(of: "`") {
                    let inner = String(text[after..<close.lowerBound])
                    flushLiteral()
                    out.append(.inline(inner))
                    i = close.upperBound
                    continue
                }
            }
            if text[i] == "[", let link = scanLink(text, at: i) {
                flushLiteral()
                out.append(.link(title: link.title, url: link.url))
                i = link.end
                continue
            }
            if text[i] == "!", let image = scanImage(text, at: i) {
                flushLiteral()
                out.append(.image(alt: image.alt, url: image.url))
                i = image.end
                continue
            }
            literal.append(text[i])
            i = text.index(after: i)
        }
        flushLiteral()
        return out
    }

    /// Try to parse a `[title](url)` starting at `i` (which points at
    /// `[`). Returns nil if the shape isn't there.
    private static func scanLink(_ text: String, at i: String.Index) -> (title: String, url: String, end: String.Index)? {
        guard let closeBracket = text[i...].range(of: "]") else { return nil }
        let title = String(text[text.index(after: i)..<closeBracket.lowerBound])
        let afterBracket = closeBracket.upperBound
        guard afterBracket < text.endIndex, text[afterBracket] == "(" else { return nil }
        let afterParen = text.index(after: afterBracket)
        guard let closeParen = text[afterParen...].range(of: ")") else { return nil }
        let url = String(text[afterParen..<closeParen.lowerBound])
        guard !title.isEmpty, !url.isEmpty else { return nil }
        return (title, url, closeParen.upperBound)
    }

    /// Try to parse a `![alt](url)` image starting at `i` (which points
    /// at `!`). Returns nil if the shape isn't there.
    private static func scanImage(_ text: String, at i: String.Index) -> (alt: String, url: String, end: String.Index)? {
        let bracketStart = text.index(after: i)
        guard bracketStart < text.endIndex, text[bracketStart] == "[" else { return nil }
        guard let closeBracket = text[bracketStart...].range(of: "]") else { return nil }
        let alt = String(text[text.index(after: bracketStart)..<closeBracket.lowerBound])
        let afterBracket = closeBracket.upperBound
        guard afterBracket < text.endIndex, text[afterBracket] == "(" else { return nil }
        let afterParen = text.index(after: afterBracket)
        guard let closeParen = text[afterParen...].range(of: ")") else { return nil }
        let url = String(text[afterParen..<closeParen.lowerBound])
        guard !url.isEmpty else { return nil }
        return (alt, url, closeParen.upperBound)
    }

    /// Split bare `http(s)://` URLs out of a literal run so they render
    /// as clickable links.
    private static func splitAutolinks(_ s: String) -> [MarkdownSegment] {
        let pattern = #"https?://[^\s)]+"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [.text(s)] }
        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        var out: [MarkdownSegment] = []
        var last = 0
        for m in re.matches(in: ns as String, options: [], range: full) {
            if m.range.location > last {
                let t = ns.substring(with: NSRange(location: last, length: m.range.location - last))
                out.append(.text(t))
            }
            let url = ns.substring(with: m.range)
            out.append(.link(title: url, url: url))
            last = m.range.location + m.range.length
        }
        if last < ns.length {
            out.append(.text(ns.substring(from: last)))
        }
        if out.isEmpty { out.append(.text(s)) }
        return out
    }

    /// Split `path/to/file.ext:line` and `path/to/file.ext (line N)` out of a
    /// literal run. Each match becomes a `.fileReference(path:line:)` segment;
    /// anything else (already-typed plain text or `.link` segments) is left
    /// untouched. The path must contain a `/` or end with a recognised file
    /// extension to avoid matching bare numbers like `123` or `:8080`.
    private static func splitFileReferences(
        _ segs: [MarkdownSegment]
    ) -> [MarkdownSegment] {
        var out: [MarkdownSegment] = []
        out.reserveCapacity(segs.count)
        for seg in segs {
            guard case .text(let s) = seg else {
                out.append(seg); continue
            }
            out.append(contentsOf: splitFileReferencesInString(s))
        }
        return out
    }

    private static let fileReferenceColonPattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"(?<path>[A-Za-z0-9_./-]+?\.[A-Za-z0-9]+):(?<line>\d+)\b"#)
    }()

    private static let fileReferenceParenPattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"(?<path>[A-Za-z0-9_./-]+?\.[A-Za-z0-9]+)\s+\(line\s+(?<line>\d+)\)"#)
    }()

    private static func splitFileReferencesInString(
        _ s: String
    ) -> [MarkdownSegment] {
        // We walk s once, matching either pattern; longer matches win by scanning
        // colon first then paren at each position. Both regexes are anchored to
        // a path ending in `.ext` and a trailing line number, so ordinary
        // numbers / URLs / prose don't trip.
        var out: [MarkdownSegment] = []
        let ns = s as NSString
        var cursor = 0
        while cursor < ns.length {
            let from = NSRange(location: cursor, length: ns.length - cursor)
            // Find the earliest match of either pattern from `cursor`.
            var best: (range: NSRange, path: String, line: Int)? = nil
            if let re = fileReferenceColonPattern,
               let m = re.firstMatch(in: ns as String, options: [], range: from) {
                let path = ns.substring(with: m.range(withName: "path"))
                let lineStr = ns.substring(with: m.range(withName: "line"))
                if let ln = Int(lineStr) {
                    best = (m.range, path, ln)
                }
            }
            if let re = fileReferenceParenPattern,
               let m = re.firstMatch(in: ns as String, options: [], range: from) {
                let path = ns.substring(with: m.range(withName: "path"))
                let lineStr = ns.substring(with: m.range(withName: "line"))
                if let ln = Int(lineStr) {
                    if best == nil || m.range.location < best!.range.location {
                        best = (m.range, path, ln)
                    }
                }
            }
            guard let hit = best else {
                out.append(.text(ns.substring(from: cursor)))
                break
            }
            if hit.range.location > cursor {
                out.append(.text(ns.substring(with: NSRange(location: cursor, length: hit.range.location - cursor))))
            }
            out.append(.fileReference(path: hit.path, line: hit.line))
            cursor = hit.range.location + hit.range.length
        }
        if out.isEmpty { out.append(.text(s)) }
        return out
    }
}
