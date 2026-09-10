import Foundation
import TapgoCore

func runConversationPresentationTests(_ t: TestRunner) {
    let secret = "raw-command-and-reasoning-detail"
    let events: [TurnItem] = [
        .assistantMessage(id: "progress", text: "已定位排版问题，正在核对显示开关。"),
        .reasoning(id: "reason", text: secret),
        .toolCall(.init(id: "read", name: "read_file", arguments: secret, status: .succeeded)),
        .commandExecution(.init(id: "cmd", command: secret, status: .failed, startedAt: Date())),
        .assistantMessage(id: "answer", text: "已修复显示。")
    ]
    for status in [Turn.Status.pending, .running, .awaitingApproval, .completed, .failed, .interrupted] {
        var turn = Turn(id: "turn", userInput: "修复显示", items: events, status: status, startedAt: Date())
        turn.assistantPhases = ["progress": "commentary", "answer": "final_answer"]
        let presentation = TurnResponsePresentation(turn)
        t.expect(ConversationPresentation.workItems(presentation, showWorkProcess: false).isEmpty, "conversation: quiet mode hides all work in \(status)")
        t.expectEqual(ConversationPresentation.workItems(presentation, showWorkProcess: true).count, 4, "conversation: opt-in process preserved in \(status)")
        t.expectEqual(presentation.answerText, "已修复显示。", "conversation: result independent of visibility in \(status)")
        t.expectEqual(turn.items, events, "conversation: hiding work never changes stored history")
    }
    for block in TurnPresentation.compactBlocks(events) {
        if case .activity(let activity) = block {
            let title = ConversationPresentation.activityTitle(activity, running: true)
            // v0.5.234: 对齐 Codex 实机 —— 折叠行显示命令内容（不是纯标签），不再隐藏细节。
            t.expect(!title.isEmpty, "conversation: collapsed activity has a title")
            if activity.latest.id == "cmd" { t.expect(title.contains("失败"), "conversation: failed activity remains distinguishable") }
        }
    }
    t.expectEqual(ConversationPresentation.workTitle(status: .completed, duration: nil), "已工作", "conversation: missing duration never invents zero seconds")
    for duration in [Double.infinity, .nan, .greatestFiniteMagnitude, -1] {
        t.expectEqual(ConversationPresentation.workTitle(status: .completed, duration: duration), "已工作", "conversation: invalid duration is safe")
    }
    t.expectEqual(ConversationPresentation.workTitle(status: .completed, duration: 65), "已工作 1 分 5 秒", "conversation: completed work duration")
    t.expectEqual(ConversationPresentation.workTitle(status: .failed, duration: 65), "处理未完成", "conversation: failure is not success")
    var live = Turn(id: "live", userInput: "", items: [.assistantMessage(id: "a", text: "流式回复")], status: .running, startedAt: Date())
    live.assistantPhases = ["a": " final "]
    t.expectEqual(TurnResponsePresentation(live).answerText, "流式回复", "conversation: compatible final phase streams without becoming process")
    live.assistantPhases = [:]
    t.expect(TurnResponsePresentation(live).messages.isEmpty, "conversation: untyped progress is never guessed to be a result")
    let plain = MarkdownPlainText.render("**已完成**：`a_b`\n\n```swift\nlet a_b = 2 ** 3\n```")
    t.expect(plain.contains("已完成：a_b") && plain.contains("let a_b = 2 ** 3") && !plain.contains("```"), "conversation: plain copy preserves literal code")
    for block in TurnPresentation.compactBlocks([.commandExecution(.init(id: "stale", command: "echo done", status: .running, startedAt: Date()))]) {
        if case .activity(let activity) = block {
            t.expect(!ConversationPresentation.activityTitle(activity, running: false).contains("进行中"), "conversation: settled turn cannot display stale running tools")
        }
    }
    live.status = .completed
    for phase in ["analysis", " Commentary "] {
        live.assistantPhases = ["a": phase]
        t.expect(TurnResponsePresentation(live).messages.isEmpty, "conversation: typed non-final content never becomes result")
    }
    t.expectEqual(MarkdownPlainText.render("[文档](https://example.com)"), "文档", "conversation: plain copy keeps link title")
    let mixed = MarkdownLite.parse("- 要点\n1. 步骤\n- [x] 已核对")
    t.expectEqual(mixed, [.bulletList(items: [[.text("要点")]], depths: [0]), .numberedList(items: [[.text("步骤")]], depths: [0]), .taskList([.init(checked: true, content: [.text("已核对")])])], "conversation: mixed list types keep their own markers")
}
