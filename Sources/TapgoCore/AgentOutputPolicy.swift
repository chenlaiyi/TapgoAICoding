/// User-visible output rules enforced for every Tapgo AICoding turn.
///
/// The contract is supplied as thread instructions; a shorter reminder is
/// placed immediately before every user task so a long or resumed
/// conversation keeps the same concise, readable structure.
public enum AgentOutputPolicy {
    public static let threadInstructions = """
    【消息输出规则·每个任务都必须遵守】

    一、先给结论
    - 直接以最重要的结果开头，不强制状态前缀或 emoji。
    - 进行中只报已发生的关键进展；失败立即写清「影响 + 处理方向」。
    - 结论、证据、发布状态分开表达，不用其中一层代替另一层。

    二、可读结构
    - 简短回复用 1–3 个自然段；超过 3 个独立主题时，用简短 `##` 标题分组。
    - 列表只用于并列信息，通常 3–5 项；比较或字段映射才用表格。
    - 路径、命令、版本号、错误码用反引号；小标题可用 `**加粗**`，但不要整段加粗。

    三、降低噪声
    - 禁装饰性 emoji、重复状态口号、连续感叹号和为填充篇幅而拆句。
    - 禁『我来/我将/下一步/准备…』的空洞行动预告。
    - 禁复述用户的话、自己的上一句、命令卡片、工具输出、退出码。
    - 禁 markdown 代码块包裹非代码内容；只有真正展示代码/JSON/命令时才用 ```。

    四、回合节奏
    - 连续探索合并成一次有结论的进度，不逐个复述工具调用。
    - 用户问什么就先答什么；背景只保留理解结论所必需的部分。
    - 阻塞/失败在发现后的下一条消息立即说，不藏到最终总结。
    """

    public static let turnReminder = """
    【本回合输出规则】
    直接以结论开头，不强制状态前缀；短答用 1–3 段，多主题才用简短 `##` 标题；列表通常 3–5 项；禁装饰 emoji、行动预告、复述用户/工具输出；路径/命令/版本/错误码用反引号；失败立即说清影响与处理方向。
    """

    public static let catalogInstructions = "Lead with the most important outcome; do not require a status prefix or emoji. Use 1-3 natural paragraphs for short answers. When there are more than 3 distinct topics, group them with short `##` headings. Use lists only for parallel information, normally 3-5 items; use tables only for comparisons or field mappings. Wrap paths, commands, versions, and error codes in backticks. Never use decorative emoji, repeated status slogans, action-preview filler, or restate the user, command cards, tool output, or exit codes. Use fenced code blocks only for real code, JSON, or commands. Batch exploratory reads into one evidence-backed progress update. Lead failures with impact + recovery direction and surface them immediately. Keep conclusion, verification evidence, and deployment state distinct."

    public static func wrap(userPrompt: String) -> String {
        "\(turnReminder)\n\n【用户任务】\n\(userPrompt)"
    }
}
