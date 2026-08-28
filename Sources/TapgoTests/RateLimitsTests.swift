// TapgoTests/RateLimitsTests.swift
import Foundation
@testable import TapgoCore

@MainActor
private func parseJSON(_ text: String) -> JSONValue? {
    let data = text.data(using: .utf8) ?? Data()
    return try? JSONDecoder().decode(JSONValue.self, from: data)
}

@MainActor
func runRateLimits(_ t: TestRunner) {
    // 1) 完整 5h + 周两档解析
    let json = """
    {
      "rateLimits": {
        "primary": {
          "usedPercent": 12,
          "windowDurationMins": 300,
          "resetsAt": 1773879554
        },
        "secondary": {
          "usedPercent": 7,
          "windowDurationMins": 10080,
          "resetsAt": 1774000000
        },
        "planType": "plus"
      }
    }
    """
    let parsed = AccountRateLimits.fromJSON(parseJSON(json))
    t.expectNotNil(parsed, "primary+secondary: parses result.rateLimits")
    t.expectEqual(parsed?.planType, "plus", "planType extracted")
    t.expectEqual(parsed?.primary?.usedPercent, 12, "primary percent")
    t.expectEqual(parsed?.primary?.windowMinutes, 300, "primary window 5h")
    t.expectEqual(parsed?.secondary?.usedPercent, 7, "secondary percent")
    t.expectEqual(parsed?.secondary?.windowMinutes, 10080, "secondary window = 7d")
    t.expectNotNil(parsed?.primary?.resetsAt, "primary resetsAt parsed")
    t.expectNotNil(parsed?.secondary?.resetsAt, "secondary resetsAt parsed")

    // 2) 通知格式：直接传 rateLimits 对象
    let notify = """
    {
      "primary": {"usedPercent": 50, "windowDurationMins": 300, "resetsAt": 1773879554},
      "secondary": {"usedPercent": 90, "windowDurationMins": 10080, "resetsAt": 1774000000},
      "planType": "pro"
    }
    """
    let notifyParsed = AccountRateLimits.fromJSON(parseJSON(notify))
    t.expectNotNil(notifyParsed, "notification: parses bare rateLimits object")
    t.expectEqual(notifyParsed?.planType, "pro", "notification planType")
    t.expectEqual(notifyParsed?.primary?.level, .warn, "primary 50% → warn")
    t.expectEqual(notifyParsed?.secondary?.level, .critical, "secondary 90% → critical")

    // 3) level 取两档最高
    t.expectEqual(notifyParsed?.level, .critical, "level = max of both windows = critical")
    let bothLow = AccountRateLimits(
        primary: RateLimitWindow(usedPercent: 20, windowMinutes: 300, resetsAt: nil),
        secondary: RateLimitWindow(usedPercent: 30, windowMinutes: 10080, resetsAt: nil),
        planType: "plus"
    )
    t.expectEqual(bothLow.level, .normal, "both low → normal")
    let oneWarn = AccountRateLimits(
        primary: RateLimitWindow(usedPercent: 60, windowMinutes: 300, resetsAt: nil),
        secondary: nil,
        planType: "plus"
    )
    t.expectEqual(oneWarn.level, .warn, "only primary warn → warn")

    // 4) 空 / 残缺响应
    let empty = AccountRateLimits.fromJSON(parseJSON("{}"))
    t.expectNil(empty, "empty object → nil")
    let badJSON = AccountRateLimits.fromJSON(parseJSON("{\"rateLimits\":{}}"))
    t.expectNil(badJSON, "empty rateLimits → nil")
    let onlyPlan = AccountRateLimits.fromJSON(parseJSON(
        "{\"rateLimits\":{\"planType\":\"plus\"}}"
    ))
    t.expectNotNil(onlyPlan, "plan-only response is valid")
    t.expectNil(onlyPlan?.level, "plan-only: level nil")

    // 5) percent 字段缺失或越界 → 拒收
    let noPercent = AccountRateLimits.fromJSON(parseJSON(
        "{\"rateLimits\":{\"primary\":{\"windowDurationMins\":300}}}"
    ))
    t.expectNil(noPercent?.primary, "missing usedPercent → primary nil")
    let clamped = AccountRateLimits.fromJSON(parseJSON(
        "{\"rateLimits\":{\"primary\":{\"usedPercent\":150,\"windowDurationMins\":300}}}"
    ))
    t.expectEqual(clamped?.primary?.usedPercent, 100, "over 100 clamped to 100")
    let negative = AccountRateLimits.fromJSON(parseJSON(
        "{\"rateLimits\":{\"primary\":{\"usedPercent\":-10,\"windowDurationMins\":300}}}"
    ))
    t.expectEqual(negative?.primary?.usedPercent, 0, "negative clamped to 0")

    // 6) shortLabel
    t.expectEqual(parsed?.primary?.shortLabel, "5h", "primary 300min → 5h")
    t.expectEqual(parsed?.secondary?.shortLabel, "周", "secondary 10080min → 周")
    let daily = RateLimitWindow(usedPercent: 10, windowMinutes: 60 * 24, resetsAt: nil)
    t.expectEqual(daily.shortLabel, "天", "24h window → 天")
    let odd = RateLimitWindow(usedPercent: 10, windowMinutes: 90, resetsAt: nil)
    t.expectEqual(odd.shortLabel, "90m", "non-round window → minutes")

    // 7) planDisplayName
    t.expectEqual(parsed?.planDisplayName, "Plus 套餐", "planType plus → Plus 套餐")
    let pro = AccountRateLimits(primary: nil, secondary: nil, planType: "Pro")
    t.expectEqual(pro.planDisplayName, "Pro 套餐", "case-insensitive pro")
    let thirdParty = AccountRateLimits(primary: nil, secondary: nil, planType: "MiniMax ultra")
    t.expectEqual(thirdParty.planDisplayName, "MiniMax ultra", "third-party planType as-is")
    let none = AccountRateLimits(primary: nil, secondary: nil, planType: nil)
    t.expectEqual(none.planDisplayName, "套餐", "missing planType → 套餐")
}

