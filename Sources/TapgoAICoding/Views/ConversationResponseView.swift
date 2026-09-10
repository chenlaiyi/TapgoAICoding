import SwiftUI
import TapgoCore

/// Shipping response surface, independent of SessionStore for deterministic UI verification.
struct ConversationResponseView<Notices: View>: View {
    let turn: Turn
    let showWorkProcess: Bool
    @ViewBuilder var notices: () -> Notices
    @Environment(\.tapgoFontScale) private var scale: AppFontScale

    private var running: Bool { turn.status == .running || turn.status == .pending }
    var body: some View {
        let presentation = TurnResponsePresentation(turn)
        // v0.5.187: 运行中始终显示 work items 单行（对齐 codex 桌面端），
        // 完成后由 showWorkProcess 决定是否展开。
        let showWork = showWorkProcess || running
        let work = showWork ? presentation.work : []
        VStack(alignment: .leading, spacing: 16) {
            if showWork {
                if let progress = TurnProgressSummary(turn: turn) {
                    TaskPlanCard(progress: progress, status: turn.status)
                }
                if !work.isEmpty {
                    ConversationWorkDisclosure(items: work, status: turn.status, duration: turn.duration, defaultExpanded: showWorkProcess)
                }
            }
            notices()
            ForEach(presentation.messages) { item in
                if case .assistantMessage(_, let text) = item {
                    AssistantResponseText(text: text, isStreaming: running && turn.items.last?.id == item.id)
                }
            }
            if running && (!showWorkProcess || work.isEmpty || !presentation.messages.isEmpty) {
                ConversationWorkingIndicator(title: presentation.messages.isEmpty ? "正在处理" : "正在生成回复")
            } else if turn.status == .awaitingApproval && presentation.notices.isEmpty {
                ConversationWorkingIndicator(title: "等待确认", animated: false)
            }
            if let message = ConversationPresentation.emptyResponse(status: turn.status),
               presentation.messages.isEmpty || turn.status != .completed {
                Text(message).font(.system(size: 13 * scale.multiplier)).foregroundStyle(DSHTheme.labelDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AssistantResponseText: View {
    let text: String
    var isStreaming = false
    @Environment(\.tapgoFontScale) private var scale: AppFontScale
    @State private var pulse = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MarkdownMessageView(text, isStreaming: isStreaming)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contextMenu {
                    Button("复制回复", systemImage: "doc.on.doc") { copy(text) }
                    Button("复制为纯文本", systemImage: "text.alignleft") { copy(MarkdownPlainText.render(text)) }
                }
            // v0.5.195: streaming 时显示 3 跳动 dots + 弱化文字（对齐 Codex 桌面端，与 v0.5.192/194 一致）。
            if isStreaming {
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .frame(width: 4, height: 4)
                                .foregroundStyle(DSHTheme.labelDim)
                                .opacity(pulse ? 1.0 : 0.3)
                                .animation(
                                    .easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.2),
                                    value: pulse
                                )
                        }
                    }
                    .frame(width: 14, alignment: .leading)
                    .accessibilityHidden(true)
                    .onAppear { pulse = true }
                    Text("生成中…")
                        .font(AppFont.scaled(.caption2, multiplier: scale.multiplier))
                        .foregroundStyle(DSHTheme.labelTertiary)
                }
                .padding(.leading, 2)
            }
        }
    }
    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// v0.5.192: 对齐 codex 桌面端，running 状态用 3 跳动 dots 动画（不再是 spinner + 文字）。
struct ConversationWorkingIndicator: View {
    let title: String
    var animated = true
    @Environment(\.tapgoFontScale) private var scale: AppFontScale
    var body: some View {
        // v0.5.213: 对齐 Codex 实机 —— 去掉前面 3 个点，「正在处理」四字做
        // shimmer 流光（gradient 高亮带从左到右扫过），不是 3 点跳动。
        Group {
            if animated {
                ShimmerText(text: title, fontSize: 13 * scale.multiplier)
            } else {
                Image(systemName: "hand.raised").accessibilityHidden(true)
                Text(title).font(.system(size: 13 * scale.multiplier))
            }
        }
        .foregroundStyle(DSHTheme.labelDim)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// v0.5.213: 文字流光（Codex 风格的「正在处理」shimmer）。
struct ShimmerText: View {
    let text: String
    let fontSize: CGFloat
    /// 0...1 loop, 控制高亮带在文字宽度内的位置（-0.3 ... 1.3 偏移以进入/离开）。
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = (t.truncatingRemainder(dividingBy: 1.6)) / 1.6
            let base = Text(text).font(.system(size: fontSize))
            base
                .foregroundStyle(DSHTheme.labelDim)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.85),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: UnitPoint(x: phase - 0.25, y: 0.5),
                        endPoint:   UnitPoint(x: phase + 0.25, y: 0.5)
                    )
                    .blendMode(.plusLighter)
                    .mask(base)
                )
        }
    }
}

