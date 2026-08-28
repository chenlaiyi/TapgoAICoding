import Foundation

/// 当前模型订阅套餐的"使用情况"快照，用于在输入框下方右侧显示
/// "套餐用量"摘要。v0.5.6 阶段由两条本地数据合成：
///
///   - `usedTokens`：当前会话累计 token（`Thread.usageTotal`）
///   - `contextWindow`：模型上下文窗口（来自最近一次 turn 的
///     `TokenUsage.contextWindow`，缺省时回落到 `TapgoConfig.autoCompactTokenLimit` × 2，
///     即 MiniMax-M3 的 1M 上下文窗口）
///
/// 后续接入 `codex account/rateLimits/read` 后，可在此结构上额外
/// 暴露 `rateLimitResetAt` / `remainingRequests` 等字段，UI 不用
/// 改签名。
public struct SubscriptionUsage: Equatable, Hashable {

    /// 已用 token（当前会话累计）。
    public var usedTokens: Int

    /// 模型上下文窗口 token 数；用于计算"已用占比"。
    public var contextWindow: Int?

    /// 构造一个用量快照。
    public init(usedTokens: Int, contextWindow: Int?) {
        self.usedTokens = usedTokens
        self.contextWindow = contextWindow
    }

    /// 上下文已用百分比，0–100；窗口未知或为 0 时返回 nil。
    public var percent: Int? {
        guard let cw = contextWindow, cw > 0, usedTokens > 0 else { return nil }
        let raw = Double(usedTokens) / Double(cw) * 100
        return min(100, max(0, Int(raw.rounded())))
    }

    /// 与 `TokenUsage.contextLevel` 一致的压力等级——UI 可以用同一
    /// 套颜色渲染（绿 → 黄 → 红），避免在 chip 与上下文菜单出现
    /// 两套互不相干的配色。
    public var level: ContextLevel {
        guard let pct = percent else { return .normal }
        if pct >= 80 { return .critical }
        if pct >= 50 { return .warn }
        return .normal
    }

    /// 是否应该显示该 chip：仅当本会话已经有 token 用量。
    /// 单纯知道窗口但还没产生用量时不显示，避免空状态刷屏。
    public var isVisible: Bool {
        usedTokens > 0
    }

    /// Chip 主标签，例如 `套餐用量 12.3k / 1.0M (1%)`。无窗口或无百分比时
    /// 自动省略多余空格。
    public var chipLabel: String {
        let used = Self.short(usedTokens)
        if let cw = contextWindow, cw > 0 {
            let pct = percent.map { " (\($0)%)" } ?? ""
            return "套餐用量 \(used) / \(Self.short(cw))" + pct
        }
        return "套餐用量 \(used)"
    }

    /// 详细说明，用于 popover / tooltip。
    public var detailText: String {
        guard isVisible else { return "暂无用量数据" }
        let used = Self.short(usedTokens)
        if let cw = contextWindow, cw > 0, let pct = percent {
            return "本会话已用 \(used) / \(Self.short(cw)) tokens，约占模型上下文窗口 \(pct)%。"
        }
        return "本会话已用 \(used) tokens。"
    }

    /// 同一套紧凑格式，与 `tapgoFormatCount` / `TokenUsage.short` 对齐。
    private static func short(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fk", Double(n) / 1_000) }
        return "\(n)"
    }
}

public extension SubscriptionUsage {
    /// 从一组 turn + 最近一次的 `TokenUsage` 聚合得到当前会话的
    /// 订阅用量快照。`contextWindow` 优先取最近一次 turn 报告
    /// 的窗口；缺省时回落到 `fallbackWindow`（典型为 1M）。
    static func from(
        turnsTotalTokens: Int,
        latestUsage: TokenUsage?,
        fallbackWindow: Int?
    ) -> SubscriptionUsage {
        let cw = latestUsage?.contextWindow ?? fallbackWindow
        return SubscriptionUsage(usedTokens: turnsTotalTokens, contextWindow: cw)
    }
}
