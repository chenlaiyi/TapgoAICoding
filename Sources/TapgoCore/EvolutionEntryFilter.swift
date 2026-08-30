import Foundation

/// 「自进化日志」历史标签页的纯逻辑过滤层。
///
/// 历史条目（`EvolutionEntry`）里能搜的字段：版本号、commit 短哈希、
/// 一句话总结、逐条 changes、why、next。统一做大小写无关的子串匹配，
/// 空 query 直接返回原列表，让 UI 在搜索框为空时无任何副作用。
///
/// 设计初衷：v0.5.33 的 Next「评估条目按版本号搜索/过滤」一直只挂在
/// 脑子里没落地——版本号一多之后用户很难翻找（v0.5.x 系列已经有 37
/// 条）。这里把过滤抽成纯 Foundation，可在 TapgoTests 中独立单测，UI
/// 层只负责读取 query 调用 `filter` + 渲染，不掺杂任何字符串处理。
public struct EvolutionEntryFilter {
    public init() {}

    /// 单条匹配。空 / 纯空白 query 永远不匹配任何条目，确保「没有过滤」
    /// 是「全部显示」而不是「全部隐藏」。
    public func matches(_ entry: EvolutionEntry, query rawQuery: String) -> Bool {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }
        let needle = query.lowercased()
        if entry.version.lowercased().contains(needle) { return true }
        if let commit = entry.commit, commit.lowercased().contains(needle) { return true }
        if let tag = entry.tag, tag.lowercased().contains(needle) { return true }
        if entry.summary.lowercased().contains(needle) { return true }
        if entry.changes.contains(where: { $0.lowercased().contains(needle) }) {
            return true
        }
        if entry.why.lowercased().contains(needle) { return true }
        if entry.next.lowercased().contains(needle) { return true }
        return false
    }

    /// 过滤整段历史。空 query 直接返回原数组（保持调用方对「未过滤」
    /// 状态的判断，方便 UI 层在 query 为空时直接复用原始 history）。
    public func filter(
        _ history: [EvolutionEntry],
        query rawQuery: String
    ) -> [EvolutionEntry] {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return history }
        return history.filter { matches($0, query: trimmed) }
    }
}

/// 自进化日志历史条目。和 SwiftUI 视图解耦，方便在 `TapgoTests`
/// 里单测过滤逻辑；UI 层在「自进化日志」sheet 里直接渲染。
public struct EvolutionEntry: Identifiable, Equatable, Sendable {
    public let version: String
    public let date: String
    public let commit: String?
    public let tag: String?
    public let summary: String
    public let changes: [String]
    public let why: String
    public let next: String

    public init(
        version: String,
        date: String,
        commit: String?,
        tag: String?,
        summary: String,
        changes: [String],
        why: String,
        next: String
    ) {
        self.version = version
        self.date = date
        self.commit = commit
        self.tag = tag
        self.summary = summary
        self.changes = changes
        self.why = why
        self.next = next
    }

    /// SwiftUI Identifiable 要求的稳定 id：
    ///   - 有 commit 的条目用 `commit ?? version`（同一份源码多个版本
    ///     不可能共享 commit，所以天然稳定）；
    ///   - 无 commit 的兜底用 `version`（保证同一版本稳定）。
    public var id: String { commit ?? version }
}
