import SwiftUI
import AppKit
import TapgoCore

@main
struct EvolutionPreviewMain {
    @MainActor
    static func main() {
        _ = NSApplication.shared

        let progress = TapgoCore.EvolutionProgress(
            version: "0.5.272",
            phase: "tests",
            phaseIndex: 3,
            phaseCount: 9,
            status: "running",
            message: "— 3229 passed, 0 failed —",
            iterationBranch: "codex/evolution-v0.5.272",
            startedAt: "2026-09-12T12:00:00Z",
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        let metrics = TapgoCore.EvolutionMetricsSnapshot(
            recordCount: 14, iterationCount: 13, publishedCount: 13, failedCount: 0,
            successRate: 1.0, medianCycleSeconds: 420,
            cycleDurations: [300, 420, 380, 500, 450, 410, 390, 470, 430, 460],
            testPassedTotal: 41000, testVersionCount: 13,
            openBacklog: 2, doneBacklog: 16
        )

        let content = VStack(alignment: .leading, spacing: 14) {
            Text("Evolution UI Fixture")
                .font(.system(size: 16, weight: .bold))
            EvolutionProgressStrip(progress: progress, isRunning: true, onStop: {})
            EvolutionMetricsStrip(metrics: metrics)
                .padding(10)
                .background(DSHTheme.bgLayer1, in: RoundedRectangle(cornerRadius: 8))
            EvolutionDiffSummaryCard(
                range: "范围: v0.5.271..v0.5.272",
                commit: "abc1234 feat(evolution): UI 回归自动化",
                stat: " Sources/TapgoAICoding/Views/EvolutionViews.swift | 180 +++++++++++\n 3 files changed, 210 insertions(+), 12 deletions(-)"
            )
            Spacer()
        }
        .padding(20)
        .frame(width: 900, height: 600)
        .background(DSHTheme.bg)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            FileHandle.standardError.write(Data("EVOLUTION UI SNAPSHOT FAILED: renderer produced no image\n".utf8))
            exit(2)
        }
        let out = ProcessInfo.processInfo.environment["TAPGO_EVOLUTION_SNAPSHOT_OUT"]
            ?? "/tmp/tapgo-evolution-ui.png"
        do {
            try png.write(to: URL(fileURLWithPath: out))
        } catch {
            FileHandle.standardError.write(Data("EVOLUTION UI SNAPSHOT FAILED: \(error)\n".utf8))
            exit(3)
        }
        print("EVOLUTION UI SNAPSHOT OK \(out) \(png.count) bytes")
    }
}
