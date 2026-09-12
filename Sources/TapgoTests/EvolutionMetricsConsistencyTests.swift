import Foundation
import TapgoCore

/// EVO-052：Python 指标工具与 Swift `EvolutionMetrics` 必须对**同一份 state** 得出相同数字。
///
/// 两套实现各自演进，最容易出现的盲区是「同一个状态集合、不同口径」——上一轮那个
/// 契约形状不一致（扁平键 vs 嵌套键）就是这么漏出去的：单测用自造 fixture，从没和
/// 另一套实现对照过。这里用同一份 fixture 同时跑两边并逐项比对。
@MainActor
func runEvolutionMetricsConsistency(_ t: TestRunner) {
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Sources/TapgoTests
        .deletingLastPathComponent()   // Sources
        .deletingLastPathComponent()   // repo root
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-consistency-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let versions = tmp.appendingPathComponent("evolution/versions", isDirectory: true)
    let state = tmp.appendingPathComponent("state", isDirectory: true)
    try? FileManager.default.createDirectory(at: versions, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)

    func write(_ text: String, _ url: URL) {
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    write("{\"version\":\"0.5.1\",\"date\":\"2026-09-01\",\"testStatus\":\"— 100 passed, 0 failed —\"}",
          versions.appendingPathComponent("v0.5.1.json"))
    write("{\"version\":\"0.5.2\",\"date\":\"2026-09-02\",\"testStatus\":\"pending\"}",
          versions.appendingPathComponent("v0.5.2.json"))
    write("{\"version\":\"0.5.3\",\"date\":\"2026-09-03\",\"testStatus\":\"— 300 passed, 0 failed —\"}",
          versions.appendingPathComponent("v0.5.3.json"))
    write("- [x] done\n- [ ] open\n", tmp.appendingPathComponent("evolution/BACKLOG.md"))
    // 含 canary_failed（两边失败集合必须一致）+ 一次失败后恢复（MTTR）
    write("""
    {"version":"0.5.1","status":"published","builtAt":"2026-09-01T00:00:00Z","testStatus":"— 100 passed, 0 failed —","healthCheck":"passed","worktreeVerified":"yes","durationSeconds":600,"tokens":1000,"costUSD":0.5}
    {"version":"0.5.2","status":"committed","builtAt":"2026-09-02T00:00:00Z"}
    {"version":"0.5.2","status":"canary_failed","builtAt":"2026-09-02T01:00:00Z","durationSeconds":300,"tokens":500,"costUSD":0.25}
    {"version":"0.5.3","status":"published","builtAt":"2026-09-03T01:00:00Z","testStatus":"— 300 passed, 0 failed —","healthCheck":"passed","worktreeVerified":"yes","durationSeconds":900,"tokens":2000,"costUSD":1.5}
    """, state.appendingPathComponent("evolution_state_history.jsonl"))
    write("{\"status\":\"pass\",\"ranAt\":\"2026-09-03T01:00:00Z\",\"version\":\"0.5.3\"}\n",
          state.appendingPathComponent("test_run_history.jsonl"))
    write("{\"tag\":\"v0.5.1\",\"passed\":true,\"ranAt\":\"2026-09-03T02:00:00Z\",\"fullBuild\":true}\n",
          state.appendingPathComponent("rollback_drill_history.jsonl"))
    write("{\"status\":\"ok\",\"ranAt\":\"2026-09-03T03:00:00Z\"}\n",
          state.appendingPathComponent("maintenance_history.jsonl"))
    write("""
    {"schemaVersion":1,"generatedAt":"2026-09-03T04:00:00Z","drafts":{"total":2,"open":1,"promoted":1,"staleOverDays":0},
     "registered":{"total":6,"shipped":6,"unshipped":0,"staleOverDays":0},
     "conversion":{"draftToRegistered":0.5,"registeredToShipped":1.0,"draftToShipped":0.5},
     "waitsDays":{"registeredToShippedMedian":7.0,"registeredToShippedSamples":3},
     "backfilledShipped":0,"unknownTimingShipped":0,"staleDays":30}
    """, state.appendingPathComponent("feedback_funnel.json"))

    let swiftSnapshot = TapgoCore.EvolutionMetrics.load(projectRoot: tmp, stateDirectory: state)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
        "python3", repoRoot.appendingPathComponent("scripts/evolution-metrics.py").path,
        "--root", tmp.path,
        "--history", state.appendingPathComponent("evolution_state_history.jsonl").path,
        "--json",
    ]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
    } catch {
        t.expect(false, "consistency: 无法启动 python3 — \(error.localizedDescription)")
        return
    }
    process.waitUntilExit()
    t.expectEqual(process.terminationStatus, 0, "consistency: python 指标退出码 0")

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let py = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        t.expect(false, "consistency: 无法解析 python JSON")
        return
    }
    func pyInt(_ key: String) -> Int? { (py[key] as? NSNumber)?.intValue }
    func pyDouble(_ key: String) -> Double? { (py[key] as? NSNumber)?.doubleValue }
    func close(_ lhs: Double?, _ rhs: Double?, _ tolerance: Double = 0.005) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (a?, b?): return abs(a - b) <= tolerance
        default: return false
        }
    }

    t.expectEqual(swiftSnapshot.iterationCount, pyInt("iterations") ?? -1, "consistency: iterations")
    t.expectEqual(swiftSnapshot.publishedCount, pyInt("published") ?? -1, "consistency: published")
    t.expectEqual(swiftSnapshot.failedCount, pyInt("failed") ?? -1, "consistency: failed（含 canary_failed）")
    t.expect(close(swiftSnapshot.successRate, pyDouble("successRate")), "consistency: successRate")
    t.expect(close(swiftSnapshot.medianCycleSeconds, pyDouble("medianCycleSeconds")), "consistency: median cycle")
    t.expect(close(swiftSnapshot.p95CycleSeconds, pyDouble("p95CycleSeconds")), "consistency: p95 cycle")
    t.expect(close(swiftSnapshot.mttrMedianSeconds, pyDouble("mttrMedianSeconds")), "consistency: mttr")
    t.expectEqual(swiftSnapshot.mttrSampleCount, pyInt("mttrSamples") ?? -1, "consistency: mttr samples")
    t.expectEqual(swiftSnapshot.unrecoveredFailureCount, pyInt("unrecoveredFailures") ?? -1, "consistency: unrecovered")
    t.expect(close(swiftSnapshot.runDurationMedianSeconds, pyDouble("runDurationMedianSeconds")), "consistency: run duration")
    t.expectEqual(swiftSnapshot.runTokensTotal, pyInt("runTokensTotal"), "consistency: tokens total")
    t.expect(close(swiftSnapshot.runCostUSDTotal, pyDouble("runCostUSDTotal")), "consistency: cost total")
    t.expectEqual(swiftSnapshot.rollbackDrillRuns, pyInt("rollbackDrillRuns") ?? -1, "consistency: rollback drill runs")
    t.expectEqual(swiftSnapshot.maintenanceRuns, pyInt("maintenanceRuns") ?? -1, "consistency: maintenance runs")
    t.expectEqual(swiftSnapshot.openBacklog, pyInt("openBacklog") ?? -1, "consistency: open backlog")
    t.expectEqual(swiftSnapshot.doneBacklog, pyInt("doneBacklog") ?? -1, "consistency: done backlog")
}
