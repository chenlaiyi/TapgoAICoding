// TapgoTests/SubscriptionUsageTests.swift
import Foundation
@testable import TapgoCore

@MainActor
func runSubscriptionUsage(_ t: TestRunner) {
    // 空数据仍保留稳定的加载态，避免 chip 在请求前后跳动。
    let empty = SubscriptionUsage(usedTokens: 0, contextWindow: 1_000_000)
    t.expect(empty.isVisible, "empty: visible while account limits load")
    t.expectEqual(empty.percent, nil, "empty: percent nil when usedTokens == 0")
    t.expectEqual(empty.level, .normal, "empty: level falls back to normal")
    t.expectEqual(empty.chipLabel, "套餐用量 · 加载中", "empty: chip shows loading label")
    t.expectEqual(empty.detailText, "正在获取模型订阅套餐用量…", "empty: detail explains loading state")

    // Basic percentage math
    let used = 250_000
    let cw = 1_000_000
    let basic = SubscriptionUsage(usedTokens: used, contextWindow: cw)
    t.expectEqual(basic.percent, 25, "basic: 250k / 1M = 25%")
    t.expectEqual(basic.level, .normal, "basic: 25% is normal (<50%)")
    t.expect(basic.isVisible, "basic: visible")
    t.expectEqual(basic.chipLabel, "套餐用量 250k / 1.0M (25%)", "basic: chip label format")
    t.expect(basic.detailText.contains("25%"), "basic: detail mentions percent")

    // warn band: 50% – 79%
    let warn = SubscriptionUsage(usedTokens: 600_000, contextWindow: 1_000_000)
    t.expectEqual(warn.percent, 60, "warn: 600k / 1M = 60%")
    t.expectEqual(warn.level, .warn, "warn: 60% is warn band")
    t.expectEqual(warn.chipLabel, "套餐用量 600k / 1.0M (60%)", "warn: chip label format")

    // critical band: ≥80%
    let crit = SubscriptionUsage(usedTokens: 850_000, contextWindow: 1_000_000)
    t.expectEqual(crit.percent, 85, "critical: 850k / 1M = 85%")
    t.expectEqual(crit.level, .critical, "critical: 85% is critical band")

    // Cap at 100% when over the window
    let over = SubscriptionUsage(usedTokens: 1_500_000, contextWindow: 1_000_000)
    t.expectEqual(over.percent, 100, "over: percent capped at 100")

    // Nil window → no percent, falls back to used-only label
    let noCw = SubscriptionUsage(usedTokens: 12_300, contextWindow: nil)
    t.expectEqual(noCw.percent, nil, "noWindow: percent nil")
    t.expectEqual(noCw.level, .normal, "noWindow: level normal")
    t.expectEqual(noCw.chipLabel, "套餐用量 12k", "noWindow: chip omits /window")
    t.expect(noCw.detailText.contains("12k"), "noWindow: detail still mentions used")

    // Zero window → guard division by zero
    let zeroCw = SubscriptionUsage(usedTokens: 123, contextWindow: 0)
    t.expectEqual(zeroCw.percent, nil, "zeroCw: percent nil when window == 0")
    t.expectEqual(zeroCw.chipLabel, "套餐用量 123", "zeroCw: chip omits /window")

    // Big numbers: 1.5M used / 1.0M window
    let big = SubscriptionUsage(usedTokens: 1_500_000, contextWindow: 1_000_000)
    t.expectEqual(big.chipLabel, "套餐用量 1.5M / 1.0M (100%)", "big: chip uses M suffix for used")

    // Convenience: .from turnsTotalTokens + latestUsage + fallbackWindow
    let usage = TokenUsage(input: 100, output: 50, total: 150, cached: 0,
                           reasoning: 0, contextWindow: 2_000_000)
    let agg = SubscriptionUsage.from(turnsTotalTokens: 12_345,
                                     latestUsage: usage,
                                     fallbackWindow: 1_000_000)
    t.expectEqual(agg.usedTokens, 12_345, "from: usedTokens copied")
    t.expectEqual(agg.contextWindow, 2_000_000, "from: window prefers latestUsage over fallback")

    let noUsage = SubscriptionUsage.from(turnsTotalTokens: 7_777,
                                         latestUsage: nil,
                                         fallbackWindow: 1_000_000)
    t.expectEqual(noUsage.contextWindow, 1_000_000, "from: window falls back when latestUsage nil")
    t.expectEqual(noUsage.percent, 1, "from: 7.7k / 1M = 1% (rounded)")

    // Equality + Hashable
    let a = SubscriptionUsage(usedTokens: 1, contextWindow: 2)
    let b = SubscriptionUsage(usedTokens: 1, contextWindow: 2)
    let c = SubscriptionUsage(usedTokens: 1, contextWindow: 3)
    t.expectEqual(a, b, "eq: same fields equal")
    t.expectNotEqual(a, c, "eq: different window not equal")
    t.expect(a.hashValue == b.hashValue, "hash: same fields same hash")
}
