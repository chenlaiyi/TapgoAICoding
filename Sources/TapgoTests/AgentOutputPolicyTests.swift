import TapgoCore

func runAgentOutputPolicyContract(_ t: TestRunner) {
    let full = AgentOutputPolicy.threadInstructions

    // Codex-style answer-first prose without a mechanical report template.
    t.expect(full.contains("像 Codex 桌面端一样直接回答"), "targets Codex desktop output")
    t.expect(full.contains("自然、连贯的短段落"), "defaults to connected prose")
    t.expect(full.contains("明显提升扫读效率"), "uses structure only when helpful")
    t.expect(full.contains("不要为了套模板机械拆成"), "rejects mechanical report headings")
    t.expect(full.contains("不要把普通说明改写成表格"), "does not force prose into tables")
    t.expect(full.contains("已完成、已验证、已发布"), "separates delivery facts without fixed headings")

    // Noise controls remain strict.
    t.expect(full.contains("装饰性 emoji"), "bans decorative emoji")
    t.expect(full.contains("行动预告"), "bans future-tense previews")
    t.expect(full.contains("用户原话"), "bans restating the user")
    t.expect(full.contains("命令卡片"), "bans restating command cards")
    t.expect(full.contains("通常一到两句"), "keeps progress updates short")
    t.expect(full.contains("失败一经确认立即说明"), "reports failures immediately")

    // wrap(userPrompt:) contract
    let wrapped = AgentOutputPolicy.wrap(userPrompt: "检查仓库")
    t.expect(wrapped.hasPrefix("【本回合输出规则】"), "turn reminder precedes the task")
    t.expect(wrapped.contains("【用户任务】\n检查仓库"), "original user task is preserved")
    t.expect((wrapped.range(of: "【本回合输出规则】")?.lowerBound ?? wrapped.endIndex) <
             (wrapped.range(of: "【用户任务】")?.lowerBound ?? wrapped.startIndex),
             "output protocol has higher recency than the task body")
    t.expect(wrapped.contains("不用状态前缀"), "turn reminder keeps answer-first style")

    // Catalog must echo the same English contract
    let catalog = AgentOutputPolicy.catalogInstructions
    t.expect(catalog.contains("Write like the Codex desktop app"), "catalog targets Codex desktop")
    t.expect(catalog.contains("natural, connected short paragraphs"), "catalog uses connected prose")
    t.expect(catalog.contains("only when they materially improve scanning"), "catalog avoids forced structure")
    t.expect(catalog.contains("never force ordinary prose into a template or table"), "catalog rejects report templates")
    t.expect(catalog.contains("Never use status prefixes"), "catalog removes mandatory status prefix")
    t.expect(catalog.contains("decorative emoji"), "catalog bans decorative emoji")
    t.expect(catalog.contains("action-preview filler"), "catalog bans action preview filler")
    t.expect(catalog.contains("backticks"), "catalog requires backticks for technical identifiers")
    t.expect(catalog.contains("Surface confirmed failures immediately"), "catalog requires immediate failure reporting")

    // Length budget: thread instructions should not bloat (was ~2.4kB, cap at 4kB)
    t.expect(full.utf8.count <= 4096, "thread instructions stay under 4KB")
    t.expect(AgentOutputPolicy.turnReminder.utf8.count <= 512, "turn reminder stays under 512B")
}
