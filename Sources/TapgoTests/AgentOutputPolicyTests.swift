import TapgoCore

func runAgentOutputPolicyContract(_ t: TestRunner) {
    let full = AgentOutputPolicy.threadInstructions

    // Answer-first structure without the old status-wall convention.
    t.expect(full.contains("直接以最重要的结果开头"), "leads with the outcome")
    t.expect(full.contains("不强制状态前缀"), "does not force status prefixes")
    t.expect(full.contains("结论、证据、发布状态分开"), "separates result, evidence, and deployment")
    t.expect(full.contains("影响 + 处理方向"), "failures include impact and recovery")

    // Markdown is used deliberately to create the hierarchy rendered by the UI.
    t.expect(full.contains("1–3 个自然段"), "short answers use natural paragraphs")
    t.expect(full.contains("简短 `##` 标题"), "allows short headings for multi-topic answers")
    t.expect(full.contains("通常 3–5 项"), "keeps lists bounded but useful")
    t.expect(full.contains("比较或字段映射才用表格"), "tables are reserved for structured comparisons")
    t.expect(full.contains("`**加粗**`"), "allows restrained subhead emphasis")

    // Noise controls remain strict.
    t.expect(full.contains("装饰性 emoji"), "bans decorative emoji")
    t.expect(full.contains("行动预告"), "bans future-tense previews")
    t.expect(full.contains("复述用户"), "bans restating the user")
    t.expect(full.contains("命令卡片"), "bans restating command cards")
    t.expect(full.contains("连续探索合并"), "batches exploration")
    t.expect(full.contains("下一条消息立即说"), "reports failures in the next message")

    // wrap(userPrompt:) contract
    let wrapped = AgentOutputPolicy.wrap(userPrompt: "检查仓库")
    t.expect(wrapped.hasPrefix("【本回合输出规则】"), "turn reminder precedes the task")
    t.expect(wrapped.contains("【用户任务】\n检查仓库"), "original user task is preserved")
    t.expect((wrapped.range(of: "【本回合输出规则】")?.lowerBound ?? wrapped.endIndex) <
             (wrapped.range(of: "【用户任务】")?.lowerBound ?? wrapped.startIndex),
             "output protocol has higher recency than the task body")
    t.expect(wrapped.contains("不强制状态前缀"), "turn reminder keeps answer-first style")

    // Catalog must echo the same English contract
    let catalog = AgentOutputPolicy.catalogInstructions
    t.expect(catalog.contains("do not require a status prefix"), "catalog removes mandatory status prefix")
    t.expect(catalog.contains("1-3 natural paragraphs"), "catalog uses natural short paragraphs")
    t.expect(catalog.contains("short `##` headings"), "catalog allows useful headings")
    t.expect(catalog.contains("impact + recovery direction"), "catalog requires impact+recovery")
    t.expect(catalog.contains("Never use decorative emoji"), "catalog bans decorative emoji")
    t.expect(catalog.contains("action-preview filler"), "catalog bans action preview filler")
    t.expect(catalog.contains("normally 3-5 items"), "catalog bounds lists")
    t.expect(catalog.contains("backticks"), "catalog requires backticks for technical identifiers")
    t.expect(catalog.contains("surface them immediately"), "catalog requires immediate failure reporting")

    // Length budget: thread instructions should not bloat (was ~2.4kB, cap at 4kB)
    t.expect(full.utf8.count <= 4096, "thread instructions stay under 4KB")
    t.expect(AgentOutputPolicy.turnReminder.utf8.count <= 512, "turn reminder stays under 512B")
}
