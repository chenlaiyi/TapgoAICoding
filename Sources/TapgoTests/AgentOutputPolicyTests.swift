import TapgoCore

func runAgentOutputPolicyContract(_ t: TestRunner) {
    let full = AgentOutputPolicy.threadInstructions

    // Status prefix convention
    t.expect(full.contains("✅ 完成"), "names done status prefix")
    t.expect(full.contains("❌ 失败"), "names failure status prefix")
    t.expect(full.contains("⚠️ 阻塞"), "names blocker status prefix")
    t.expect(full.contains("🔍 排查中"), "names investigating status prefix")
    t.expect(full.contains("💬 答复"), "names answer status prefix")

    // Structure
    t.expect(full.contains("状态行 ≤ 80 字符"), "caps status line at 80 chars")
    t.expect(full.contains("动作 + 结果 + 关键证据"), "status line must carry action+result+evidence")
    t.expect(full.contains("影响 + 处理方向"), "failures must state impact + recovery in one line")
    t.expect(full.contains("≤ 6 行"), "default reply ≤ 6 lines")
    t.expect(full.contains("8 行上限"), "hard cap 8 lines on detail requests")

    // Banned markdown decorations
    t.expect(full.contains("`##`/`###` 标题"), "bans markdown headings")
    t.expect(full.contains("`>` 引用块"), "bans blockquotes")
    t.expect(full.contains("`|...|` 表格"), "bans tables")
    t.expect(full.contains("`---` 分隔线"), "bans horizontal rules")
    t.expect(full.contains("`**加粗**`"), "bans bold")

    // Other bans
    t.expect(full.contains("emoji 装饰"), "bans decorative emoji")
    t.expect(full.contains("行动预告"), "bans future-tense previews")
    t.expect(full.contains("复述用户"), "bans restating the user")
    t.expect(full.contains("命令卡片"), "bans restating command cards")
    t.expect(full.contains("同义改写"), "bans synonymous rewording")

    // Lists and code
    t.expect(full.contains("`-` 起手"), "forces dash lists")
    t.expect(full.contains("最多 3 项"), "caps lists at 3 items")
    t.expect(full.contains("包裹"), "wraps paths/versions/error codes in backticks")

    // Rhythm
    t.expect(full.contains("连续探索合并"), "batches exploration")
    t.expect(full.contains("当回合下一条消息"), "reports failures in the next turn")

    // wrap(userPrompt:) contract
    let wrapped = AgentOutputPolicy.wrap(userPrompt: "检查仓库")
    t.expect(wrapped.hasPrefix("【本回合输出规则】"), "turn reminder precedes the task")
    t.expect(wrapped.contains("【用户任务】\n检查仓库"), "original user task is preserved")
    t.expect((wrapped.range(of: "【本回合输出规则】")?.lowerBound ?? wrapped.endIndex) <
             (wrapped.range(of: "【用户任务】")?.lowerBound ?? wrapped.startIndex),
             "output protocol has higher recency than the task body")
    t.expect(wrapped.contains("✅/❌/⚠️/🔍/💬"), "turn reminder lists the 5 status prefixes")

    // Catalog must echo the same English contract
    let catalog = AgentOutputPolicy.catalogInstructions
    t.expect(catalog.contains("status prefix"), "catalog mandates status prefix")
    t.expect(catalog.contains("≤80 chars"), "catalog caps status line at 80 chars")
    t.expect(catalog.contains("≤6 lines"), "catalog caps default reply at 6 lines")
    t.expect(catalog.contains("impact + recovery direction"), "catalog requires impact+recovery")
    t.expect(catalog.contains("Never use markdown headers"), "catalog bans markdown headers")
    t.expect(catalog.contains("No action previews"), "catalog bans action previews")
    t.expect(catalog.contains("No restating the user"), "catalog bans restating the user")
    t.expect(catalog.contains("max 3 items"), "catalog caps lists at 3 items")
    t.expect(catalog.contains("backticks"), "catalog requires backticks for paths")
    t.expect(catalog.contains("Surface failures immediately"), "catalog requires immediate failure reporting")

    // Length budget: thread instructions should not bloat (was ~2.4kB, cap at 4kB)
    t.expect(full.utf8.count <= 4096, "thread instructions stay under 4KB")
    t.expect(AgentOutputPolicy.turnReminder.utf8.count <= 512, "turn reminder stays under 512B")
}
