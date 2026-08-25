import SwiftUI
import TapgoCore

struct TrajectoryView: View {
    @EnvironmentObject var store: SessionStore
    let thread: TapgoCore.Thread
    /// Turns whose item list is expanded. The most recent turn is
    /// expanded by default so the latest activity is visible without
    /// a click; older turns collapse to keep the timeline scannable.
    @State private var expanded: Set<String>
    /// Which activity kinds to show in the timeline.
    @AppStorage("tapgo.trajectoryFilter") private var filter: TrajectoryFilter = .all
    @State private var query = ""
    @AppStorage("tapgo.trajectoryShowTimeline") private var showTimeline = true

    init(thread: TapgoCore.Thread) {
        self.thread = thread
        let last = thread.turns.last?.id
        self._expanded = State(initialValue: last.map { [$0] } ?? [])
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(L10n.trajectory).font(.headline)
                Spacer()
                Button {
                    showTimeline.toggle()
                } label: {
                    Image(systemName: showTimeline ? "list.bullet" : "list.bullet.rectangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(showTimeline ? "隐藏时间线" : "显示时间线")
                .accessibilityLabel(showTimeline ? "隐藏时间线" : "显示时间线")
                Button {
                    toggleAll()
                } label: {
                    Image(systemName: allExpanded ? "chevron.up.2" : "chevron.down.2")
                }
                .buttonStyle(.borderless)
                .help(allExpanded ? "全部收起" : "全部展开")
                .accessibilityLabel(allExpanded ? "全部收起" : "全部展开")
                Button {
                    copyAll()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("复制全部会话为 Markdown")
                .accessibilityLabel("复制全部会话为 Markdown")
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(thread.title, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("复制标题")
                .accessibilityLabel("复制标题")
                Text(L10n.turnCount(thread.turns.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            if thread.usageTotal > 0 || thread.durationTotalText != nil {
                HStack(spacing: 12) {
                    if thread.usageTotal > 0 {
                        Label(
                            TokenUsage.summary(of: thread.usageTotal),
                            systemImage: "number"
                        )
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    if let d = thread.durationTotalText {
                        Label(d, systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let usage = thread.turns.last(where: { $0.usage != nil })?.usage,
                       let pct = usage.contextPercent {
                        Label("上下文 \(pct)%", systemImage: "gauge.medium")
                            .font(.caption2)
                            .foregroundStyle(contextColor(usage.contextLevel))
                            .help("上下文已用 \(pct)% — 建议接近上限时新建会话")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            if showTimeline {
            Divider()
            Picker("过滤", selection: $filter) {
                ForEach(TrajectoryFilter.allCases) { f in
                    Text(f.title).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("在轨迹中查找…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onExitCommand {
                        if !query.isEmpty { query = "" }
                    }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("清空查找")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: DSHTheme.radiusPill))
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            List {
                ForEach(thread.turns) { turn in
                    Section {
                        DisclosureGroup(isExpanded: expansion(for: turn)) {
                            ForEach(turn.items.filter { TrajectoryFilter.matches(item: $0, filter: filter) && itemMatchesQuery($0) }, id: \.id) { item in
                                TrajectoryItemRow(item: item)
                            }
                        } label: {
                            turnHeader(turn)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            }
        }
        .background(DSHTheme.moduleBg)
    }

    private func expansion(for turn: Turn) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(turn.id) },
            set: { if $0 { expanded.insert(turn.id) } else { expanded.remove(turn.id) } }
        )
    }

    private var allExpanded: Bool {
        !thread.turns.isEmpty && thread.turns.allSatisfy { expanded.contains($0.id) }
    }
    private func itemMatchesQuery(_ item: TurnItem) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        let text: String
        switch item {
        case .userMessage(_, let t): text = t
        case .assistantMessage(_, let t): text = t
        case .reasoning(_, let t): text = t
        case .reasoningSummary(_, let t): text = t
        case .commandExecution(let ce): text = ce.stdout + " " + ce.command
        case .toolCall(let tc): text = tc.name + " " + tc.arguments + " " + (tc.result ?? "")
        case .fileChange(let fc): text = fc.path + " " + fc.diff
        default: text = ""
        }
        return text.lowercased().contains(q)
    }
    private func toggleAll() {
        if allExpanded {
            expanded.removeAll()
        } else {
            expanded = Set(thread.turns.map(\.id))
        }
    }
    private func copyAll() {
        let md = thread.turns.map { TurnMarkdown.render($0) }.joined(separator: "\n\n---\n\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(md, forType: .string)
    }

    private func contextColor(_ level: TapgoCore.ContextLevel?) -> Color {
        switch level {
        case .critical: return DSHTheme.error
        case .warn: return DSHTheme.warn
        case .normal: return DSHTheme.success
        case .none: return .secondary
        }
    }

    @ViewBuilder
    private func turnHeader(_ turn: Turn) -> some View {
        HStack {
            Image(systemName: turnIcon(turn))
            Text(turn.userInput.isEmpty ? L10n.emptyTurn : turn.userInput)
                .lineLimit(1)
            Spacer()
            Text(timeString(turn.startedAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let usage = turn.usage, usage.total > 0 {
                Text(TokenUsage.summary(of: usage.total))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let d = turn.durationText {
                Text(d)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(turnStatusLabel(turn.status))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if turn.status == .running {
                Button {
                    store.cancelActiveTurn()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("中断当前任务")
                .accessibilityLabel("中断当前任务")
            }
            if (turn.status == .failed || turn.status == .interrupted) && !turn.userInput.isEmpty {
                Button {
                    store.sendUserMessage(turn.userInput)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("重试本回合")
                .accessibilityLabel("重试本回合")
            }
            if turn.status == .completed && turn.id == thread.turns.last?.id && !turn.userInput.isEmpty {
                Button {
                    store.newThread()
                    store.sendUserMessage(turn.userInput)
                } label: {
                    Image(systemName: "repeat")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("在新会话中重新生成")
                .accessibilityLabel("重新生成")
            }
            Button {
                NotificationCenter.default.post(name: .tapgoJumpToTurn, object: turn.id)
            } label: {
                Image(systemName: "arrow.right.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("在对话中跳转到该回合")
            .accessibilityLabel("在对话中跳转到该回合")
            CopyIconButton(text: TurnMarkdown.render(turn), help: "复制本回合")
            if !turn.userInput.isEmpty {
                CopyIconButton(text: turn.userInput, help: "复制用户输入")
            }
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func turnIcon(_ turn: Turn) -> String {
        switch turn.status {
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.octagon"
        case .interrupted: return "stop.circle"
        case .running: return "circle.dotted"
        case .awaitingApproval: return "questionmark.circle"
        case .pending: return "clock"
        }
    }

    private func turnStatusLabel(_ status: Turn.Status) -> String {
        switch status {
        case .completed: return "完成"
        case .failed: return "失败"
        case .interrupted: return "已中断"
        case .running: return "运行中"
        case .awaitingApproval: return "待批准"
        case .pending: return "待执行"
        }
    }
}

struct TrajectoryItemRow: View {
    let item: TurnItem

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading) {
                Text(label).font(.subheadline)
                if let via = viaSSH {
                    Text("\(L10n.viaSSHPrefix) \(via)")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                if let detail = detailText {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            if let copy = copyText {
                Spacer(minLength: 4)
                CopyIconButton(text: copy, help: "复制")
            }
        }
        .contextMenu {
            if case .fileChange(let fc) = item {
                Button {
                    let url = URL(fileURLWithPath: fc.path)
                    if FileManager.default.fileExists(atPath: fc.path) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("打开文件", systemImage: "doc")
                }
            }
            if let copy = copyText {
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(copy, forType: .string)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
            }
        }
    }

    private var copyText: String? {
        switch item {
        case .toolCall(let tc): return tc.result ?? tc.arguments
        case .commandExecution(let ce): return ce.stdout.isEmpty ? ce.command : ce.stdout
        case .fileChange(let fc): return fc.diff.isEmpty ? fc.path : fc.diff
        case .reasoning(_, let t): return t
        case .reasoningSummary(_, let t): return t
        case .assistantMessage(_, let t): return t
        case .userMessage(_, let t): return t
        default: return nil
        }
    }

    private var icon: String {
        switch item {
        case .userMessage: return "person.circle"
        case .assistantMessage: return "bubble.left"
        case .reasoning: return "brain"
        case .reasoningSummary: return "text.quote"
        case .toolCall: return "wrench.adjustable"
        case .commandExecution: return "terminal"
        case .fileChange: return "doc"
        case .approval: return "checkmark.shield"
        case .error: return "exclamationmark.triangle"
        }
    }
    private var color: Color {
        switch item {
        case .userMessage: return .blue
        case .assistantMessage: return .purple
        case .reasoning: return .gray
        case .reasoningSummary: return .gray
        case .toolCall: return .indigo
        case .commandExecution: return .green
        case .fileChange: return .orange
        case .approval: return .yellow
        case .error: return .red
        }
    }
    private var label: String {
        switch item {
        case .userMessage(_, let t): return "\(L10n.userPrefix) \(t.prefix(80))"
        case .assistantMessage(_, let t): return "\(L10n.assistantPrefix) \(t.prefix(80))"
        case .reasoning(_, let t): return "\(L10n.reasoningPrefix) \(t.prefix(80))"
        case .reasoningSummary(_, let t): return "\(L10n.reasoningSummary): \(t.prefix(80))"
        case .toolCall(let tc): return "\(L10n.toolPrefix) \(tc.name)"
        case .commandExecution(let ce): return L10n.commandDisplay(String(ce.command.prefix(80)))
        case .fileChange(let fc): return L10n.fileChangeDisplay(fc.kind.rawValue, fc.path)
        case .approval(let ar): return L10n.approvalLabel(ar.kind.rawValue)
        case .error(_, let m): return "\(L10n.errorPrefix) \(m.prefix(80))"
        }
    }
    private var viaSSH: String? {
        if case .commandExecution(let ce) = item { return ce.viaSSH }
        return nil
    }
    private var detailText: String? {
        switch item {
        case .toolCall(let tc): return tc.result ?? tc.arguments
        case .commandExecution(let ce): return ce.stdout.isEmpty ? nil : String(ce.stdout.prefix(200))
        case .fileChange(let fc): return fc.diff.isEmpty ? nil : String(fc.diff.prefix(200))
        default: return nil
        }
    }
}
