import Foundation

/// 当前模型订阅套餐的"使用情况"快照，用于在输入框下方右侧显示
/// "套餐用量"摘要。
///
/// v0.5.6 起由两条本地数据合成：
///   - `usedTokens`：当前会话累计 token（`Thread.usageTotal`）
///   - `contextWindow`：模型上下文窗口（来自最近一次 turn 的
///     `TokenUsage.contextWindow`，缺省时回落到 `TapgoConfig.autoCompactTokenLimit` × 2，
///     即 MiniMax-M3 的 1M 上下文窗口）
///
/// v0.5.9 接入 codex app-server 的 `account/rateLimits/read` 与
/// `account/rateLimits/updated` 通知，新增 `accountRateLimits`
/// （5h / 周两档），并把 `level` 升级为"任一档达到 critical 取
/// critical，否则取最高"——这样 chip 颜色始终反映最紧张的那档。
public struct SubscriptionUsage: Equatable, Hashable {

    /// 已用 token（当前会话累计）。
    public var usedTokens: Int

    /// 模型上下文窗口 token 数；用于计算"已用占比"。
    public var contextWindow: Int?

    /// v0.5.9: codex 上报的 5h / 周限速窗口（可能为 nil，比如还没
    /// 拿到响应或当前账号是免费档没有 weekly 窗口）。
    public var accountRateLimits: AccountRateLimits?

    /// 构造一个用量快照。
    public init(
        usedTokens: Int,
        contextWindow: Int?,
        accountRateLimits: AccountRateLimits? = nil
    ) {
        self.usedTokens = usedTokens
        self.contextWindow = contextWindow
        self.accountRateLimits = accountRateLimits
    }

    /// 上下文已用百分比，0–100；窗口未知或为 0 时返回 nil。
    public var percent: Int? {
        guard let cw = contextWindow, cw > 0, usedTokens > 0 else { return nil }
        let raw = Double(usedTokens) / Double(cw) * 100
        return min(100, max(0, Int(raw.rounded())))
    }

    /// 与 `TokenUsage.contextLevel` 一致的压力等级。v0.5.9 起，
    /// 若拿到了 codex 套餐用量，则优先按 5h / 周两档中压力更高的
    /// 一档判定——这样 ChatGPT Pro / MiniMax ultra 的"5 小时限额"
    /// 不会因为本会话 token 数低而被显示成绿色。
    public var level: ContextLevel {
        if let limits = accountRateLimits, let limitsLevel = limits.level {
            return limitsLevel
        }
        guard let pct = percent else { return .normal }
        if pct >= 80 { return .critical }
        if pct >= 50 { return .warn }
        return .normal
    }

    /// 是否应该显示该 chip。
    ///
    /// v0.5.9+：**始终返回 true**。ChatView 的输入框下方右侧
    /// 会一直挂一个 `subscriptionChip`，即便本会话尚未累计 token、
    /// codex `account/rateLimits/read` 还没响应，也保持渲染——
    /// 这能避免"新会话进来输入框下方右侧什么都没有"的视觉错觉。
    ///
    /// 缺数据时 `chipLabel` 自动降级为 `套餐用量 · 加载中`，
    /// `detailText` 降级为 `正在获取模型订阅套餐用量…`，
    /// 让用户清楚这是"还没拉到数据"而不是"没开发好"。
    ///
    /// 历史 v0.5.6 行为（仅 `usedTokens > 0` 时显示）已弃用。
    public var isVisible: Bool { true }

