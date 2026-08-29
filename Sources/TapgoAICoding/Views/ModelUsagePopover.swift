import SwiftUI
import TapgoCore

/// Subscription / quota summary popover shown on hover over the circular
/// context meter in the composer footer. Source mapping vs. the reference:
///   * 上下文容量 + 横向进度条  → TokenUsage.contextWindow + contextPercent
///   * 6 行占比                → 用 TokenUsage.input/output/cached/reasoning 4 个
///     维度填充前 4 行;MCP 工具 / 技能当前无拆分量,占位"—"。
///   * 平均缓存命中率           → 由调用方提供
///   * 剩余额度 (5小时/每周/Credits) → codex account/rateLimits/read
///     + account/rateLimits/updated,经 CodexHarnessClient.readRateLimits()
///     拉取,SessionStore.rateLimits 持有,本视图直接渲染。
struct ModelUsagePopover: View {
    let usage: TokenUsage?
    let averageCacheHitPercent: Int?
    let rateLimits: RateLimitsSnapshot?
    let rateLimitsLoading: Bool
    let rateLimitsError: String?
    let appFontScale: AppFontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            contextSection
            Divider().opacity(0.4)
            cacheHitSection
            Divider().opacity(0.4)
            quotaSection
        }
        .padding(16)
        .frame(width: 300)
        .background(DSHTheme.bg)
    }

    @ViewBuilder
    private var contextSection: some View {
        let total = usage?.total ?? 0
        let window = usage?.contextWindow
        let percent = usage?.contextPercent ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("上下文容量")
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                    .foregroundStyle(DSHTheme.label)
                Spacer(minLength: 8)
                if let window {
                    Text("\(tapgoFormatCount(total))/\(tapgoFormatCount(window))（\(percent)%）")
                        .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                        .foregroundStyle(DSHTheme.label)
                } else {
                    Text("—")
                        .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                        .foregroundStyle(DSHTheme.labelDim)
                }
            }
            if let window, window > 0 {
                ContextBar(percent: percent)
            }
            breakdownRows
        }
    }

    @ViewBuilder
    private var breakdownRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let usage, let window = usage.contextWindow, window > 0 {
                row(name: "消息", percent: percentOf(usage.input, window))
                row(name: "MCP 工具", percent: 0, placeholder: true)
                row(name: "系统工具", percent: percentOf(usage.output, window))
                row(name: "系统提示词", percent: percentOf(usage.cached, window))
                row(name: "技能", percent: 0, placeholder: true)
                row(name: "其他", percent: percentOf(usage.reasoning, window))
            } else {
                Text("等待首次用量上报")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(DSHTheme.labelTertiary)
            }
        }
    }

    private func row(name: String, percent: Int, placeholder: Bool = false) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(placeholder ? DSHTheme.labelTertiary.opacity(0.35) : DSHTheme.brand)
                .frame(width: 7, height: 7)
            Text(name)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(DSHTheme.label)
            Spacer(minLength: 8)
            Text(placeholder ? "—" : "\(percent)%")
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(placeholder ? DSHTheme.labelTertiary : DSHTheme.label)
                .monospacedDigit()
        }
    }

    private func percentOf(_ value: Int, _ window: Int) -> Int {
        ModelUsageMetrics.percentOfWindow(value, window: window)
    }

    @ViewBuilder
    private var cacheHitSection: some View {
        HStack {
            Text("平均缓存命中率")
                .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                .foregroundStyle(DSHTheme.label)
            Spacer(minLength: 8)
            Text(averageCacheHitPercent.map { "\($0)%" } ?? "—")
                .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                .foregroundStyle(DSHTheme.label)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("剩余额度")
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                    .foregroundStyle(DSHTheme.label)
                if let plan = rateLimits?.planLabel {
                    Text(plan)
                        .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(DSHTheme.brand.opacity(0.12), in: Capsule())
                        .foregroundStyle(DSHTheme.brand)
                }
                Spacer(minLength: 8)
                Text(rateLimitsLoading ? "刷新中…" : "codex account/rateLimits")
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(DSHTheme.labelTertiary)
            }
            let cells = quotaCells()
            if cells.isEmpty {
                Text("等待首次订阅用量上报")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(DSHTheme.labelTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        QuotaCellView(cell: cell, appFontScale: appFontScale)
                    }
                }
            }
            if let err = rateLimitsError, rateLimits == nil {
                Text(err)
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(DSHTheme.error)
                    .lineLimit(2)
            }
        }
    }

    /// Build the 2–3 quota cells from the snapshot:
    ///   1) primary window (5h, etc.)
    ///   2) secondary window (weekly, etc.) when present
    ///   3) Credits balance, hidden when `!credits.isVisible`
    private func quotaCells() -> [QuotaCell] {
        guard let snap = rateLimits else { return [] }
        var out: [QuotaCell] = []
        if let primary = snap.primary {
            out.append(QuotaCell(
                name: primary.windowLabel,
                usedPercent: primary.usedPercent,
                resetsAt: primary.resetsAt,
                kind: .window
            ))
        }
        if let secondary = snap.secondary {
            out.append(QuotaCell(
                name: secondary.windowLabel,
                usedPercent: secondary.usedPercent,
                resetsAt: secondary.resetsAt,
                kind: .window
            ))
        }
        if let credits = snap.credits, credits.isVisible {
            out.append(QuotaCell(
                name: "Credits",
                usedPercent: credits.unlimited ? 0 : nil,
                balance: credits.unlimited ? "无限" : credits.balance,
                kind: .credits
            ))
        }
        return out
    }
}

