import Foundation

/// 自进化 backlog 的纯解析模型（TapgoCore，可被 App 与测试共用）。
///
/// 数据源固定为项目根下的 `evolution/BACKLOG.md`，格式约定：
///   - `## P0 — ...` / `## P1 — ...` 标记优先级段；
///   - `- [ ] **EVO-005 标题**：详情` 为未完成项；
///   - `- [x] ...` 为已完成项。
///
/// App 用它把“下一项该做什么”直接显示在自进化横幅里，并把该项注入
/// kickoff prompt；命令行 `scripts/evolution-backlog.py` 使用同一份格式。
public struct EvolutionBacklogItem: Equatable, Identifiable {
    public let id: String
    public let priority: String
    public let title: String
    public let detail: String
    public let done: Bool

    public init(id: String, priority: String, title: String, detail: String, done: Bool) {
        self.id = id
        self.priority = priority
        self.title = title
        self.detail = detail
        self.done = done
    }

    /// 注入 prompt 的单行形式。
    public var promptLine: String {
        detail.isEmpty ? "\(id) \(title)" : "\(id) \(title)：\(detail)"
    }
}

public enum EvolutionBacklog {
    public static let relativePath = "evolution/BACKLOG.md"

    /// 解析 backlog 文本，保持文件顺序（backlog 文件本身按优先级排序）。
    public static func parse(_ text: String) -> [EvolutionBacklogItem] {
        var items: [EvolutionBacklogItem] = []
        var priority = "P?"
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## P") {
                let header = line.dropFirst(3)
                priority = String(header.prefix { $0 != " " && $0 != "—" })
                continue
            }
            let isOpen = line.hasPrefix("- [ ] ")
            let isDone = line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ")
            guard isOpen || isDone else { continue }
            var body = String(line.dropFirst(6))
            guard body.hasPrefix("**"),
                  let closeRange = body.range(of: "**", options: [], range: body.index(body.startIndex, offsetBy: 2)..<body.endIndex) else {
                continue
            }
            let head = String(body[body.index(body.startIndex, offsetBy: 2)..<closeRange.lowerBound])
            body = String(body[closeRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if body.hasPrefix(":") || body.hasPrefix("：") {
                body = String(body.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            let parts = head.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count >= 2 else { continue }
            items.append(EvolutionBacklogItem(
                id: parts[0],
                priority: priority,
                title: parts[1],
                detail: body,
                done: isDone
            ))
        }
        return items
    }

    /// 取第一个未完成项；backlog 文件按优先级书写，因此文件顺序即优先级。
    public static func topOpen(in items: [EvolutionBacklogItem]) -> EvolutionBacklogItem? {
        items.first { !$0.done }
    }

    /// 从项目根读取 `evolution/BACKLOG.md` 并取顶部未完成项。
    public static func topOpen(projectRoot: URL) -> EvolutionBacklogItem? {
        let url = projectRoot.appendingPathComponent(relativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return topOpen(in: parse(text))
    }
}
