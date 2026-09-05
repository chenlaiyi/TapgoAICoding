import SwiftUI
import TapgoCore
import UserNotifications

/// Sidebar-pinned list of scheduled tasks. Editing happens inline in a sheet;
/// list rows show name + schedule label + next fire time + on/off toggle +
/// last execution outcome (with failure badge) + a "play" button for manual
/// fire. New tasks are added via the toolbar "+" button.
struct ScheduledTasksView: View {
    @EnvironmentObject var bridge: ScheduledTaskBridge
    @State private var tasks: [ScheduledTask] = []
    @State private var editing: ScheduledTask? = nil
    @State private var draftName: String = ""
    @State private var draftPrompt: String = ""
    @State private var draftScheduleKind: String = "daily"
    @State private var draftWeekday: Int = 2  // Monday
    @State private var draftHour: Int = 9
    @State private var draftMinute: Int = 0
    @State private var draftIntervalMin: Int = 30
    @State private var draftFireAt: Date = Date().addingTimeInterval(3600)
    @State private var draftThreadMode: String = "new"  // "new" | "active"
    @State private var statusMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if tasks.isEmpty {
                emptyState
            } else {
                taskList
            }
            if let s = statusMessage {
                Divider()
                Text(s)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DSHTheme.fidelityMainCanvas)
        .sheet(item: $editing) { task in
            editorSheet(for: task)
        }
        .task { reload() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(DSHTheme.trajectoryAssistant)
            Text("定时任务")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DSHTheme.label)
            Spacer()
            Button {
                createDraft()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("新建定时任务")
            .accessibilityLabel("新建定时任务")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DSHTheme.fidelityTitlebar)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "clock")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("还没有定时任务")
                .font(.headline)
                .foregroundStyle(DSHTheme.label)
            Text("定时任务会在设定时间自动注入提示词到新会话或当前活跃会话。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button {
                createDraft()
            } label: {
                Label("新建第一个任务", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(tasks) { task in
                    row(for: task)
                }
            }
            .padding(12)
        }
    }

    private func row(for task: ScheduledTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: task.enabled ? "clock.fill" : "clock.badge.xmark")
                    .foregroundStyle(task.enabled ? DSHTheme.trajectoryAssistant : .secondary)
                Text(task.name)
                    .font(.headline)
                    .foregroundStyle(DSHTheme.label)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { task.enabled },
                    set: { newVal in toggle(task: task, enabled: newVal) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(task.schedule.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let nxt = task.nextFireAt, task.enabled {
                    Text("· 下次 \(formatRelative(nxt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    runNow(task: task)
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .help("立即运行（不影响下次计划）")
                .accessibilityLabel("立即运行 \(task.name)")
                Button {
                    editing = task
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("编辑")
                .accessibilityLabel("编辑 \(task.name)")
                Button {
                    delete(task)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除")
                .accessibilityLabel("删除 \(task.name)")
            }
            // Last execution summary line — only shown once the task has fired.
            if let last = task.resolvedHistory.last {
                HStack(spacing: 6) {
                    Image(systemName: outcomeIcon(last.outcome))
                        .font(.caption)
                        .foregroundStyle(outcomeColor(last.outcome))
                    Text("上次：\(outcomeText(last))")
                        .font(.caption)
                        .foregroundStyle(outcomeColor(last.outcome))
                    Spacer()
                    if task.resolvedHistory.count > 1 {
                        Text("近 \(task.resolvedHistory.count) 次")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(12)
        .background(DSHTheme.fidelitySidebarMid.opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Outcome styling

    private func outcomeIcon(_ o: ExecutionRecord.Outcome) -> String {
        switch o {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .skipped: return "forward.circle.fill"
        }
    }

    private func outcomeColor(_ o: ExecutionRecord.Outcome) -> Color {
        switch o {
        case .success: return .green
        case .failure: return .red
        case .skipped: return .orange
        }
    }

    private func outcomeText(_ r: ExecutionRecord) -> String {
        let when = formatRelative(r.firedAt)
        switch r.outcome {
        case .success:
            if let ms = r.durationMs { return "\(when) · 成功（\(ms)ms）" }
            return "\(when) · 成功"
        case .failure:
            let msg = (r.errorMessage ?? "未知错误").prefix(60)
            return "\(when) · 失败：\(msg)"
        case .skipped:
            return "\(when) · 跳过：\(r.errorMessage ?? "未配置")"
        }
    }

    // MARK: - Editor sheet

    private func editorSheet(for task: ScheduledTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task.resolvedHistory.isEmpty && task.name != "新任务" ? "编辑任务" : (task.name == "新任务" ? "新建任务" : "编辑任务"))
                .font(.headline)
            Form {
                TextField("任务名", text: $draftName)
                TextField("提示词", text: $draftPrompt, axis: .vertical)
                    .lineLimit(3...8)
                    .textFieldStyle(.roundedBorder)
                Picker("触发时机", selection: $draftScheduleKind) {
                    Text("每天 HH:MM").tag("daily")
                    Text("每 N 分钟").tag("interval")
                    Text("每周某天").tag("weekly")
                    Text("一次性").tag("oneShot")
                }
                .pickerStyle(.segmented)
                Group {
                    if draftScheduleKind == "daily" {
                        Stepper(value: $draftHour, in: 0...23) {
                            HStack { Text("小时"); Spacer(); Text(String(format: "%02d", draftHour)) }
                        }
                        Stepper(value: $draftMinute, in: 0...59) {
                            HStack { Text("分钟"); Spacer(); Text(String(format: "%02d", draftMinute)) }
                        }
                    } else if draftScheduleKind == "interval" {
                        Stepper(value: $draftIntervalMin, in: 1...1440) {
                            HStack { Text("间隔（分钟）"); Spacer(); Text("\(draftIntervalMin)") }
                        }
                    } else if draftScheduleKind == "weekly" {
                        Picker("星期", selection: $draftWeekday) {
                            Text("周一").tag(2); Text("周二").tag(3); Text("周三").tag(4)
                            Text("周四").tag(5); Text("周五").tag(6); Text("周六").tag(7); Text("周日").tag(1)
                        }
                        Stepper(value: $draftHour, in: 0...23) {
                            HStack { Text("小时"); Spacer(); Text(String(format: "%02d", draftHour)) }
                        }
                        Stepper(value: $draftMinute, in: 0...59) {
                            HStack { Text("分钟"); Spacer(); Text(String(format: "%02d", draftMinute)) }
                        }
                    } else {
                        DatePicker("触发时间", selection: $draftFireAt, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Picker("目标会话", selection: $draftThreadMode) {
                    Text("新建会话").tag("new")
                    Text("当前活跃会话").tag("active")
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)
            HStack {
                Button("取消") { editing = nil }
                Spacer()
                Button("保存") {
                    saveDraft(existing: task)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty ||
                          draftPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460, height: 520)
        .onAppear { loadDraft(from: task) }
    }

    private func loadDraft(from t: ScheduledTask) {
        draftName = t.name
        draftPrompt = t.prompt
        draftThreadMode = t.targetThreadId == nil ? "new" : "active"
        switch t.schedule {
        case .daily(let h, let m):
            draftScheduleKind = "daily"; draftHour = h; draftMinute = m
        case .interval(let s):
            draftScheduleKind = "interval"; draftIntervalMin = max(1, Int(s / 60))
        case .oneShot(let d):
            draftScheduleKind = "oneShot"; draftFireAt = d
        case .weekly(let wd, let h, let m):
            draftScheduleKind = "weekly"; draftWeekday = wd; draftHour = h; draftMinute = m
        }
    }

    private func buildSchedule() -> ScheduleSpec {
        switch draftScheduleKind {
        case "daily": return .daily(hour: draftHour, minute: draftMinute)
        case "interval": return .interval(seconds: TimeInterval(draftIntervalMin * 60))
        case "oneShot": return .oneShot(draftFireAt)
        case "weekly": return .weekly(weekday: draftWeekday, hour: draftHour, minute: draftMinute)
        default: return .daily(hour: 9, minute: 0)
        }
    }

    private func createDraft() {
        let new = ScheduledTask(name: "新任务", prompt: "", schedule: .daily(hour: 9, minute: 0))
        loadDraft(from: new)
        editing = new
    }

    private func saveDraft(existing: ScheduledTask) {
        var t = existing
        t.name = draftName.trimmingCharacters(in: .whitespaces)
        t.prompt = draftPrompt
        t.schedule = buildSchedule()
        t.targetThreadId = draftThreadMode == "active" ? t.targetThreadId : nil
        t.enabled = true
        t.nextFireAt = t.schedule.nextFire(after: Date(), lastFired: t.lastFiredAt)
        do {
            try bridge.taskStore.save(t)
            statusMessage = "已保存：\(t.name)"
            editing = nil
            reload()
        } catch {
            statusMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func toggle(task: ScheduledTask, enabled: Bool) {
        var t = task
        t.enabled = enabled
        t.nextFireAt = enabled ? t.schedule.nextFire(after: Date(), lastFired: t.lastFiredAt) : nil
        try? bridge.taskStore.save(t)
        reload()
    }

    private func delete(_ task: ScheduledTask) {
        bridge.taskStore.delete(id: task.id)
        statusMessage = "已删除：\(task.name)"
        reload()
    }

    private func runNow(task: ScheduledTask) {
        statusMessage = "正在运行：\(task.name)"
        Task { @MainActor in
            await bridge.runNow(task)
            reload()
            statusMessage = "已触发：\(task.name)（最近执行已记录）"
        }
    }

    private func reload() {
        tasks = bridge.taskStore.loadAll()
    }

    private func formatRelative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.locale = Locale(identifier: "zh_CN")
        return f.localizedString(for: d, relativeTo: Date())
    }
}
