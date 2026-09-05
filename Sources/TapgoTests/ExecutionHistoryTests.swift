import Foundation
import TapgoCore

func runExecutionHistoryTests(_ t: TestRunner) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-exechistory-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = ScheduledTaskStore(baseDir: tmp)

    // Build a task without executionHistory — should decode fine (legacy compat).
    let task = ScheduledTask(
        name: "晨会",
        prompt: "今天的 diff",
        schedule: .daily(hour: 9, minute: 0)
    )
    try? store.save(task)

    let reloaded = store.loadAll().first!
    t.expectEqual(reloaded.executionHistory, nil, "legacy task has no executionHistory field on disk")
    t.expectEqual(reloaded.resolvedHistory.count, 0, "resolvedHistory falls back to empty array")

    // Encode ExecutionRecord and round-trip.
    let rec1 = ExecutionRecord(firedAt: Date(timeIntervalSince1970: 1_700_000_000), outcome: .success, durationMs: 142)
    let rec2 = ExecutionRecord(firedAt: Date(timeIntervalSince1970: 1_700_000_100), outcome: .failure, durationMs: 0, errorMessage: "目标会话不存在")
    let rec3 = ExecutionRecord(firedAt: Date(timeIntervalSince1970: 1_700_000_200), outcome: .skipped, durationMs: nil, errorMessage: "inject 未配置")

    var updated = reloaded
    updated.executionHistory = [rec1, rec2, rec3]
    try? store.save(updated)
    let loaded = store.loadAll().first!
    t.expectEqual(loaded.resolvedHistory.count, 3, "three history entries persist")
    t.expectEqual(loaded.resolvedHistory[0].outcome, .success, "first entry is success")
    t.expectEqual(loaded.resolvedHistory[1].outcome, .failure, "second entry is failure")
    t.expectEqual(loaded.resolvedHistory[1].errorMessage, "目标会话不存在", "error message round-trips")
    t.expectEqual(loaded.resolvedHistory[2].outcome, .skipped, "third entry is skipped")

    // Bounded append: pushing beyond 5 should drop the head.
    var capped = updated
    for i in 4...8 {
        capped.executionHistory?.append(ExecutionRecord(
            firedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(i * 10)),
            outcome: .success,
            durationMs: i * 10
        ))
        if let h = capped.executionHistory, h.count > 5 {
            capped.executionHistory = Array(h.suffix(5))
        }
    }
    t.expectEqual(capped.resolvedHistory.count, 5,
                  "history capped at \(5)")
    t.expectEqual(capped.resolvedHistory.first?.durationMs, 40,
                  "oldest entries dropped after cap")
}
