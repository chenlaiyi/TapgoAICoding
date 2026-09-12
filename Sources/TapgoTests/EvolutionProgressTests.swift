import Foundation
import TapgoCore

@MainActor
func runEvolutionProgress(_ t: TestRunner) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-progress-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

    let progress = TapgoCore.EvolutionProgress(
        version: "0.5.267", phase: "tests", phaseIndex: 3, phaseCount: 9,
        status: "running", message: "3197 passed",
        iterationBranch: "codex/evolution-v0.5.267",
        startedAt: "2026-09-12T12:00:00Z", updatedAt: "2026-09-12T12:01:00Z"
    )
    let encoded = try? JSONEncoder().encode(progress)
    try? encoded?.write(to: tmp.appendingPathComponent(TapgoCore.EvolutionProgress.progressFileName))
    let loaded = TapgoCore.EvolutionProgress.load(stateDirectory: tmp)
    t.expectEqual(loaded?.version, "0.5.267", "progress: round-trip version")
    t.expectEqual(loaded?.phaseLabel, "全量回归", "progress: phase label")
    t.expectEqual(loaded?.progressFraction ?? 0, 3.0 / 9.0, "progress: fraction")
    t.expectEqual(loaded?.isActive, true, "progress: active")
    t.expectEqual(loaded?.isStale, false, "progress: fresh update is not stale")

    let stale = TapgoCore.EvolutionProgress(
        version: "0.5.267", phase: "build", phaseIndex: 4, phaseCount: 9,
        status: "running", updatedAt: "2020-01-01T00:00:00Z"
    )
    t.expectEqual(stale.isStale, true, "progress: old running marker is stale")

    t.expectEqual(TapgoCore.EvolutionProgress.stopRequested(stateDirectory: tmp), false, "progress: no stop initially")
    try? TapgoCore.EvolutionProgress.requestStop(stateDirectory: tmp)
    t.expectEqual(TapgoCore.EvolutionProgress.stopRequested(stateDirectory: tmp), true, "progress: stop requested")
    TapgoCore.EvolutionProgress.clearStopRequest(stateDirectory: tmp)
    t.expectEqual(TapgoCore.EvolutionProgress.stopRequested(stateDirectory: tmp), false, "progress: stop cleared")
}
