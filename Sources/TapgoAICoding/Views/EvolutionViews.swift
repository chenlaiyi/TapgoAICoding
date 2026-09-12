import SwiftUI
import TapgoCore

/// 自进化进度条（面板与离屏 UI 回归共用）。
struct EvolutionProgressStrip: View {
    let progress: TapgoCore.EvolutionProgress
    var isRunning: Bool
    var onStop: () -> Void = {}

    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                ProgressView(value: progress.progressFraction)
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .frame(maxWidth: 220)
                Text("\(progress.phaseIndex)/\(progress.phaseCount) \(progress.phaseLabel)")
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier).weight(.semibold))
                    .foregroundStyle(tint)
                if progress.isStale {
                    Text("可能已中断")
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .foregroundStyle(.orange)
                }
                Spacer()
                if isRunning || progress.isActive {
                    Button(action: onStop) {
                        Label("停止", systemImage: "stop.fill")
                    }
                    .controlSize(.mini)
                    .tint(.red)
                    .help("请求停止本轮自进化；脚本会在阶段边界回滚未提交改动")
                }
            }
            if let message = progress.message, !message.isEmpty {
                Text(message)
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var tint: Color {
        switch progress.status {
        case "failed": return .red
        case "stopped": return .orange
        case "done": return .green
        default: return DSHTheme.brand
        }
    }
}

/// 自进化指标条（日志页与离屏 UI 回归共用）。
struct EvolutionMetricsStrip: View {
    let metrics: TapgoCore.EvolutionMetricsSnapshot

    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            stat("成功率", rateText)
            stat("迭代", "\(metrics.iterationCount)")
            stat("失败", "\(metrics.failedCount)")
            stat("中位周期", cycleText)
            stat("Backlog", "\(metrics.openBacklog) open / \(metrics.doneBacklog) done")
            Spacer(minLength: 8)
            cycleTrend
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(DSHTheme.brand)
        }
    }

    private var rateText: String {
        guard let rate = metrics.successRate else { return "—" }
        return String(format: "%.0f%%", rate * 100)
    }

    private var cycleText: String {
        guard let seconds = metrics.medianCycleSeconds else { return "—" }
        if seconds >= 3600 { return String(format: "%.1fh", seconds / 3600) }
        return String(format: "%.0fm", seconds / 60)
    }

    @ViewBuilder
    private var cycleTrend: some View {
        let recent = Array(metrics.cycleDurations.suffix(10))
        let peak = max(recent.max() ?? 1, 1)
        VStack(alignment: .trailing, spacing: 2) {
            if recent.isEmpty {
                Text("—")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(height: 22, alignment: .bottom)
            } else {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(recent.enumerated()), id: \.offset) { _, duration in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(DSHTheme.brand.opacity(0.55))
                            .frame(width: 4, height: max(3, 20 * duration / peak))
                    }
                }
                .frame(height: 22, alignment: .bottom)
            }
            Text("周期趋势")
                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                .foregroundStyle(.tertiary)
        }
    }
}

/// diff 摘要卡（diff sheet 与离屏 UI 回归共用）。
struct EvolutionDiffSummaryCard: View {
    let range: String
    let commit: String
    let stat: String

    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(DSHTheme.brand)
                Text(range)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(DSHTheme.brand)
                Spacer()
            }
            if !commit.isEmpty {
                Text(commit)
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !stat.isEmpty {
                Text(stat)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(8)
        .background(DSHTheme.bgLayer1, in: RoundedRectangle(cornerRadius: 6))
    }
}
