// TapgoTests/ThreadSummaryTests.swift
import Foundation
import TapgoCore

@MainActor
func runThreadSummary(_ t: TestRunner) {
    let t1 = Turn(id: "a", userInput: "x", status: .completed,
                  startedAt: Date(timeIntervalSince1970: 0), completedAt: Date(timeIntervalSince1970: 10),
                  usage: TokenUsage(total: 100))
    let t2 = Turn(id: "b", userInput: "y", status: .completed,
                  startedAt: Date(timeIntervalSince1970: 0), completedAt: Date(timeIntervalSince1970: 5),
                  usage: TokenUsage(total: 50))
    var th = TapgoCore.Thread(id: "s", title: "sum", createdAt: Date(), updatedAt: Date())
    th.turns = [t1, t2]

    t.expectEqual(th.usageTotal, 150, "usageTotal: sum of totals")
    t.expectEqual(th.durationTotal, TimeInterval(15), "durationTotal: sum")
    t.expectEqual(th.durationTotalText ?? "", "15s", "durationTotalText")

    let e = TapgoCore.Thread(id: "e", title: "e", createdAt: Date(), updatedAt: Date())
    t.expectEqual(e.usageTotal, 0, "usageTotal: empty → 0")
    t.expectNil(e.durationTotalText, "durationTotalText: empty → nil")
}