private struct ConversationWorkDisclosure: View {
    let items: [TurnItem]
    let status: Turn.Status
    let duration: TimeInterval?
    /// `showWorkProcess` 设置为 true 时默认展开，且 turn 结束后不强制收回。
    var defaultExpanded: Bool = false
    @State private var expansionOverride: Bool?
    @Environment(\.tapgoFontScale) private var scale: AppFontScale
    private var active: Bool { status == .pending || status == .running || status == .awaitingApproval }
    // v0.5.226: 默认收起（`?? false`），但 `showWorkProcess` 打开时 `?? true` 默认展开。
    // 用户点 chevron 后用 expansionOverride 维持状态；onChange 在 turn 结束时只在
    // `defaultExpanded == false`（即设置关闭）时才清 override，避免"开着设置但过程被收回"。
    private var expanded: Bool { expansionOverride ?? defaultExpanded }
    private var blockCount: Int { TurnPresentation.compactBlocks(items).count }
    private var headerTitle: String {
        let base = ConversationPresentation.workTitle(status: status, duration: duration)
        guard blockCount > 0 else { return base }
        return "\(base) · \(blockCount) 步"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { expansionOverride = expanded ? false : true } label: {
                HStack(spacing: 7) {
                    // v0.5.224: 对齐 Codex 实机 —— 去掉 3 跳动 dots，
                    // 「正在处理」文字改 shimmer 流光（用户反馈）。
                    if active {
                        ShimmerText(text: headerTitle, fontSize: 13 * scale.multiplier)
                    } else {
                        Text(headerTitle)
                    }
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 10))
                }
                .font(.system(size: 13 * scale.multiplier))
                .foregroundStyle(DSHTheme.labelDim)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "收起工作过程" : "展开工作过程")
            .accessibilityValue(headerTitle)
            if expanded {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(TurnPresentation.compactBlocks(items)) { block in
                        switch block {
                        // v0.5.188: 工作过程中的 assistantMessage 改为紧凑单行可展开
                        // （之前以完整 Markdown 渲染，跟最终答案/其他 activity 重复）。
                        case .item(.assistantMessage(_, let text)):
                            ConversationWorkAssistantRow(text: text, running: active)
                        case .activity(let activity):
                            ConversationActivityRow(activity: activity, running: active)
                        default: EmptyView()
                        }
                    }
                }
                .padding(.leading, 1)
            }
        }
        .onChange(of: active) { _, value in
            if !value && !defaultExpanded { expansionOverride = nil }
        }
    }
}

/// v0.5.195: 内联 3 跳动 dots（用于 ConversationWorkDisclosure 标题旁表明正在 running）。

private struct ConversationActivityRow: View {
    let activity: TurnActivityRollup
    let running: Bool
    @State private var expanded = false
    @Environment(\.tapgoFontScale) private var scale: AppFontScale
    private var display: TurnActivityDisplay { TurnPresentation.activityDisplay(for: activity, turnIsRunning: running) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    // v0.5.190: running 且未失败时显示 spinner（对齐 Codex 桌面端）。
                    if running && !display.isFailure {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: display.systemImage ?? "circle").frame(width: 16)
                    }
                    Text(ConversationPresentation.activityTitle(activity, running: running)).lineLimit(1)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9))
                }
                .font(.system(size: 12 * scale.multiplier))
                .foregroundStyle(display.isFailure ? DSHTheme.error : DSHTheme.labelDim)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ConversationPresentation.activityTitle(activity, running: running))
            .accessibilityValue(expanded ? "详情已展开" : "详情已收起")
            if expanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(activity.events) { event in
                            Text(event.searchableText)
                                .font(.system(size: 11 * scale.multiplier, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(12)
                }
                .frame(maxHeight: 220)
                .background(DSHTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(DSHTheme.border, lineWidth: 0.5))
            }
        }
    }
}

/// v0.5.188: 工作过程中的 assistantMessage 紧凑单行 + 可点击展开
/// 完整 Markdown，跟 ConversationActivityRow 保持一致的交互样式。
private struct ConversationWorkAssistantRow: View {
    let text: String
    let running: Bool
    @State private var expanded = false
    @Environment(\.tapgoFontScale) private var scale: AppFontScale

    private var previewText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
        return firstLine.count > 60 ? String(firstLine.prefix(60)) + "…" : firstLine
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "text.quote").frame(width: 16)
                    Text(previewText).lineLimit(1)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9))
                }
                .font(.system(size: 12 * scale.multiplier))
                .foregroundStyle(DSHTheme.labelDim)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(previewText)
            .accessibilityValue(expanded ? "详情已展开" : "详情已收起")
            if expanded {
                MarkdownMessageView(text)
                    .environment(\.conversationBodySize, 12)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DSHTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(DSHTheme.border, lineWidth: 0.5))
            }
        }
    }
}

struct ConversationUserMessageLabel: View {
    let text: String
    @Environment(\.tapgoFontScale) private var scale: AppFontScale
    var body: some View {
        Text(text)
            .font(.system(size: 15 * scale.multiplier))
            .lineSpacing(4)
            .foregroundStyle(DSHTheme.label)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(DSHTheme.conversationUserBg, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(DSHTheme.border, lineWidth: 0.5))
            .textSelection(.enabled)
    }
}
