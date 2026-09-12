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

/// 可钻取的指标详情：周期趋势、状态时间线、失败原因、flaky 与 health/worktree 统计。
struct EvolutionMetricsDetailView: View {
    let metrics: TapgoCore.EvolutionMetricsSnapshot

    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自进化指标详情")
                .font(AppFont.scaled(.headline, multiplier: appFontScale.multiplier))
            HStack(spacing: 10) {
                card("成功率", rateText)
                card("published", "\(metrics.publishedCount)")
                card("failed", "\(metrics.failedCount)")
                card("flaky", "\(metrics.flakySections.count)")
                card("test runs", "\(metrics.testRunCount) · \(metrics.lastTestStatus ?? "—")")
                card("health", "\(metrics.healthPassedCount)/\(metrics.healthPassedCount + metrics.healthFailedCount)")
                card("worktree", "\(metrics.worktreePassedCount)/\(metrics.worktreePassedCount + metrics.worktreeFailedCount)")
                card("benchmark", metrics.lastBenchmarkScore.map { "\($0)/100" } ?? "—")
                card("model eval", metrics.modelEvalBestScore.map { String(format: "%.0f/100", $0) } ?? "—")
            }

            Divider()
            sectionTitle("周期趋势")
            cycleChart

            Divider()
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("状态时间线")
                    if metrics.iterations.isEmpty {
                        emptyText("暂无迭代")
                    } else {
                        ForEach(metrics.iterations.reversed(), id: \.version) { point in
                            HStack(spacing: 6) {
                                Circle().fill(statusColor(point.status)).frame(width: 7, height: 7)
                                Text(point.version)
                                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                Text(statusLabel(point.status))
                                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("失败原因")
                    if metrics.failureReasons.isEmpty {
                        emptyText("无失败")
                    } else {
                        ForEach(metrics.failureReasons.sorted { $0.value > $1.value }, id: \.key) { key, value in
                            HStack(spacing: 6) {
                                Text(key)
                                    .font(.system(.caption2, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(value)")
                                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            sectionTitle("Flaky sections")
            if metrics.flakySections.isEmpty {
                emptyText("无 flaky（环境失败 \(metrics.environmentFailureCount) · 真实失败 \(metrics.realFailureCount)）")
            } else {
                ForEach(metrics.flakySections, id: \.self) { section in
                    Text("• \(section)")
                        .font(.system(.caption2, design: .monospaced))
                }
            }
        }
        .padding(16)
    }

    private func card(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(DSHTheme.brand)
        }
        .padding(8)
        .background(DSHTheme.bgLayer1, in: RoundedRectangle(cornerRadius: 6))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier).weight(.semibold))
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
            .foregroundStyle(.tertiary)
    }

    private var rateText: String {
        guard let rate = metrics.successRate else { return "—" }
        return String(format: "%.0f%%", rate * 100)
    }

    private var cycleChart: some View {
        let points = Array(metrics.cyclePoints.suffix(10))
        let peak = max(points.map(\.seconds).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(points, id: \.version) { point in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DSHTheme.brand.opacity(0.65))
                            .frame(width: 14, height: max(4, 36 * point.seconds / peak))
                        Text(shortVersion(point.version))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                if points.isEmpty {
                    emptyText("暂无周期数据")
                }
            }
            .frame(height: 54, alignment: .bottom)
        }
    }

    private func shortVersion(_ version: String) -> String {
        version.split(separator: ".").last.map(String.init) ?? version
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "published", "local_built": return .green
        case "push_failed", "release_failed", "health_failed", "worktree_verify_failed": return .red
        case "committed": return DSHTheme.brand
        default: return .orange
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "published": return "已发布"
        case "local_built": return "本机构建"
        case "committed": return "已提交"
        case "push_failed": return "推送失败"
        case "release_failed": return "发布失败"
        case "health_failed": return "健康检查失败"
        case "worktree_verify_failed": return "worktree 验证失败"
        default: return status
        }
    }
}