    /// Chip 主标签。
    ///   - 拿到 codex 套餐用量时优先显示套餐角度的"5h 12% · 周 7%"；
    ///   - 本会话有 token 但还没有套餐用量时显示"套餐用量 12.3k / 1.0M (1%)"；
    ///   - 两者都没有时降级为"套餐用量 · 加载中"，保证 chip 始终有内容。
    public var chipLabel: String {
        if let limits = accountRateLimits {
            return Self.rateLimitsChipLabel(limits)
        }
        if usedTokens > 0 {
            let used = Self.short(usedTokens)
            if let cw = contextWindow, cw > 0 {
                let pct = percent.map { " (\($0)%)" } ?? ""
                return "套餐用量 \(used) / \(Self.short(cw))" + pct
            }
            return "套餐用量 \(used)"
        }
        return "套餐用量 · 加载中"
    }

    /// 详细说明，用于 popover / tooltip。
    ///   - 拿到 codex 套餐用量时列出套餐名、5h / 周两档百分比与重置时间；
    ///   - 本会话有 token 但还没有套餐用量时显示本会话上下文窗口用量；
    ///   - 两者都没有时显示"正在获取模型订阅套餐用量…"，明确是加载态。
    public var detailText: String {
        if let limits = accountRateLimits {
            return Self.rateLimitsDetailText(limits, usedTokens: usedTokens)
        }
        if usedTokens > 0 {
            let used = Self.short(usedTokens)
            if let cw = contextWindow, cw > 0, let pct = percent {
                return "本会话已用 \(used) / \(Self.short(cw)) tokens，约占模型上下文窗口 \(pct)%。"
            }
            return "本会话已用 \(used) tokens。"
        }
        return "正在获取模型订阅套餐用量…"
    }

    // MARK: - Rate-limit label helpers

    /// 把 `accountRateLimits` 渲染成 `套餐 5h 12% · 周 7%` 这种
    /// 紧凑形式。窗口为 5h 时不强制渲染 "5h"，在 chip 已经够紧凑的
    /// 前提下输出 `套餐 · 12% / 周 · 7%`。
    static func rateLimitsChipLabel(_ limits: AccountRateLimits) -> String {
        var parts: [String] = []
        if let p = limits.primary {
            parts.append("\(p.shortLabel) \(p.usedPercent)%")
        }
        if let s = limits.secondary {
            parts.append("\(s.shortLabel) \(s.usedPercent)%")
        }
        if parts.isEmpty {
            return limits.planDisplayName
        }
        return parts.joined(separator: " · ")
    }

    static func rateLimitsDetailText(_ limits: AccountRateLimits, usedTokens: Int) -> String {
        var lines: [String] = [limits.planDisplayName]
        if let p = limits.primary {
            var line = "5h 窗口：\(p.usedPercent)% 已用"
            if let reset = p.resetsInText { line += "，\(reset)重置" }
            lines.append(line)
        }
        if let s = limits.secondary {
            var line = "\(s.shortLabel) 窗口：\(s.usedPercent)% 已用"
            if let reset = s.resetsInText { line += "，\(reset)重置" }
            lines.append(line)
        }
        if usedTokens > 0 {
            lines.append("本会话累计 \(Self.short(usedTokens)) tokens")
        }
        return lines.joined(separator: "\n")
    }

    /// 同一套紧凑格式，与 `tapgoFormatCount` / `TokenUsage.short` 对齐。
    private static func short(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fk", Double(n) / 1_000) }
        return "\(n)"
    }
}

public extension SubscriptionUsage {
    /// 从一组 turn + 最近一次的 `TokenUsage` + codex 套餐用量
    /// 聚合得到当前会话的订阅用量快照。`contextWindow` 优先取
    /// 最近一次 turn 报告的窗口；缺省时回落到 `fallbackWindow`。
    static func from(
        turnsTotalTokens: Int,
        latestUsage: TokenUsage?,
        fallbackWindow: Int?,
        accountRateLimits: AccountRateLimits? = nil
    ) -> SubscriptionUsage {
        let cw = latestUsage?.contextWindow ?? fallbackWindow
        return SubscriptionUsage(
            usedTokens: turnsTotalTokens,
            contextWindow: cw,
            accountRateLimits: accountRateLimits
        )
    }
}
