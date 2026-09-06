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

/// Goal actions stay explicit, while long requirements can be read in place.
struct TaskGoalCard: View {
    let goal: String
    let status: String?
    let elapsed: String
    var hasStarted = true
    var canStart = true
    var onPause: () -> Void
    var onStart: () -> Void
    var onEdit: () -> Void
    var onRemove: () -> Void
    @State private var expanded = false
    @Environment(\.tapgoFontScale) private var scale: AppFontScale
    private var running: Bool { status == "running" }
    private var title: String { running ? "进行中" : (status == "completed" ? "已完成" : (hasStarted ? "已暂停" : "待开始")) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "scope").foregroundStyle(DSHTheme.labelDim)
                Text("目标").fontWeight(.medium)
                Text(title).foregroundStyle(DSHTheme.labelDim)
                Spacer(minLength: 6)
                Text(elapsed).monospacedDigit().foregroundStyle(DSHTheme.labelTertiary)
                Button(action: running ? onPause : onStart) {
                    Label(running ? "暂停" : (hasStarted ? "继续" : "开始"), systemImage: running ? "pause" : "play")
                }
                .buttonStyle(.plain)
                .disabled(!running && !canStart)
                .help(running ? "暂停目标并中断当前执行" : "将目标发送给助手继续执行")
                Menu {
                    Button("编辑目标…", action: onEdit).disabled(running)
                    Button("移除目标", action: onRemove).disabled(running)
                } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .accessibilityLabel("目标操作")
            }
            .font(AppFont.scaled(.callout, multiplier: scale.multiplier))
            if expanded {
                TaskBoundedContent(maxHeight: 180) {
                    Text(goal)
                        .font(AppFont.scaled(.callout, multiplier: scale.multiplier))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("收起目标", systemImage: "chevron.up") { expanded = false }
                    .buttonStyle(.plain)
                    .font(AppFont.scaled(.caption, multiplier: scale.multiplier))
                    .foregroundStyle(DSHTheme.labelDim)
            } else {
                Button { expanded = true } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text(goal)
                            .font(AppFont.scaled(.callout, multiplier: scale.multiplier))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10)).foregroundStyle(DSHTheme.labelDim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("展开目标：\(goal)")
            }
        }
        .padding(12)
        .background(DSHTheme.composerProjectSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DSHTheme.border, lineWidth: 0.5))
    }
}

/// Shared queue shell keeps collapse and overflow behavior identical in every state.
struct TaskQueueCard<Rows: View>: View {
    let count: Int
    var error: String?
    @ViewBuilder var rows: () -> Rows
    @State private var expanded = true
    @Environment(\.tapgoFontScale) private var scale: AppFontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    Text("待发送 · \(count) 条")
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.up").font(.system(size: 9))
                }
                .font(AppFont.scaled(.caption, multiplier: scale.multiplier))
                .foregroundStyle(DSHTheme.labelDim)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "已展开" : "已折叠")
            if expanded {
                ScrollView { rows() }
                    .frame(height: min(CGFloat(count) * 54 * scale.multiplier, 190))
            }
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(AppFont.scaled(.caption, multiplier: scale.multiplier))
                    .foregroundStyle(DSHTheme.warn)
                    .padding(12)
            }
        }
        .padding(.bottom, 25)
        .background(DSHTheme.composerProjectSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(DSHTheme.border, lineWidth: 0.5))
        .accessibilityIdentifier("queued-message-card")
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
