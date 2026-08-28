import Foundation

/// 一档"限速窗口"快照，对应 codex app-server
/// `account/rateLimits/read` 返回中的 `primary` 与 `secondary`。
/// `usedPercent` 由 codex 给出（已经过它的内部计算），UI 不用
/// 自行换算"已用 / 限额"。
public struct RateLimitWindow: Hashable, Equatable, Codable {
    public var usedPercent: Int
    public var windowMinutes: Int
    public var resetsAt: Date?

    public init(usedPercent: Int, windowMinutes: Int, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }

    /// 解析 codex `RateLimit` JSON；缺失必要字段时返回 nil。
    /// 字段名采用 snake_case（与 codex 当前协议保持一致）。
    public static func fromJSON(_ value: JSONValue?) -> RateLimitWindow? {
        guard let obj = value?.objectValue else { return nil }
        let usedPercent = obj["usedPercent"]?.intOrBoolAsInt
            ?? obj["used_percent"]?.intOrBoolAsInt
        guard let usedPercent else { return nil }
        let windowMinutes = obj["windowDurationMins"]?.intOrBoolAsInt
            ?? obj["window_duration_mins"]?.intOrBoolAsInt
            ?? 0
        let resetsAt: Date? = {
            if let secs = obj["resetsAt"]?.intOrBoolAsInt {
                return Date(timeIntervalSince1970: TimeInterval(secs))
            }
            if let secs = obj["resets_at"]?.intOrBoolAsInt {
                return Date(timeIntervalSince1970: TimeInterval(secs))
            }
            return nil
        }()
        return RateLimitWindow(
            usedPercent: max(0, min(100, usedPercent)),
            windowMinutes: windowMinutes,
            resetsAt: resetsAt
        )
    }

    /// 把窗口长度渲染成 `5h` / `周` / `2d` 等短标签，方便 chip 用。
    public var shortLabel: String {
        let mins = windowMinutes
        if mins <= 0 { return "窗口" }
        if mins % (60 * 24 * 7) == 0 {
            let weeks = mins / (60 * 24 * 7)
            return weeks == 1 ? "周" : "\(weeks)周"
        }
        if mins % (60 * 24) == 0 {
            let days = mins / (60 * 24)
            return days == 1 ? "天" : "\(days)天"
        }
        if mins % 60 == 0 {
            return "\(mins / 60)h"
        }
        return "\(mins)m"
    }

    /// 把 `resetsAt` 渲染成"X 分钟 / Y 小时 / 周一 12:34"等短描述。
    /// 过去时刻返回 "已到"。
    public var resetsInText: String? {
        guard let resetsAt else { return nil }
        let delta = resetsAt.timeIntervalSinceNow
        if delta <= 0 { return "已到" }
        let mins = Int(delta / 60)
        if mins < 1 { return "<1 分钟后" }
        if mins < 60 { return "\(mins) 分钟后" }
        let hours = mins / 60
        if hours < 24 { return "\(hours) 小时后" }
        let days = hours / 24
        if days < 7 { return "\(days) 天后" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M-d HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: resetsAt)
    }

    /// 与 `TokenUsage.contextLevel` 同源的压力等级，便于沿用现有
    /// 配色板：50–79% → warn，≥80% → critical。
    public var level: ContextLevel {
        if usedPercent >= 80 { return .critical }
        if usedPercent >= 50 { return .warn }
        return .normal
    }
}

/// `account/rateLimits/read` 的整体响应，对应 codex `RateLimits`。
/// `primary` 是 5 hour 窗口，`secondary` 通常是周窗口；可能只有一档。
public struct AccountRateLimits: Hashable, Equatable, Codable {
    public var primary: RateLimitWindow?
    public var secondary: RateLimitWindow?
    public var planType: String?

    public init(primary: RateLimitWindow?, secondary: RateLimitWindow?, planType: String?) {
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
    }

    public static func fromJSON(_ value: JSONValue?) -> AccountRateLimits? {
        // codex 把 rateLimits 放在 `result.rateLimits`；上游的
        // `account/rateLimits/updated` 通知则直接在 `params.rateLimits`。
        let obj = value?.objectValue?["rateLimits"]?.objectValue ?? value?.objectValue
        guard let obj else { return nil }
        let primary = RateLimitWindow.fromJSON(obj["primary"])
        let secondary = RateLimitWindow.fromJSON(obj["secondary"])
        let planType = obj["planType"]?.stringValue ?? obj["plan_type"]?.stringValue
        // 没有 primary/secondary 至少要有 planType 才算有效响应。
        guard primary != nil || secondary != nil || planType != nil else { return nil }
        return AccountRateLimits(primary: primary, secondary: secondary, planType: planType)
    }

    /// 两档中压力最高的等级；当只有一档时取那一档；都没有时返回 nil。
    public var level: ContextLevel? {
        let levels: [ContextLevel] = [primary?.level, secondary?.level].compactMap { $0 }
        guard !levels.isEmpty else { return nil }
        if levels.contains(.critical) { return .critical }
        if levels.contains(.warn) { return .warn }
        return .normal
    }

    /// 套餐名简称，例如 `Plus 套餐`、`Pro 套餐`、`MiniMax ultra` 等；
    /// 缺失时回落到 `套餐`。
    public var planDisplayName: String {
        guard let planType, !planType.isEmpty else { return "套餐" }
        // codex 现在返回的是 free / plus / pro / team / enterprise / edu 等；
        // 第三方中转（MiniMax ultra）可能直接是订阅名，原样展示即可。
        switch planType.lowercased() {
        case "free": return "免费套餐"
        case "plus": return "Plus 套餐"
        case "pro": return "Pro 套餐"
        case "team": return "Team 套餐"
        case "enterprise": return "企业套餐"
        case "edu": return "教育套餐"
        default: return planType
        }
    }
}
