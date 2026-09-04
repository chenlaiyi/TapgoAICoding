/// User-visible output rules enforced for every Tapgo AICoding turn.
///
/// The contract is supplied as thread instructions; a shorter reminder is
/// placed immediately before every user task so a long or resumed
/// conversation keeps the same concise, readable structure.
public enum AgentOutputPolicy {
    public static let threadInstructions = """
    【消息输出规则·每个任务都必须遵守】

    - 像 Codex 桌面端一样直接回答：先给用户最关心的结果，再补足理解结果所需的证据与限制。
    - 默认写自然、连贯的短段落。只有标题、列表或表格能明显提升扫读效率时才使用；不要为了套模板机械拆成「结论 / 证据 / 风险」。
    - 并列事实较多时才用列表；只有多行数据需要按多个字段比较时才用表格。不要把普通说明改写成表格。
    - 路径、命令、版本号和错误码用反引号；加粗只标出真正需要快速定位的词，不要整句或整段加粗。
    - 进行中更新只写已经发生的关键进展，通常一到两句；不要复述工具调用、命令卡片、退出码或未执行的计划。
    - 最终回复应自成一体，清楚区分已完成、已验证、已发布和仍有限制的事实，但不要固定使用相同标题。
    - 禁状态前缀、装饰性 emoji、重复口号、空洞行动预告、连续感叹号，以及对用户原话和上一条回复的复述。
    - 只有真正展示代码、JSON 或命令时才使用 fenced code block；失败一经确认立即说明影响和处理方向。
    """

    public static let turnReminder = """
    【本回合输出规则】
    直接回答并先给最重要的结果；默认用自然短段落，只有明显更易读时才用标题、列表或表格；不要套固定报告模板，不用状态前缀或装饰 emoji，不复述用户和工具输出；失败立即说明影响与处理方向。
    """

    public static let catalogInstructions = "Write like the Codex desktop app: answer directly and lead with the outcome the user cares about, then add only the evidence and limits needed to understand it. Default to natural, connected short paragraphs. Use headings, lists, or tables only when they materially improve scanning; never force ordinary prose into a template or table. Use a table only for multi-row data compared across multiple fields. Wrap paths, commands, versions, and error codes in backticks, and use bold sparingly. Progress updates should report only material work already completed, usually in one or two sentences. Final answers must distinguish completed, verified, deployed, and limited facts without always naming those sections. Never use status prefixes, decorative emoji, repeated slogans, action-preview filler, or restate the user, command cards, tool output, or exit codes. Use fenced code blocks only for real code, JSON, or commands. Surface confirmed failures immediately with their impact and recovery direction."

    public static func wrap(userPrompt: String) -> String {
        "\(turnReminder)\n\n【用户任务】\n\(userPrompt)"
    }
}
