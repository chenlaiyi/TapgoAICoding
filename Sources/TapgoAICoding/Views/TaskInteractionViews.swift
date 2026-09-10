import SwiftUI
import TapgoCore

/// A persistent plan snapshot. Expanding it never changes the agent's steps.
struct TaskPlanCard: View {
    let progress: TurnProgressSummary
    let status: Turn.Status
    @State private var expanded = false
    @Environment(\.tapgoFontScale) private var scale: AppFontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checklist").foregroundStyle(DSHTheme.labelDim)
                    Text("执行清单").fontWeight(.medium)
                    Text("\(progress.completedSteps)/\(progress.steps.count)").monospacedDigit().foregroundStyle(DSHTheme.labelDim)
                    Spacer(minLength: 8)
                    Text(progress.statusText(for: status)).foregroundStyle(DSHTheme.labelDim)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 10))
                }
                .font(AppFont.scaled(.callout, multiplier: scale.multiplier))
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("执行清单，已完成 \(progress.completedSteps) 项，共 \(progress.steps.count) 项，\(progress.statusText(for: status))")
            .accessibilityValue(expanded ? "已展开" : "已折叠")
            if expanded {
                Divider().padding(.horizontal, 12)
                TaskBoundedContent(maxHeight: 320) {
                    TaskPlanSteps(progress: progress, status: status).padding(12)
                }
            }
        }
        .background(DSHTheme.composerProjectSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DSHTheme.border, lineWidth: 0.5))
    }
}

struct TaskPlanSteps: View {
    let progress: TurnProgressSummary
    let status: Turn.Status
    @Environment(\.tapgoFontScale) private var scale: AppFontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(progress.steps) { step in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: icon(step))
                        .font(.system(size: 14))
                        .foregroundStyle(step.status == .pending ? DSHTheme.labelTertiary : DSHTheme.labelDim)
                        .frame(width: 18, height: 20)
                        .accessibilityHidden(true)
                    Text(step.text)
                        .font(AppFont.scaled(.callout, multiplier: scale.multiplier))
                        .foregroundStyle(step.status == .completed ? DSHTheme.labelDim : DSHTheme.label)
                        .strikethrough(step.status == .completed, color: DSHTheme.labelTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(step.text)，\(progress.stepStatusText(step, turnStatus: status))")
            }
        }
    }

    private func icon(_ step: TurnProgressSummary.Step) -> String {
        switch step.status {
        case .completed: return "checkmark.circle.fill"
        case .pending: return "circle"
        case .inProgress:
            switch status {
            case .running: return "circle.lefthalf.filled"
            case .awaitingApproval: return "hand.raised.circle"
            case .interrupted: return "pause.circle"
            case .failed, .completed: return "exclamationmark.circle"
            case .pending: return "circle"
            }
        }
    }
}

/// Codex 桌面端对齐(2026-09-10 实机截图):输入框上方的活动带是**一张**
/// 浅表面卡——排队行在上,目标行最下、最贴近 composer。每行单行内联,
/// 动作靠右;角标按钮可把整条活动带折叠成一行摘要,让位给 composer。
struct TaskActivityStrip<Rows: View>: View {
    var queueCount: Int
    var error: String?
    var goal: String?
    var goalStatus: String?
    var goalHasStarted = true
    var goalCanStart = true
    var goalElapsed: String
    var onPause: () -> Void
    var onStart: () -> Void
    var onEditGoal: () -> Void
    var onRemoveGoal: () -> Void
    @ViewBuilder var rows: () -> Rows

    @State private var collapsed = false
    @State private var goalExpanded = false
    // macOS 14 兼容:symbolEffect(.rotate) 要 macOS 15,手动转。
    @State private var spinAngle: Double = 0
    @Environment(\.tapgoFontScale) private var scale: AppFontScale

