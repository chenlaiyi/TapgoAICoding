import SwiftUI
import UIKit

private enum MessageBlock {
    case paragraph(String)
    case heading(Int, String)
    case code(String, String)
    case list([MessageListItem])
    case quote(String)
    case rule
    case table([[String]])
}

private struct MessageListItem {
    let depth: Int
    let marker: String
    let text: String
    let checked: Bool?
}

private enum MessageMarkdown {
    static func parse(_ source: String) -> [MessageBlock] {
        let lines = source.components(separatedBy: "\n")
        var blocks: [MessageBlock] = []
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { index += 1; continue }
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let fence = String(line.prefix(3))
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var code: [String] = []
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(language, code.joined(separator: "\n")))
                continue
            }
            let hashes = line.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), line.dropFirst(hashes).hasPrefix(" ") {
                blocks.append(.heading(hashes, String(line.dropFirst(hashes + 1))))
                index += 1
                continue
            }
            if line.count >= 3, Set(line.filter { !$0.isWhitespace }).isSubset(of: Set<Character>(["-", "*", "_"])),
               Set(line.filter { !$0.isWhitespace }).count == 1 {
                blocks.append(.rule)
                index += 1
                continue
            }
            if line.hasPrefix(">") {
                var quoted: [String] = []
                while index < lines.count {
                    let current = lines[index].trimmingCharacters(in: .whitespaces)
                    guard current.hasPrefix(">") else { break }
                    quoted.append(String(current.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quoted.joined(separator: "\n")))
                continue
            }
            if let first = listItem(lines[index]) {
                var items = [first]
                index += 1
                while index < lines.count, let next = listItem(lines[index]) {
                    items.append(next)
                    index += 1
                }
                blocks.append(.list(items))
                continue
            }
            if index + 1 < lines.count, line.contains("|"), isTableDivider(lines[index + 1]) {
                var rows = [tableCells(line)]
                index += 2
                while index < lines.count, lines[index].contains("|"),
                      !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(tableCells(lines[index]))
                    index += 1
                }
                blocks.append(.table(rows))
                continue
            }
            var paragraph = [lines[index]]
            index += 1
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty,
                  !startsBlock(lines[index]) {
                paragraph.append(lines[index])
                index += 1
            }
            blocks.append(.paragraph(softWrapped(paragraph)))
        }
        return blocks
    }

    private static func startsBlock(_ source: String) -> Bool {
        let line = source.trimmingCharacters(in: .whitespaces)
        let hashes = line.prefix(while: { $0 == "#" }).count
        return line.hasPrefix("```") || line.hasPrefix("~~~") || line.hasPrefix(">")
            || ((1...6).contains(hashes) && line.dropFirst(hashes).hasPrefix(" "))
            || listItem(line) != nil
    }

    private static func listItem(_ source: String) -> MessageListItem? {
        let indent = source.prefix(while: { $0 == " " || $0 == "\t" })
            .reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let line = source.trimmingCharacters(in: .whitespaces)
        var marker: String
        var content: String
        if let bullet = ["- ", "* ", "+ "].first(where: { line.hasPrefix($0) }) {
            marker = "•"
            content = String(line.dropFirst(bullet.count))
        } else {
            guard let dot = line.firstIndex(of: "."), dot != line.startIndex,
                  line[line.startIndex..<dot].allSatisfy(\.isNumber),
                  line[line.index(after: dot)...].hasPrefix(" ") else { return nil }
            marker = String(line[...dot])
            content = String(line[line.index(dot, offsetBy: 2)...])
        }
        let checked: Bool?
        if content.hasPrefix("[ ] ") {
            checked = false
            content = String(content.dropFirst(4))
        } else if content.hasPrefix("[x] ") || content.hasPrefix("[X] ") {
            checked = true
            content = String(content.dropFirst(4))
        } else {
            checked = nil
        }
        return MessageListItem(depth: min(indent / 2, 4), marker: marker,
                               text: content, checked: checked)
    }

    private static func softWrapped(_ lines: [String]) -> String {
        guard let first = lines.first else { return "" }
        return lines.dropFirst().reduce(first.trimmingCharacters(in: .whitespaces)) { result, line in
            let hardBreak = result.hasSuffix("  ") || result.hasSuffix("\\")
            let separator = hardBreak ? "\n" : " "
            return result.trimmingCharacters(in: .whitespaces) + separator
                + line.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func isTableDivider(_ source: String) -> Bool {
        let cells = tableCells(source)
        return !cells.isEmpty && cells.allSatisfy { cell in
            let marks = cell.filter { !$0.isWhitespace }
            return marks.filter { $0 == "-" }.count >= 3
                && marks.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func tableCells(_ source: String) -> [String] {
        var line = source.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("|") { line.removeFirst() }
        if line.hasSuffix("|") { line.removeLast() }
        return line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

struct AssistantMessageView: View {
    let text: String
    let reasoning: String?
    var showCopy = true
    /// Whether a code block at this Markdown block index was left expanded.
    var expandedCodeBlocks: (Int) -> Bool = { _ in false }
    /// Records a code block's expand or collapse.
    var onCodeExpansionChange: ((Int, Bool) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let reasoning, !reasoning.isEmpty {
                DisclosureGroup("思考过程") {
                    markdown(reasoning)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .font(.system(size: 13))
            }
            markdown(text)
            if showCopy && !text.isEmpty {
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Label("复制", systemImage: "square.on.square")
                        .font(.system(size: 12))
                        .frame(height: 28)
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("复制回复")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func markdown(_ source: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MessageMarkdown.parse(source).enumerated()), id: \.offset) { index, block in
                blockView(block, index: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MessageBlock, index: Int) -> some View {
        switch block {
        case .paragraph(let value):
            inline(value).font(.system(size: 15)).lineSpacing(4)
        case .heading(let level, let value):
            inline(value)
                .font(.system(size: level == 1 ? 19 : level == 2 ? 17 : 15, weight: .semibold))
                .lineSpacing(3)
        case .code(let language, let value):
            AssistantCodeBlock(language: language, value: value,
                               initialExpanded: expandedCodeBlocks(index),
                               onExpandedChange: onCodeExpansionChange.map { callback in
                                   { expanded in callback(index, expanded) }
                               })
        case .list(let items):
            let markerWidth = max(18, items.map {
                ceil(($0.marker as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 15)]).width)
            }.max() ?? 18)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let checked = item.checked {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .foregroundStyle(.secondary)
                                .frame(width: markerWidth)
                        } else {
                            Text(item.marker)
                                .foregroundStyle(.secondary)
                                .frame(width: markerWidth, alignment: .trailing)
                        }
                        inline(item.text).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 15)).lineSpacing(4)
                    .padding(.leading, CGFloat(item.depth) * 14)
                }
            }
        case .quote(let value):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.45)).frame(width: 3)
                inline(value).font(.system(size: 15)).foregroundStyle(.secondary).lineSpacing(4)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .rule:
            Divider()
        case .table(let rows):
            if (rows.first?.count ?? 0) <= 3 {
                tableRows(rows, compact: true)
            } else {
                ScrollView(.horizontal) {
                    tableRows(rows, compact: false)
                }
            }
        }
    }

    private func tableRows(_ rows: [[String]], compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        inline(cell)
                            .font(.system(size: 12, weight: rowIndex == 0 ? .semibold : .regular))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minWidth: compact ? 0 : 105,
                                   maxWidth: compact ? .infinity : nil,
                                   alignment: .leading)
                            .padding(8)
                    }
                }
                if rowIndex < rows.count - 1 { Divider() }
            }
        }
        .frame(maxWidth: compact ? .infinity : nil, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    private func inline(_ source: String) -> Text {
        guard let content = try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return Text(source) }
        return Text(content)
    }
}

