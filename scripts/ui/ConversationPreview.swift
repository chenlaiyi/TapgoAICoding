import SwiftUI
import TapgoCore

// Isolated fixture: the shipping response view with fictional turns, no model or SessionStore.
@main
struct ConversationPreview: App {
    var body: some Scene {
        WindowGroup("会话输出验收") { ConversationPreviewContent() }
            .defaultSize(width: 960, height: 900)
    }
}
private struct ConversationPreviewContent: View {
    @State private var remoteReply = true
    @State private var work = false
    @State private var dark = true
    @State private var large = false
    @State private var narrow = false
    @State private var phase = Turn.Status.completed
    private var turn: Turn {
        let done = phase == .completed
        let streaming = phase == .pending
        var items: [TurnItem] = [
            .userMessage(id: "user", text: "请统一会话过程和总结的显示，特别注意关闭过程后的体验。"),
            .assistantMessage(id: "commentary", text: "已定位到过程开关的遗漏，正在核对历史会话和流式回复。"),
            .toolCall(.init(id: "plan-preview", name: "执行计划", arguments: "", result: "✓ 检查显示开关\n→ 验证会话排版\n○ 复查真实应用", status: .succeeded)),
            .reasoning(id: "reason", text: "DETAIL_REASONING_FIXTURE: 此内容仅在主动展开详情后可见。"),
            .toolCall(.init(id: "read", name: "read_file", arguments: "{\"path\":\"Sources/ConversationView.swift\"}", result: "DETAIL_READ_FIXTURE: 文件读取完成", status: .succeeded)),
            .commandExecution(.init(id: "test", command: "swift test --filter Conversation", status: done || streaming ? .succeeded : .running, stdout: "DETAIL_COMMAND_FIXTURE: 24 passed", startedAt: Date()))
        ]
        if phase == .awaitingApproval {
            items.append(.error(id: "notice", message: "需要确认后才能继续。"))
        }
        if done || streaming {
            items.append(.assistantMessage(id: "final", text: streaming ? "已确认执行主机，正在核对项目目录。" : remoteReply ? """
            当前项目在远程 Mac mini 上，目录是 `/Users/developer/Acorn`。

            该目录对应 **Acorn** 仓库，已通过远端的 `hostname`、`pwd` 和 Git 地址核实。

            后续命令会在这个远程目录执行。
            """ : """
            已统一会话过程和总结的显示，关闭开关后只保留回复与必要提示。

            - 过程入口、执行清单和工具详情一起隐藏。
            - 历史会话与运行中回合采用相同规则。
            - 正文、列表和代码块使用统一字号与间距，长内容自然换行。

            **验证结果**：24 项针对性检查通过，深浅色和窄窗口均已检查。

            | 场景 | 结果 |
            | --- | --- |
            | 关闭过程 | **只显示回复** |
            | 主动展开 | 可查看 `命令详情` |

            ```swift
            transcript.showWorkProcess = false
            ```

            可查看[说明文档](https://example.com/guide)。当前完成本地验证，尚未发布。
            """))
        }
        var result = Turn(id: "preview", userInput: "统一输出", items: items, status: streaming ? .running : phase,
                          startedAt: Date(timeIntervalSince1970: 1000), completedAt: done ? Date(timeIntervalSince1970: 1065) : nil)
        result.assistantPhases = ["commentary": "commentary", "final": "final_answer"]
        return result
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Text("会话输出验收").font(.headline)
                    Spacer()
                    Toggle("远程回复", isOn: $remoteReply)
                    Toggle("显示过程", isOn: $work)
                    Toggle("深色", isOn: $dark)
                    Toggle("大字体", isOn: $large)
                    Toggle("窄窗口", isOn: $narrow)
                }
                Picker("回合状态", selection: $phase) {
                    Text("进行中").tag(Turn.Status.running)
                    Text("回复中").tag(Turn.Status.pending)
                    Text("待确认").tag(Turn.Status.awaitingApproval)
                    Text("已完成").tag(Turn.Status.completed)
                    Text("未完成").tag(Turn.Status.failed)
                    Text("已中断").tag(Turn.Status.interrupted)
                }.pickerStyle(.segmented)
            }.padding(18)
            Divider()
            if remoteReply {
                RemoteProjectBanner(
                    project: Project(id: "fixture", displayName: "Mac mini:~/Acorn", kind: .remote, addedAt: Date(), lastUsedAt: Date(), worktreeRoot: URL(fileURLWithPath: "/tmp/fixture-mirror"), remoteHostId: "fixture-host", remotePath: "~/Acorn"),
                    host: RemoteHost(id: "fixture-host", alias: "Mac mini", host: "100.64.0.10", user: "developer", port: 22, addedAt: Date()))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack {
                        Spacer(minLength: 36)
                        ConversationUserMessageLabel(text: remoteReply ? "当前项目在哪里？" : "请统一会话过程和总结的显示。")
                    }
                    ConversationResponseView(turn: turn, showWorkProcess: work) {
                        if phase == .awaitingApproval {
                            Label("需要确认后才能继续。", systemImage: "hand.raised")
                                .font(.system(size: 13)).foregroundStyle(DSHTheme.labelDim)
                        }
                    }
                    if phase == .completed {
                        Button("复制回复", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(TurnResponsePresentation(turn).answerText, forType: .string)
                        }.buttonStyle(.plain).labelStyle(.iconOnly).foregroundStyle(DSHTheme.labelDim)
                    }
                }
                .frame(maxWidth: narrow ? 440 : 760, alignment: .leading)
                .padding(.horizontal, 24).padding(.vertical, 30)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 650)
        .background(DSHTheme.fidelityMainCanvas)
        .environment(\.tapgoFontScale, large ? AppFontScale.large : .medium)
        .preferredColorScheme(dark ? .dark : .light)
    }
}