/// One quota cell rendered by the popover.
struct QuotaCell {
    enum Kind { case window, credits }
    let name: String
    let usedPercent: Int?
    let resetsAt: Date?
    let balance: String?
    let kind: Kind

    init(
        name: String,
        usedPercent: Int?,
        resetsAt: Date? = nil,
        balance: String? = nil,
        kind: Kind
    ) {
        self.name = name
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.balance = balance
        self.kind = kind
    }
}

/// Render a single quota cell (window with progress bar or credits balance).
private struct QuotaCellView: View {
    let cell: QuotaCell
    let appFontScale: AppFontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(cell.name)
                .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                .foregroundStyle(DSHTheme.label)
            valueText
                .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                .foregroundStyle(DSHTheme.label)
                .monospacedDigit()
            progressBar
            if let caption = RateLimitsSnapshot.resetCaption(
                for: cell.kind == .window
                    ? RateLimitWindow(usedPercent: cell.usedPercent ?? 0,
                                      windowDurationMins: 0,
                                      resetsAt: cell.resetsAt)
                    : nil
            ) {
                Text(caption)
                    .font(AppFont.scaled(.caption2, multiplier: appFontScale.multiplier))
                    .foregroundStyle(DSHTheme.labelTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var valueText: some View {
        switch cell.kind {
        case .window:
            if let pct = cell.usedPercent {
                Text("\(pct)%")
            } else {
                Text("—").foregroundStyle(DSHTheme.labelTertiary)
            }
        case .credits:
            if let balance = cell.balance, !balance.isEmpty {
                Text(balance)
            } else {
                Text("—").foregroundStyle(DSHTheme.labelTertiary)
            }
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        switch cell.kind {
        case .window:
            Capsule()
                .fill(levelColor.opacity(0.85))
                .frame(height: 4)
                .overlay(
                    GeometryReader { geo in
                        Capsule()
                            .fill(DSHTheme.surface.opacity(0.5))
                            .frame(width: max(0, geo.size.width * (1 - CGFloat(min(cell.usedPercent ?? 0, 100)) / 100)))
                    },
                    alignment: .trailing
                )
        case .credits:
            Capsule().fill(DSHTheme.warn.opacity(0.7)).frame(height: 4)
        }
    }

    private var levelColor: Color {
        let pct = cell.usedPercent ?? 0
        if pct >= 80 { return DSHTheme.error }
        if pct >= 50 { return DSHTheme.warn }
        return DSHTheme.brand
    }
}

private struct ContextBar: View {
    let percent: Int
    var body: some View {
        GeometryReader { geo in
            let clamped = max(0, min(percent, 100))
            let fillWidth = geo.size.width * Double(clamped) / 100.0
            ZStack(alignment: .leading) {
                Capsule().fill(DSHTheme.border.opacity(0.5))
                Capsule().fill(fillColor(for: clamped)).frame(width: max(2, fillWidth))
            }
        }
        .frame(height: 6)
    }
    private func fillColor(for percent: Int) -> Color {
        if percent >= 80 { return DSHTheme.error }
        if percent >= 50 { return DSHTheme.warn }
        return DSHTheme.brand
    }
}

/// 圆形上下文进度条 —— 淡淡的环,环内显示整数百分比;
/// 无数据时显示 "—",运行中提升亮度。
struct CircularContextMeter: View {
    let percent: Int?
    let isActive: Bool
    var body: some View {
        let value = percent ?? 0
        let visible = percent != nil
        ZStack {
            Circle().stroke(DSHTheme.border.opacity(0.6), lineWidth: 2)
            Circle()
                .trim(from: 0, to: CGFloat(min(value, 100)) / 100.0)
                .stroke(
                    isActive ? DSHTheme.brand : DSHTheme.brand.opacity(0.55),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text(visible ? "\(value)" : "—")
                .font(AppFont.scaled(.caption2, multiplier: 1))
                .foregroundStyle(isActive ? DSHTheme.label : DSHTheme.labelTertiary)
                .monospacedDigit()
        }
        .frame(width: 22, height: 22)
        .opacity(isActive ? 1.0 : 0.85)
    }
}