    private var running: Bool { goalStatus == "running" }
    private var goalTitle: String {
        guard goal != nil else { return "排队消息" }
        if running { return "进行中的目标" }
        if goalStatus == "completed" { return "已完成的目标" }
        return goalHasStarted ? "已暂停的目标" : "待开始的目标"
    }
    private var summary: String {
        switch (queueCount > 0, goal != nil) {
        case (true, true): return "排队 \(queueCount) 条 · \(goalTitle)"
        case (true, false): return "排队 \(queueCount) 条"
        default: return goalTitle
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if collapsed {
                summaryRow
            } else {
                if queueCount > 0 { rows() }
                if queueCount > 0 && goal != nil {
                    Divider().padding(.horizontal, 12)
                }
                if let goal { goalRow(goal) }
            }
            if let error {
                Divider().padding(.horizontal, 12)
                Label(error, systemImage: "exclamationmark.circle")
                    .font(AppFont.scaled(.caption, multiplier: scale.multiplier))
                    .foregroundStyle(DSHTheme.warn)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
        .background(DSHTheme.composerProjectSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DSHTheme.border, lineWidth: 0.5))
        .accessibilityIdentifier("queued-message-card")
    }

    /// 目标行:转圈图标 + 状态标题 + 内联截断的目标文本 + 计时 + 移除/暂停/折叠。
    @ViewBuilder
    private func goalRow(_ goal: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                    .foregroundStyle(DSHTheme.labelDim)
                    .rotationEffect(.degrees(spinAngle))
                    .onChange(of: running) { _, isRunning in
                        if isRunning {
                            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spinAngle = 360 }
                        } else {
                            var tx = Transaction()
                            tx.disablesAnimations = true
                            withTransaction(tx) { spinAngle = 0 }
                        }
                    }
                    .onAppear {
                        if running {
                            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spinAngle = 360 }
                        }
                    }
                    .accessibilityHidden(true)
                Text(goalTitle)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(goal)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(DSHTheme.labelDim)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { goalExpanded = true } }
                    .accessibilityLabel("目标:\(goal),点按展开全文")
                Spacer(minLength: 8)
                Text(goalElapsed)
                    .monospacedDigit()
                    .foregroundStyle(DSHTheme.labelTertiary)
                // Codex 实机顺序:计时 → 垃圾桶 → 圆圈暂停/开始 → 折叠角标。
                stripButton("trash", "移除目标", action: onRemoveGoal)
                    .disabled(running)
                stripButton(running ? "pause.circle" : "play.circle",
                            running ? "暂停目标并中断当前执行" : "将目标发送给助手继续执行",
                            action: running ? onPause : onStart)
                    .disabled(!running && !goalCanStart)
                stripButton("arrow.down.right.and.arrow.up.left", "折叠目标与排队") {
                    withAnimation(.easeInOut(duration: 0.15)) { collapsed = true }
                }
            }
            .font(AppFont.scaled(.subheadline, multiplier: scale.multiplier))
            .padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(Rectangle())
            .contextMenu {
                Button("编辑目标…", action: onEditGoal).disabled(running)
                Button("移除目标", action: onRemoveGoal).disabled(running)
            }
            if goalExpanded {
                Divider().padding(.horizontal, 12)
                TaskBoundedContent(maxHeight: 180) {
                    Text(goal)
                        .font(AppFont.scaled(.callout, multiplier: scale.multiplier))
                        .foregroundStyle(DSHTheme.label)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { goalExpanded = false } }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// 折叠后的摘要行:一条可点回的小字,保留计数与计时。
    private var summaryRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { collapsed = false }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11))
                Text(summary).lineLimit(1)
                Spacer(minLength: 8)
                if goal != nil {
                    Text(goalElapsed).monospacedDigit()
                }
            }
            .font(AppFont.scaled(.caption, multiplier: scale.multiplier))
            .foregroundStyle(DSHTheme.labelDim)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("展开活动带:\(summary)")
        .accessibilityValue("已折叠")
    }

    private func stripButton(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(DSHTheme.labelDim)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct TaskContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Short text takes its natural height; long text stays scrollable inside the card.
private struct TaskBoundedContent<Content: View>: View {
    var maxHeight: CGFloat
    @ViewBuilder var content: () -> Content
    @State private var measuredHeight: CGFloat = 44
    var body: some View {
        ScrollView {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: TaskContentHeight.self, value: geometry.size.height)
                })
        }
        .frame(height: min(maxHeight, measuredHeight))
        .onPreferenceChange(TaskContentHeight.self) { value in
            if value > 0 && abs(measuredHeight - value) > 0.5 { measuredHeight = value }
        }
    }
}
