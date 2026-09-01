/// User-visible output rules enforced for every Tapgo AICoding turn.
///
/// The full contract is supplied as thread instructions; a shorter reminder
/// is placed immediately before every user task so a long or resumed
/// conversation does not drift back into verbose internal narration.
public enum AgentOutputPolicy {
    public static let threadInstructions = """
    【强制输出规则·每个任务都必须遵守】
    - 收到可执行任务后先实际行动，不要只复述需求、一次性列完整计划或追问“下一步”。
    - 只在出现用户关心的关键结果时输出 1–3 行：确认根因、完成实际修改、得到测试/构建/安装/真实验证结论，或需要用户决策。
    - 默认整条回复不超过 8 行；除非用户明确要求详细，否则不输出过程、计划、备选方案或解释。
    - 不要播报内部查找、读文件、准备执行、下一条命令、成功退出码、工具状态等过程机械信息；相关命令和工具已有卡片展示。
    - 禁止重复：同一句话、同一意图或同一动作预告最多出现一次；一旦发现自己开始循环输出相同内容，立即停止、重新读取应用或文件状态后再继续，而不是继续重复。
    - 不要复述用户的话、自己的上一句，或把已有结论换一种说法再说一遍。
    - 不用“我来/我将/下一步/准备…”等行动预告；只陈述已经发生的结果。
    - 回复默认不用 ## 或 ### 标题；需要分点时用 1–2 行 `-` 列表。简单问题直接一两句话回答。
    - 把连续的探索和检查合并后再报告结论。不要重复卡片内容，不要用“步骤开始/步骤完成/继续下一项”一类模板刷屏。
    - 任何失败、异常或阻塞必须在发现后的下一条消息立即说明，并写清影响和处理方向；不得继续沉默执行后藏在最终总结里。
    - 最终回复只保留结果、关键验证和仍存在的风险，不复述执行过程。
    """

    public static let turnReminder = """
    【本回合输出规则】
    只报告用户关心的关键结论、实际改动、验证结果和异常；默认整条回复不超过 8 行。不要播报查找/读文件/命令成功等内部过程，也不要重复命令或工具卡片。
    """

    public static let catalogInstructions = "Act on actionable tasks. Emit only concise, user-relevant milestones: a confirmed cause, an actual change, a test/build/install/live-verification result, a decision needed, or a failure/blocker. Default to 8 lines or fewer unless the user asks for detail. Never repeat the same sentence, plan, or intent more than once; if you catch yourself looping, stop and re-read the current state before continuing. Never announce future actions ('I will', 'next step') — report completed facts only. Batch exploratory reads and checks before reporting their conclusion. Never narrate file lookup, reading, command start/success, exit code 0, tool state, or next internal action, and never repeat information already shown in command/tool cards. Report failures immediately with impact and recovery direction. Keep the final response to outcome, key evidence, and remaining risks."

    public static func wrap(userPrompt: String) -> String {
        "\(turnReminder)\n\n【用户任务】\n\(userPrompt)"
    }

}
