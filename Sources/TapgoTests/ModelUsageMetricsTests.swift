// TapgoTests/ModelUsageMetricsTests.swift
import Foundation
@testable import TapgoCore

func runModelUsageMetrics(_ t: TestRunner) {
    // percentOfWindow: 基本比例 + 边界
    t.expectEqual(ModelUsageMetrics.percentOfWindow(500_000, window: 1_000_000), 50, "50% rounded")
    t.expectEqual(ModelUsageMetrics.percentOfWindow(0, window: 1_000_000), 0, "0% on empty")
    t.expectEqual(ModelUsageMetrics.percentOfWindow(1_000_000, window: 1_000_000), 100, "100% on full")
    t.expectEqual(ModelUsageMetrics.percentOfWindow(0, window: 0), 0, "no divide-by-zero on zero window")
    t.expectEqual(ModelUsageMetrics.percentOfWindow(123, window: -1), 0, "no divide-by-zero on negative window")
    t.expectEqual(ModelUsageMetrics.percentOfWindow(1234, window: 3), 41133, "ratio above 100% allowed (over-context)")

    // averageCacheHitPercent: 多 turn 平均
    let turns: [Turn] = [
        Turn(id: "t1", userInput: "", status: .completed, startedAt: Date(), usage: TokenUsage(input: 1000, cached: 200)),
        Turn(id: "t2", userInput: "", status: .completed, startedAt: Date(), usage: TokenUsage(input: 2000, cached: 1000)),
        Turn(id: "t3", userInput: "", status: .completed, startedAt: Date(), usage: TokenUsage(input: 0, cached: 0)),   // 应跳过
        Turn(id: "t4", userInput: "", status: .completed, startedAt: Date(), usage: nil),                            // 应跳过
    ]
    // (200/1000 + 1000/2000) / 2 = (0.2 + 0.5) / 2 = 0.35 → 35%
    t.expectEqual(ModelUsageMetrics.averageCacheHitPercent(turns: turns) ?? -1, 35, "average over multi-turn cached/input")

    // 空 turn 列表 → nil
    t.expectNil(ModelUsageMetrics.averageCacheHitPercent(turns: []), "empty turns → nil")

    // 全部 input == 0 → nil
    let zeroInput: [Turn] = [
        Turn(id: "z1", userInput: "", status: .completed, startedAt: Date(), usage: TokenUsage(input: 0, cached: 0)),
    ]
    t.expectNil(ModelUsageMetrics.averageCacheHitPercent(turns: zeroInput), "all zero input → nil")
}
