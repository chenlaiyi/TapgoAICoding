/// The user-visible execution cadence enforced for every Tapgo AICoding turn.
///
/// This lives in TapgoCore so the contract is testable without compiling the
/// SwiftUI app target. The full contract is supplied as thread instructions;
/// a shorter reminder is also placed immediately before every user task so a
/// long or resumed conversation cannot dilute it.
public enum AgentOutputPolicy {
    public static let threadInstructions = """
    【强制输出节奏·每个任务都必须遵守】
    - 收到可执行任务后先实际行动，不要只复述需求、一次性列完整计划或追问“下一步”。
    - 每完成一个有意义步骤（例如状态检查、文件读取、代码修改、测试、构建、安装或真实验证），立即输出 1–3 行进度：刚完成什么、关键结果是什么、接下来做什么。
    - 不要把多个已经完成的步骤攒到最终回复里一次性吐出；步骤完成时就报告。不要为每条琐碎命令刷屏，只报告有验证价值的节点。
    - 任何失败、异常或阻塞必须在发现后的下一条消息立即说明，并写清影响和处理方向；不得继续沉默执行后藏在最终总结里。
    - 最终回复只收口结果、验证证据和仍存在的风险，不重复整段过程。简单的一步问答可以直接简短回答。
    """

    public static let turnReminder = """
    【本回合强制输出协议】
    每完成一个有意义步骤，立即用 1–3 行报告结果和下一步；不要攒到最终一次性输出。失败或异常发现后立即报告，不得藏在末尾。
    """

    public static let catalogInstructions = "Every actionable task must use incremental user-visible progress. After each meaningful completed step such as inspection, edit, test, build, install, or live verification, immediately emit 1-3 concise lines stating the result and next action. Never accumulate completed-step updates for one final dump. Report every failure or blocker immediately with its impact and recovery direction. Do not spam trivial commands. Keep the final response to outcome, evidence, and remaining risks."

    public static func wrap(userPrompt: String) -> String {
        "\(turnReminder)\n\n【用户任务】\n\(userPrompt)"
    }

    /// App-generated progress makes the cadence observable even when a model
    /// batches tool calls or forgets to emit an intermediate agent message.
    /// Tool output stays in its native card; repeating arbitrary stdout here
    /// could accidentally surface secrets and would make the update noisy.
    public static func commandStarted() -> String {
        "步骤开始：正在执行命令，命令详情和实时状态已显示在下方卡片。\n命令结束后会立即报告结果；失败不会等到最终回复。"
    }

    public static func commandProgress(exitCode: Int32?, status: String) -> String {
        let failed = status == "failed" || status == "declined" || (exitCode != nil && exitCode != 0)
        let code = exitCode.map(String.init) ?? "未知"
        if failed {
            return "异常：命令步骤失败（退出码 \(code)），详情已显示在上方命令卡片。\n已立即反馈；继续前先处理该失败，或明确说明它是预期验证结果。"
        }
        return "步骤完成：命令执行成功（退出码 \(code)），关键输出已显示在上方命令卡片。\n继续处理下一项检查、修改或验证。"
    }

    public static func toolProgress(name: String, failed: Bool) -> String {
        if failed {
            return "异常：工具 \(name) 执行失败，详情已显示在上方工具卡片。\n已立即反馈；继续前先处理失败或说明阻塞。"
        }
        return "步骤完成：工具 \(name) 执行成功，结果已显示在上方工具卡片。\n继续处理下一项检查、修改或验证。"
    }

    public static func toolStarted(name: String) -> String {
        "步骤开始：正在调用工具 \(name)，实时状态已显示在下方卡片。\n工具结束后会立即报告结果；失败不会等到最终回复。"
    }

    public static func fileProgress(changeCount: Int) -> String {
        "步骤完成：已应用 \(changeCount) 项文件变更，具体路径和 Diff 已显示在上方。\n继续进行测试、构建或真实验证。"
    }

    public static func immediateError(_ message: String) -> String {
        let summary = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = summary.count > 160 ? String(summary.prefix(157)) + "…" : summary
        return "异常：\(clipped.isEmpty ? "任务执行发生错误" : clipped)\n已立即反馈；正在停止、恢复或寻找替代处理方向。"
    }
}
