import SwiftUI
import TapgoCore

// Isolated visual fixture: uses shipping components, never constructs SessionStore.
@main
struct TaskInteractionPreview: App {
    var body: some Scene {
        WindowGroup("任务交互验收") { PreviewContent().frame(minWidth: 460, minHeight: 760) }
    }
}
private struct PreviewContent: View {
    @State private var phase: Turn.Status = .running
    @State private var goalStatus = "running"
    @State private var dark = true
    @State private var large = false
    @State private var showGoal = true
    @State private var editGoal = false
    @State private var queued = ["检查清单的未完成项", "补充窄窗口与长文本验证"]
    @State private var goal = "将清单、任务与目标的交互统一到桌面应用中。保留长内容、步骤状态与可用操作，并在窄窗口中完成布局验收。验证完成后再准备发布。"
    private var summary: TurnProgressSummary {
        let done = phase == .completed
        let call = ToolCall(id: "plan-preview", name: "执行计划", arguments: "",
                            result: "✓ 检查现有界面与状态\\n".replacingOccurrences(of: "\\n", with: "\n") + (done ? "✓" : "→") + " 统一清单、任务和目标组件\n" + (done ? "✓" : "○") + " 验证窄窗口、长内容与状态切换", status: .succeeded)
        return TurnProgressSummary(id: "preview", items: [.toolCall(call)])!
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("交互状态验收").font(.headline)
                Spacer()
                Toggle("深色", isOn: $dark)
                Toggle("大字体", isOn: $large)
            }
            Picker("任务状态", selection: $phase) {
                Text("进行中").tag(Turn.Status.running)
                Text("待批准").tag(Turn.Status.awaitingApproval)
                Text("已暂停").tag(Turn.Status.interrupted)
                Text("失败").tag(Turn.Status.failed)
                Text("已完成").tag(Turn.Status.completed)
            }
            .pickerStyle(.segmented)
            TaskPlanCard(progress: summary, status: phase)
            Spacer(minLength: 24)
            if showGoal {
                TaskGoalCard(goal: goal, status: goalStatus, elapsed: "2m 18s",
                             onPause: { goalStatus = "paused" }, onStart: { goalStatus = "running" },
                             onEdit: { editGoal = true }, onRemove: { showGoal = false })
            } else { Button("恢复目标") { showGoal = true } }
            VStack(spacing: -25) {
                if !queued.isEmpty {
                    TaskQueueCard(count: queued.count) {
                        VStack(spacing: 0) {
                            ForEach(Array(queued.enumerated()), id: \.offset) { index, text in
                                HStack {
                                    Text(text).lineLimit(2)
                                    Spacer()
                                    Button("移除", systemImage: "xmark") { queued.remove(at: index) }.labelStyle(.iconOnly)
                                }.padding(12).frame(minHeight: 52)
                            }
                        }
                    }.padding(.horizontal, 12)
                }
                Text("输入下一条消息…")
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                    .background(DSHTheme.composerSurface, in: RoundedRectangle(cornerRadius: 18))
            }

        }
        .padding(24)
        .background(DSHTheme.fidelityMainCanvas)
        .preferredColorScheme(dark ? .dark : .light)
        .environment(\.tapgoFontScale, large ? .large : .medium)
        .sheet(isPresented: $editGoal) {
            VStack { TextEditor(text: $goal); Button("保存") { editGoal = false } }.padding(20).frame(width: 400, height: 220)
        }
    }
}