/// One fenced code block: horizontal scrolling, bounded height, copy, and partial selection.
private struct AssistantCodeBlock: View {
    let language: String
    let value: String
    let onExpandedChange: ((Bool) -> Void)?
    @State private var expanded: Bool

    init(language: String, value: String, initialExpanded: Bool = false,
         onExpandedChange: ((Bool) -> Void)? = nil) {
        self.language = language
        self.value = value
        self.onExpandedChange = onExpandedChange
        _expanded = State(initialValue: initialExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language.isEmpty ? "代码" : language)
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = value
                } label: {
                    Label("复制", systemImage: "square.on.square")
                        .font(.caption2)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("复制代码")
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            Divider()
            ScrollView(.horizontal, showsIndicators: true) {
                Text(MobileCodePreview.visible(value, expanded: expanded))
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if MobileCodePreview.isCollapsible(value) {
                Divider()
                Button(expanded ? "收起代码" : "展开全部（\(MobileCodePreview.lineCount(value)) 行）") {
                    expanded.toggle()
                    onExpandedChange?(expanded)
                }
                .font(.caption)
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
                .accessibilityLabel(expanded ? "收起代码" : "展开全部 \(MobileCodePreview.lineCount(value)) 行代码")
                .accessibilityValue(expanded ? "已展开" : "已收起")
            }
        }
        .background(Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 10))
    }
}