@MainActor
func runSubscriptionUsageWithRateLimits(_ t: TestRunner) {
    let now = Int(Date().timeIntervalSince1970)
    let plusWindow = AccountRateLimits(
        primary: RateLimitWindow(
            usedPercent: 60,
            windowMinutes: 300,
            resetsAt: Date(timeIntervalSince1970: TimeInterval(now + 1800))
        ),
        secondary: RateLimitWindow(
            usedPercent: 7,
            windowMinutes: 10080,
            resetsAt: Date(timeIntervalSince1970: TimeInterval(now + 86400))
        ),
        planType: "plus"
    )

    // 拿到 rate limits 后，chip label 走套餐角度而不是上下文窗口。
    let usage = SubscriptionUsage(
        usedTokens: 12_000,
        contextWindow: 1_000_000,
        accountRateLimits: plusWindow
    )
    t.expect(usage.isVisible, "with rate limits, chip is visible regardless of usedTokens")
    t.expectEqual(usage.chipLabel, "5h 60% · 周 7%", "chipLabel shows primary+secondary")
    t.expectEqual(usage.level, .warn, "level follows max(primary, secondary) = warn")
    t.expect(usage.detailText.contains("Plus 套餐"), "detailText shows plan name")
    t.expect(usage.detailText.contains("5h 窗口"), "detailText shows 5h window")
    t.expect(usage.detailText.contains("周 窗口"), "detailText shows 周 window")
    t.expect(usage.detailText.contains("重置"), "detailText mentions resets")

    // 即使本会话 token 很大、上下文满到 99%，只要 rate limits 都正常，
    // chip 颜色也由 rate limits 决定。
    let heavy = SubscriptionUsage(
        usedTokens: 990_000,
        contextWindow: 1_000_000,
        accountRateLimits: plusWindow
    )
    t.expectEqual(heavy.percent, 99, "context usage heavy")
    t.expectEqual(heavy.level, .warn, "rate limits override context percent")

    // 没拿到 rate limits 且没有 token 时保留稳定的加载态，避免
    // 新会话输入区右下角的套餐 chip 忽隐忽现。
    let legacy = SubscriptionUsage(usedTokens: 0, contextWindow: 1_000_000)
    t.expect(legacy.isVisible, "no rate limits + no tokens → visible loading state")
    t.expectEqual(legacy.chipLabel, "套餐用量 · 加载中", "empty usage shows loading label")
    t.expectEqual(legacy.detailText, "正在获取模型订阅套餐用量…", "empty usage explains loading state")

    // 已有 token 时仍回落到 v0.5.6 的本会话估算语义。
    let legacyVisible = SubscriptionUsage(usedTokens: 12_300, contextWindow: 1_000_000)
    t.expectEqual(legacyVisible.chipLabel, "套餐用量 12k / 1.0M (1%)", "no rate limits → v0.5.6 label")

    // .from 兼容旧调用（不传 rate limits）
    let legacyAgg = SubscriptionUsage.from(
        turnsTotalTokens: 5_000,
        latestUsage: nil,
        fallbackWindow: 1_000_000
    )
    t.expectNil(legacyAgg.accountRateLimits, "legacy .from leaves rate limits nil")

    // .from 把 rate limits 透传
    let newAgg = SubscriptionUsage.from(
        turnsTotalTokens: 5_000,
        latestUsage: nil,
        fallbackWindow: 1_000_000,
        accountRateLimits: plusWindow
    )
    t.expectEqual(newAgg.accountRateLimits?.planType, "plus", ".from passes rate limits")
    t.expectEqual(newAgg.level, .warn, ".from level uses rate limits")
}


