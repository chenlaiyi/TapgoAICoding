import Foundation
import TapgoCore

@MainActor
func runResponsePresentationTests(_ t: TestRunner) {
    let command = TurnItem.commandExecution(.init(id: "cmd", command: "secret-shaped raw arguments", status: .succeeded, startedAt: Date()))
    var turn = Turn(id: "t", userInput: "修复显示", items: [
        .userMessage(id: "u", text: "修复显示"),
        .assistantMessage(id: "progress", text: "Now inspect the file"),
        .reasoning(id: "r", text: "internal trace"), command,
        .assistantMessage(id: "answer", text: "已完成修复。")
    ], status: .running, startedAt: Date())
    t.expect(TurnResponsePresentation(turn).messages.isEmpty, "phase-less running commentary never leaks into answer")
    t.expectEqual(TurnResponsePresentation(turn).users.count, 1, "user prompt remains visible")
    turn.status = .completed
    t.expectEqual(TurnResponsePresentation(turn).answerText, "已完成修复。", "legacy final answer separated from progress")
    t.expectEqual(TurnResponsePresentation(turn).work.count, 3, "raw work retained for opt-in disclosure")
    t.expectEqual(TurnMarkdown.response(turn), "已完成修复。", "copy only answer")
    t.expect(TurnMarkdown.render(turn).contains("secret-shaped"), "explicit full export still retains execution trace")
    t.expectEqual(PhoneRemote.assistantText(turn), "已完成修复。", "phone shares final answer selection")
    turn.status = .running
    turn.assistantPhases = ["progress": "commentary", "answer": "final_answer"]
    t.expectEqual(TurnResponsePresentation(turn).answerText, "已完成修复。", "explicit final streams while running")
    turn.items += [.error(id: "e", message: "连接失败")]
    t.expectEqual(TurnResponsePresentation(turn).notices.count, 1, "errors stay visible outside process")
    let request = ApprovalRequest(id: "approval", kind: .commandExecution, reason: "请确认", payload: .command(.init(id: "approve-cmd", command: "echo ok", status: .awaitingApproval, startedAt: Date())))
    turn.items += [.approval(request)]
    t.expectEqual(TurnResponsePresentation(turn).notices.count, 2, "approval never hidden by process setting")
    if let data = try? JSONEncoder().encode(turn), let decoded = try? JSONDecoder().decode(Turn.self, from: data) {
        t.expectEqual(decoded.assistantPhases, turn.assistantPhases, "phase survives history round-trip")
        var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        object.removeValue(forKey: "assistantPhases")
        let legacy = try? JSONDecoder().decode(Turn.self, from: JSONSerialization.data(withJSONObject: object))
        t.expectEqual(legacy?.assistantPhases, [:], "old history with no phase field remains readable")
    } else { t.expect(false, "phase round trip") }
    turn.assistantPhases = [:]
    turn.status = .interrupted
    turn.items = [.assistantMessage(id: "p", text: "开始执行"), command]
    t.expect(TurnResponsePresentation(turn).messages.isEmpty, "interrupted pre-tool commentary is not a result")
    turn.status = .completed
    t.expect(TurnResponsePresentation(turn).messages.isEmpty, "no false result when work ends without answer")
    turn.items = [.assistantMessage(id: "p", text: "准备中")]
    turn.assistantPhases = ["p": "commentary"]
    t.expect(TurnResponsePresentation(turn).messages.isEmpty, "explicit commentary never promoted at completion")
    for method in ["item/started", "item/completed"] {
        let event = ExecEventParser.parse(method: method, params: ["item": .object(["id": .string("a"), "type": .string("agentMessage"), "phase": .string("final_answer"), "text": .string("结果")])])
        switch event {
        case .agentMessageStarted(let id, let phase), .agentMessage(let id, _, let phase):
            t.expectEqual(id, "a", "phase event id retained")
            t.expectEqual(phase, "final_answer", "phase parsed at start and completion")
        default: t.expect(false, "phase event parsed")
        }
    }
    let suite = "tapgo-personalization-test-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let initial = ResponsePersonalization(defaults: defaults)
    t.expectEqual(initial.length, .concise, "default concise")
    t.expectEqual(initial.language, .chinese, "default Chinese")
    t.expect(!initial.showWorkProcess, "default quiet mode")
    defaults.set("detailed", forKey: ResponsePersonalization.lengthKey)
    defaults.set("english", forKey: ResponsePersonalization.languageKey)
    defaults.set("professional", forKey: ResponsePersonalization.toneKey)
    defaults.set(String(repeating: "偏好", count: 1200), forKey: ResponsePersonalization.instructionsKey)
    let saved = ResponsePersonalization(defaults: defaults)
    t.expectEqual(saved.instructions.count, 2000, "custom instructions bounded by characters")
    let prompt = AgentOutputPolicy.wrap(userPrompt: "本次用中文", preferences: saved)
    t.expect(prompt.contains("English") && prompt.contains("专业") && prompt.contains("完整步骤"), "saved preferences reach actual turn wrapper")
    t.expect(prompt.hasSuffix("【用户任务】\n本次用中文"), "current request preserved after preferences")
    t.expect(prompt.contains("关闭显示工作过程"), "quiet preference reaches model for resumed and new turns")
    defaults.set("invalid", forKey: ResponsePersonalization.lengthKey)
    t.expectEqual(ResponsePersonalization(defaults: defaults).length, .concise, "unknown stored value safely defaults")
}
