import TapgoCore

func runAgentOutputPolicyContract(_ t: TestRunner) {
    let full = AgentOutputPolicy.threadInstructions
    t.expect(full.contains("用户关心的关键结果"), "limits updates to user-relevant milestones")
    t.expect(full.contains("1–3 行"), "keeps milestone updates concise")
    t.expect(full.contains("不超过 8 行"), "caps default reply length")
    t.expect(full.contains("不要播报内部查找"), "suppresses internal exploration narration")
    t.expect(full.contains("不要重复卡片内容"), "does not duplicate native cards")
    t.expect(full.contains("禁止重复"), "bans repeated sentences and intents")
    t.expect(full.contains("循环输出相同内容"), "requires stopping a repetition loop")
    t.expect(full.contains("行动预告"), "bans future-tense action announcements")
    t.expect(full.contains("不用 ## 或 ### 标题"), "avoids markdown headings by default")
    t.expect(full.contains("失败、异常或阻塞"), "covers failures and blockers")
    t.expect(full.contains("立即说明"), "requires immediate failure reporting")

    let wrapped = AgentOutputPolicy.wrap(userPrompt: "检查仓库")
    t.expect(wrapped.hasPrefix("【本回合输出规则】"), "turn reminder precedes the task")
    t.expect(wrapped.contains("【用户任务】\n检查仓库"), "original user task is preserved")
    t.expect((wrapped.range(of: "【本回合输出规则】")?.lowerBound ?? wrapped.endIndex) <
             (wrapped.range(of: "【用户任务】")?.lowerBound ?? wrapped.startIndex),
             "output protocol has higher recency than the task body")

    let catalog = AgentOutputPolicy.catalogInstructions
    t.expect(catalog.contains("user-relevant milestones"), "catalog limits updates to meaningful outcomes")
    t.expect(catalog.contains("8 lines or fewer"), "catalog caps default reply length")
    t.expect(catalog.contains("Never repeat the same sentence"), "catalog bans repetition")
    t.expect(catalog.contains("Never announce future actions"), "catalog bans action announcements")
    t.expect(catalog.contains("Never narrate file lookup"), "catalog suppresses routine mechanics")
    t.expect(catalog.contains("Report failures immediately"), "catalog reports failures immediately")
}