@MainActor
func runSubscriptionUsageAlwaysVisible(_ t: TestRunner) {
    // v0.5.9+：保证 chip 永远渲染，缺数据时降级为"加载中"。
    // 这是修"用户进入新会话看到输入框下方右侧啥都没有"的根因。

    // 1. 完全无数据：仅构造默认 init
    let brandNew = SubscriptionUsage(usedTokens: 0, contextWindow: nil)
    t.expect(brandNew.isVisible, "alwaysVisible: brand-new (no tokens, no cw) → visible")
    t.expectEqual(brandNew.chipLabel, "套餐用量 · 加载中", "alwaysVisible: brand-new → loading chip")
    t.expectEqual(brandNew.detailText, "正在获取模型订阅套餐用量…", "alwaysVisible: brand-new → loading detail")
    t.expectEqual(brandNew.level, .normal, "alwaysVisible: brand-new level stays normal")

    // 2. 有 contextWindow 但没有 token：仍然显示加载中
    let onlyWindow = SubscriptionUsage(usedTokens: 0, contextWindow: 1_000_000)
    t.expect(onlyWindow.isVisible, "alwaysVisible: only window → visible")
    t.expectEqual(onlyWindow.chipLabel, "套餐用量 · 加载中", "alwaysVisible: only window → loading chip")

    // 3. 有 token 但没有 codex 套餐用量 + 没有上下文窗口 → 走"本会话 fallback"
    let onlyTokens = SubscriptionUsage(usedTokens: 12_300, contextWindow: nil)
    t.expect(onlyTokens.isVisible, "alwaysVisible: only tokens → visible")
    t.expectEqual(onlyTokens.chipLabel, "套餐用量 12k", "alwaysVisible: only tokens → session-only chip")
    t.expectEqual(onlyTokens.detailText, "本会话已用 12k tokens。", "alwaysVisible: only tokens → session-only detail")

    // 4. 拿到 codex 套餐用量：可见且走套餐角度
    let primary = RateLimitWindow(usedPercent: 80, windowMinutes: 300, resetsAt: nil)
    let secondary = RateLimitWindow(usedPercent: 7, windowMinutes: 10080, resetsAt: nil)
    let limits = AccountRateLimits(primary: primary, secondary: secondary, planType: "pro")
    let withLimits = SubscriptionUsage(usedTokens: 0, contextWindow: 1_000_000, accountRateLimits: limits)
    t.expect(withLimits.isVisible, "alwaysVisible: with rate limits → visible")
    t.expectEqual(withLimits.chipLabel, "5h 80% · 周 7%", "alwaysVisible: rate-limit label overrides loading")
    t.expectEqual(withLimits.level, .critical, "alwaysVisible: 5h 80% → critical (overrides normal)")
    t.expectEqual(withLimits.detailText.contains("Pro 套餐"), true, "alwaysVisible: detail includes plan name")

    // 5. 5h 80% 单档：critical 触发
    let onlyCritical = AccountRateLimits(
        primary: RateLimitWindow(usedPercent: 80, windowMinutes: 300, resetsAt: nil),
        secondary: nil,
        planType: nil
    )
    let onlyCriticalUsage = SubscriptionUsage(usedTokens: 0, contextWindow: nil, accountRateLimits: onlyCritical)
    t.expectEqual(onlyCriticalUsage.level, .critical, "alwaysVisible: 5h 80% single-window → critical")

    // 6. 周 7% 单档：normal
    let onlyWeekly = AccountRateLimits(
        primary: nil,
        secondary: RateLimitWindow(usedPercent: 7, windowMinutes: 10080, resetsAt: nil),
        planType: "plus"
    )
    let onlyWeeklyUsage = SubscriptionUsage(usedTokens: 0, contextWindow: nil, accountRateLimits: onlyWeekly)
    t.expectEqual(onlyWeeklyUsage.level, .normal, "alwaysVisible: 周 7% single-window → normal")
    t.expectEqual(onlyWeeklyUsage.chipLabel, "周 7%", "alwaysVisible: weekly-only chip label")

    // 7. 5h 60% 单档：warn 触发
    let warnOnly = AccountRateLimits(
        primary: RateLimitWindow(usedPercent: 60, windowMinutes: 300, resetsAt: nil),
        secondary: nil,
        planType: nil
    )
    let warnUsage = SubscriptionUsage(usedTokens: 0, contextWindow: nil, accountRateLimits: warnOnly)
    t.expectEqual(warnUsage.level, .warn, "alwaysVisible: 5h 60% single-window → warn")
}
