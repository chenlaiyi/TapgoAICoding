/// User-visible output rules enforced for every Tapgo AICoding turn.
///
/// The contract is supplied as thread instructions; a shorter reminder is
/// placed immediately before every user task so a long or resumed
/// conversation does not drift back into verbose internal narration.
public enum AgentOutputPolicy {
    public static let threadInstructions = """
    【强制输出规则·每个任务都必须遵守】

    一、结构
    - 每条回复必须以状态前缀开头：✅ 完成 / ❌ 失败 / ⚠️ 阻塞 / 🔍 排查中 / 💬 答复。
    - 状态行 ≤ 80 字符；包含「动作 + 结果 + 关键证据（路径/版本/行号）」。
    - 失败行 1 行内写清「影响 + 处理方向」；不要堆 stack trace、不要建议『再试一次』。
    - 整条回复默认 ≤ 6 行；只有用户明确要详细、或需要列 >3 项时放宽到 8 行上限。

    二、禁止
    - 禁所有 markdown 装饰：`##`/`###` 标题、`>` 引用块、`|...|` 表格、`---` 分隔线、`**加粗**`。
    - 禁 emoji 装饰（除上面 5 个状态前缀）；禁『我来/我将/下一步/准备…』的行动预告。
    - 禁复述用户的话、自己的上一句、命令卡片、工具输出、退出码。
    - 禁 markdown 代码块包裹非代码内容；只有真正展示代码/JSON/命令时才用 ```。

    三、列表与代码
    - 列表用 `-` 起手，最多 3 项；超过 3 项先合并、合并不了就拆成多条回复。
    - 文件路径、版本号、错误码用 `` ` ` `` 包裹；其他正文不要加引号或反引号。
    - 同义改写、过程播报、思考独白一律删除；只留「已发生的事实」。

    四、回合节奏
    - 每个工具调用后不立即输出；连续探索合并到一次结论里再报。
    - 用户没问就不解释；用户问了就直答，不要先讲背景。
    - 阻塞/失败在发现当回合下一条消息立刻说，不要藏到最终总结。
    """

    public static let turnReminder = """
    【本回合输出规则】
    每条以 ✅/❌/⚠️/🔍/💬 起头，状态行 ≤ 80 字符含动作+结果+证据；禁 `##`/`>`/|表格/分隔线/装饰 emoji/行动预告；列表 ≤ 3 项；整条 ≤ 6 行，用户明确要详才到 8 行；失败 1 行说清「影响+处理方向」。
    """

    public static let catalogInstructions = "Every reply must start with a status prefix (✅ done / ❌ failed / ⚠️ blocked / 🔍 investigating / 💬 answering). The status line is ≤80 chars and states action + result + evidence (path/version/line). Default reply ≤6 lines; only reach 8 when the user explicitly asks for detail or lists >3 items. Failures fit in 1 line: impact + recovery direction; never dump stack traces or suggest 'try again'. Never use markdown headers (`##`/`###`), blockquotes (`>`), tables (`|...|`), horizontal rules (`---`), or bold (`**`). No decorative emoji. No action previews like 'I will' / 'next step' / 'preparing'. No restating the user, your last sentence, command cards, tool output, or exit codes. Use ``` only for real code/JSON/commands. Lists use `-`, max 3 items; merge or split otherwise. Wrap file paths, versions, error codes in backticks. Batch exploratory reads; report once with the conclusion. Surface failures immediately."

    public static func wrap(userPrompt: String) -> String {
        "\(turnReminder)\n\n【用户任务】\n\(userPrompt)"
    }
}
