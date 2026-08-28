import TapgoCore

func runAgentOutputPolicyContract(_ t: TestRunner) {
    let full = AgentOutputPolicy.threadInstructions
    t.expect(full.contains("每完成一个有意义步骤"), "requires progress after every meaningful step")
    t.expect(full.contains("1–3 行"), "limits progress updates to 1-3 lines")
    t.expect(full.contains("不要把多个已经完成的步骤攒到最终回复"), "forbids final progress dump")
    t.expect(full.contains("失败、异常或阻塞"), "covers failures and blockers")
    t.expect(full.contains("立即说明"), "requires immediate failure reporting")
    t.expect(full.contains("不要为每条琐碎命令刷屏"), "avoids noisy command-by-command chatter")

    let wrapped = AgentOutputPolicy.wrap(userPrompt: "检查仓库")
    t.expect(wrapped.hasPrefix("【本回合强制输出协议】"), "turn reminder precedes the task")
    t.expect(wrapped.contains("【用户任务】\n检查仓库"), "original user task is preserved")
    t.expect((wrapped.range(of: "【本回合强制输出协议】")?.lowerBound ?? wrapped.endIndex) <
             (wrapped.range(of: "【用户任务】")?.lowerBound ?? wrapped.startIndex),
             "output protocol has higher recency than the task body")

    let catalog = AgentOutputPolicy.catalogInstructions
    t.expect(catalog.contains("each meaningful completed step"), "catalog requires step completion updates")
    t.expect(catalog.contains("1-3 concise lines"), "catalog preserves concise update size")
    t.expect(catalog.contains("Report every failure or blocker immediately"), "catalog reports failures immediately")

    let commandOK = AgentOutputPolicy.commandProgress(exitCode: 0, status: "completed")
    t.expectEqual(commandOK.split(separator: "\n").count, 2, "command progress is exactly two lines")
    t.expect(commandOK.contains("步骤完成"), "successful command is reported as completed")
    t.expect(commandOK.contains("退出码 0"), "successful command includes exit code")

    let commandFailed = AgentOutputPolicy.commandProgress(exitCode: 7, status: "failed")
    t.expect(commandFailed.contains("异常"), "failed command is reported immediately as abnormal")
    t.expect(commandFailed.contains("退出码 7"), "failed command includes exit code")
    t.expect(AgentOutputPolicy.toolProgress(name: "browser.open", failed: false).contains("browser.open 执行成功"),
             "successful tool progress names the tool")
    t.expect(AgentOutputPolicy.toolProgress(name: "browser.open", failed: true).contains("立即反馈"),
             "failed tool progress is immediate")
    t.expect(AgentOutputPolicy.fileProgress(changeCount: 3).contains("3 项文件变更"),
             "file progress includes change count")
    t.expect(AgentOutputPolicy.immediateError("network down").contains("异常：network down"),
             "transport error is surfaced immediately")
}
