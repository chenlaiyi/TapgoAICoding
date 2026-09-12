import Foundation
import TapgoCore

@MainActor
func runEvolutionMetrics(_ t: TestRunner) {
    let records = [
        TapgoCore.EvolutionRecordEntry(version: "0.5.1", date: "2026-09-01", testStatus: "— 100 passed, 0 failed —"),
        TapgoCore.EvolutionRecordEntry(version: "0.5.2", date: "2026-09-02", testStatus: "— 200 passed, 0 failed —"),
        TapgoCore.EvolutionRecordEntry(version: "0.5.3", date: "2026-09-03", testStatus: "— 300 passed, 0 failed —")
    ]
    let history = [
        TapgoCore.EvolutionHistoryEntry(version: "0.5.1", status: "published", builtAt: "2026-09-01T00:00:00Z", testStatus: "— 100 passed, 0 failed —", healthCheck: "passed", worktreeVerified: "yes", benchmarkScore: 100),
        TapgoCore.EvolutionHistoryEntry(version: "0.5.2", status: "committed", builtAt: "2026-09-02T00:00:00Z", testStatus: "— 200 passed, 0 failed —"),
        TapgoCore.EvolutionHistoryEntry(version: "0.5.2", status: "release_failed", builtAt: "2026-09-02T01:00:00Z", testStatus: "— 200 passed, 0 failed —"),
        TapgoCore.EvolutionHistoryEntry(version: "0.5.3", status: "published", builtAt: "2026-09-03T01:00:00Z", testStatus: "— 300 passed, 0 failed —", healthCheck: "passed", worktreeVerified: "yes")
    ]
    let backlog = "- [x] done\n- [ ] open\n"
    let testRuns = [
        TapgoCore.EvolutionTestRunEntry(status: "fail", failedSections: ["Parser section"], reruns: [("Parser section", true)], environmentFailures: 1, realFailures: 1)
    ]
    let snapshot = TapgoCore.EvolutionMetrics.compute(records: records, history: history, backlogText: backlog, testRuns: testRuns)
    t.expectEqual(snapshot.recordCount, 3, "metrics: record count")
    t.expectEqual(snapshot.iterationCount, 3, "metrics: unique versions")
    t.expectEqual(snapshot.publishedCount, 2, "metrics: published count")
    t.expectEqual(snapshot.failedCount, 1, "metrics: failed count")
    t.expectEqual(snapshot.successRate.map { abs($0 - 2.0 / 3.0) < 0.0001 } ?? false, true,
                  "metrics: success rate")
    t.expectEqual(snapshot.testPassedTotal, 600, "metrics: test passed total")
    t.expectEqual(snapshot.cycleDurations.count, 1, "metrics: cycle duration count")
    t.expectEqual(snapshot.medianCycleSeconds.map { abs($0 - 176400) < 1 } ?? false, true,
                  "metrics: median cycle")
    t.expectEqual(snapshot.openBacklog, 1, "metrics: open backlog")
    t.expectEqual(snapshot.doneBacklog, 1, "metrics: done backlog")
    t.expectEqual(snapshot.healthPassedCount, 2, "metrics: health passed")
    t.expectEqual(snapshot.worktreePassedCount, 2, "metrics: worktree passed")
    t.expectEqual(snapshot.testRunCount, 1, "metrics: test run count")
    t.expectEqual(snapshot.lastTestStatus, "fail", "metrics: last test status")
    t.expectEqual(snapshot.flakySections, ["Parser section"], "metrics: flaky sections")
    t.expectEqual(snapshot.environmentFailureCount, 1, "metrics: environment failures")
    t.expectEqual(snapshot.realFailureCount, 1, "metrics: real failures")
    t.expectEqual(snapshot.failureReasons["release_failed"], 1, "metrics: failure reasons")
    t.expectEqual(snapshot.cyclePoints.count, 1, "metrics: cycle points")
    t.expectEqual(snapshot.lastBenchmarkScore, 100, "metrics: benchmark score")
    t.expectEqual(!snapshot.iterations.isEmpty, true, "metrics: iteration timeline")

    let parsedHistory = TapgoCore.EvolutionMetrics.parseHistory(
        "{\"version\":\"0.5.1\",\"status\":\"published\",\"builtAt\":\"2026-09-01T00:00:00Z\"}\nnot-json\n"
    )
    t.expectEqual(parsedHistory.count, 1, "metrics: JSONL parser skips invalid lines")

    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-metrics-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let versions = tmp.appendingPathComponent("evolution/versions", isDirectory: true)
    let state = tmp.appendingPathComponent("state", isDirectory: true)
    try? FileManager.default.createDirectory(at: versions, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
    try? "{\"version\":\"0.5.1\",\"date\":\"2026-09-01\",\"testStatus\":\"— 50 passed, 0 failed —\"}".write(
        to: versions.appendingPathComponent("v0.5.1.json"), atomically: true, encoding: .utf8)
    try? "{\"version\":\"0.5.1\",\"status\":\"published\",\"builtAt\":\"2026-09-01T00:00:00Z\",\"testStatus\":\"— 50 passed, 0 failed —\",\"healthCheck\":\"passed\",\"worktreeVerified\":\"yes\"}\n".write(
        to: state.appendingPathComponent("evolution_state_history.jsonl"), atomically: true, encoding: .utf8)
    try? "{\"status\":\"fail\",\"failedSections\":[{\"section\":\"P\"}],\"reruns\":[{\"section\":\"P\",\"passed\":true}],\"environmentFailures\":0,\"realFailures\":1}\n".write(
        to: state.appendingPathComponent("test_run_history.jsonl"), atomically: true, encoding: .utf8)
    try? "{\"score\":50}\n{\"score\":80}\n".write(
        to: state.appendingPathComponent("model_eval_history.jsonl"), atomically: true, encoding: .utf8)
    try? "{\"tag\":\"v0.5.1\",\"passed\":true}\n".write(
        to: state.appendingPathComponent("rollback_drill_history.jsonl"), atomically: true, encoding: .utf8)
    try? "{\"status\":\"ok\",\"ranAt\":\"2026-09-01T10:00:00Z\"}\n{\"status\":\"failed\",\"ranAt\":\"2026-09-02T10:00:00Z\"}\n".write(
        to: state.appendingPathComponent("maintenance_history.jsonl"), atomically: true, encoding: .utf8)
    try? "- [ ] load test\n".write(to: tmp.appendingPathComponent("evolution/BACKLOG.md"), atomically: true, encoding: .utf8)
    let loaded = TapgoCore.EvolutionMetrics.load(projectRoot: tmp, stateDirectory: state)
    t.expectEqual(loaded.recordCount, 1, "metrics: load record count")
    t.expectEqual(loaded.publishedCount, 1, "metrics: load published")
    t.expectEqual(loaded.openBacklog, 1, "metrics: load backlog")
    t.expectEqual(loaded.healthPassedCount, 1, "metrics: load health")
    t.expectEqual(loaded.flakySections, ["P"], "metrics: load flaky")
    t.expectEqual(loaded.modelEvalRuns, 2, "metrics: load model eval runs")
    t.expectEqual(loaded.modelEvalLatestScore, 80, "metrics: load model eval latest")
    t.expectEqual(loaded.modelEvalBestScore, 80, "metrics: load model eval best")
    t.expectEqual(loaded.rollbackDrillRuns, 1, "metrics: load rollback drill runs")
    t.expectEqual(loaded.lastRollbackDrillTag, "v0.5.1", "metrics: load rollback drill tag")
    t.expectEqual(loaded.lastRollbackDrillPassed, true, "metrics: load rollback drill passed")
    t.expectEqual(loaded.maintenanceRuns, 2, "metrics: load maintenance runs")
    t.expectEqual(loaded.lastMaintenanceStatus, "failed", "metrics: load maintenance status")
    t.expectEqual(loaded.lastMaintenanceAt, "2026-09-02T10:00:00Z", "metrics: load maintenance timestamp")
}
