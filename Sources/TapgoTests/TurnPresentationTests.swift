import Foundation
import TapgoCore

@MainActor
func runTurnPresentationTests(_ t: TestRunner) {
    let readCommand = CommandExecution(
        id: "cmd-read",
        command: "head SettingsView.swift",
        status: .succeeded,
        stdout: "old",
        exitCode: 0,
        startedAt: Date()
    )
    let buildCommand = CommandExecution(
        id: "cmd-build",
        command: "swift build",
        status: .running,
        startedAt: Date()
    )

    // ZCode-style transcript: every event keeps its own quiet row with the
    // concrete command; prose messages do not collapse the rows around them.
    let blocks = TurnPresentation.compactBlocks([
        .userMessage(id: "user", text: "修复"),
        .reasoning(id: "think-1", text: "先读文件"),
        .commandExecution(readCommand),
        .reasoning(id: "think-2", text: "已经找到原因"),
        .commandExecution(buildCommand),
        .assistantMessage(id: "milestone", text: "修跨模块依赖问题"),
    ])
    t.expectEqual(blocks.count, 6, "each event is its own row; milestone stays a separate item block")
    if case .activity(let reasoningRow) = blocks[1] {
        let display = TurnPresentation.activityDisplay(for: reasoningRow, turnIsRunning: false)
        t.expectEqual(display.text, "思考", "completed reasoning reads as a plain 思考 row")
    } else {
        t.expect(false, "second block is reasoning")
    }
    if case .activity(let commandRow) = blocks[2] {
        let display = TurnPresentation.activityDisplay(for: commandRow, turnIsRunning: false)
        t.expectEqual(display.text, "终端 · head SettingsView.swift", "terminal row shows the concrete command")
    } else {
        t.expect(false, "third block is command")
    }

    let runningBuild = TurnPresentation.activityDisplay(for: .commandExecution(buildCommand))
    t.expectEqual(runningBuild.text, "终端 · swift build", "running terminal row shows the live command")

    // Consecutive search-like tool calls group into one 查阅 row with counts.
    let searchOne = ToolCall(id: "s-1", name: "web_search", arguments: "{}", status: .succeeded)
    let searchTwo = ToolCall(id: "s-2", name: "grep", arguments: "{}", status: .succeeded)
    let searchGroup = TurnPresentation.compactBlocks([
        .toolCall(searchOne),
        .toolCall(searchTwo),
        .assistantMessage(id: "after-search", text: "搜索完成"),
    ])
    t.expectEqual(searchGroup.count, 2, "consecutive searches group into one 查阅 row")
    if case .activity(let group) = searchGroup[0] {
        let display = TurnPresentation.activityDisplay(for: group, turnIsRunning: false)
        t.expectEqual(display.text, "查阅 · 2 搜索", "search group carries per-category counts")
    } else {
        t.expect(false, "search group becomes one activity row")
    }

    let contextCompaction = ToolCall(
        id: "compact-1",
        name: "上下文压缩",
        arguments: "",
        result: "上下文压缩完成",
        status: .succeeded
    )
    let compactBlocks = TurnPresentation.compactBlocks([
        .toolCall(contextCompaction),
        .assistantMessage(id: "after-compact", text: "继续处理"),
    ])
    if case .activity(let compact) = compactBlocks[0] {
        let display = TurnPresentation.activityDisplay(for: compact, turnIsRunning: false)
        t.expectEqual(display.text, "上下文已自动压缩", "context compaction has dedicated completed wording")
        t.expectEqual(display.kind, .compaction, "context compaction has its own semantic category")
    } else {
        t.expect(false, "context compaction becomes an activity row")
    }

    let command = CommandExecution(
        id: "cmd-run",
        command: "git status --short",
        status: .failed,
        stderr: "error",
        startedAt: Date()
    )
    let failedBlocks = TurnPresentation.compactBlocks([
        .commandExecution(command),
        .assistantMessage(id: "failed-done", text: "检查完成"),
    ])
    if case .activity(let failedRow) = failedBlocks[0] {
        let display = TurnPresentation.activityDisplay(for: failedRow, turnIsRunning: false)
        t.expect(display.text.contains("终端 · git status --short"), "failed terminal row still shows the command")
        t.expect(display.text.contains("执行失败"), "failed terminal row carries the failure suffix")
        t.expect(display.isFailure, "failed row is marked as failure")
    } else {
        t.expect(false, "failed command becomes a terminal row")
    }

    let file1 = FileChange(id: "file-1", kind: .update, path: "A.swift", status: .applied)
    let file2 = FileChange(id: "file-2", kind: .update, path: "B.swift", status: .applied)
    let files = TurnPresentation.compactBlocks([
        .reasoning(id: "think", text: "修改"),
        .fileChange(file1),
        .fileChange(file2),
    ])
    t.expectEqual(files.count, 2, "file changes remain a separate user-relevant batch")
    if case .fileBatch(let batch) = files[1] {
        t.expectEqual(batch.count, 2, "consecutive file changes still merge")
    } else {
        t.expect(false, "file batch remains visible")
    }

    let searchCommand = CommandExecution(
        id: "search", command: "rg -n foo Sources", status: .running, startedAt: Date()
    )
    let search = TurnPresentation.activityDisplay(for: .commandExecution(searchCommand))
    t.expectEqual(search.kind, .command, "rg stays a terminal command row")
    t.expectEqual(search.text, "终端 · rg -n foo Sources", "terminal search shows the concrete command")

    let reasoning = TurnPresentation.activityDisplay(
        for: .reasoning(id: "reasoning", text: "分析中\nInvestigating editor refresh")
    )
    t.expectEqual(reasoning.text, "思考", "a plain reasoning read shows the quiet label")
    t.expectEqual(reasoning.summaryText, "分析中\nInvestigating editor refresh", "single reasoning still carries summary text for expansion")

    // 多段连续 reasoning 合并为一个 rollup，渲染成 "思考过程 · N 字符"。
    let multiReasoning = TurnPresentation.compactBlocks([
        .userMessage(id: "u", text: "修复"),
        .reasoning(id: "r1", text: "先看 SettingsView 的字体逻辑"),
        .reasoning(id: "r2", text: "然后看 MarkdownMessageView 的 block 间距"),
        .reasoningSummary(id: "r3", text: "结论: 段落 lineSpacing 从 3 → 2.5"),
        .assistantMessage(id: "m", text: "改完了"),
    ])
    t.expectEqual(multiReasoning.count, 3, "user + grouped reasoning + assistant = 3 blocks")
    if case .activity(let rollup) = multiReasoning[1] {
        let display = TurnPresentation.activityDisplay(for: rollup, turnIsRunning: false)
        t.expect(display.text.contains("思考过程"), "folded reasoning shows 思考过程 label")
        t.expect(display.text.contains("字符"), "folded reasoning carries character count")
        t.expectNotNil(display.summaryText, "folded reasoning exposes joined text")
        if let joined = display.summaryText {
            t.expect(joined.contains("先看 SettingsView"), "joined text preserves the first reasoning body")
            t.expect(joined.contains("结论"), "joined text preserves the summary body")
        }
        t.expectEqual(rollup.events.count, 3, "rollup aggregates exactly the three reasoning events")
    } else {
        t.expect(false, "second block is a reasoning rollup")
    }

    // 同理: reasoning 紧跟一条 commandExecution 必须断开合并，每段都各自成单事件活动。
    let interruptedReasoning = TurnPresentation.compactBlocks([
        .reasoning(id: "r1", text: "看代码"),
        .commandExecution(CommandExecution(
            id: "c1", command: "rg foo", status: .succeeded, startedAt: Date()
        )),
        .reasoning(id: "r2", text: "执行后"),
    ])
    t.expectEqual(interruptedReasoning.count, 3, "r1 / cmd / r2 are three independent activity rollups")
    if case .activity(let reasoningOnly) = interruptedReasoning[0] {
        t.expectEqual(reasoningOnly.events.count, 1, "first reasoning stays a single-event rollup")
    } else {
        t.expect(false, "first block is reasoning")
    }
    if case .activity(let commandRollup) = interruptedReasoning[1] {
        let display = TurnPresentation.activityDisplay(for: commandRollup, turnIsRunning: false)
        t.expect(display.text.contains("终端 · rg foo"), "commandExecution between reasonings stays its own row")
    } else {
        t.expect(false, "second block is the commandExecution rollup")
    }
    if case .activity(let trailingReasoning) = interruptedReasoning[2] {
        t.expectEqual(trailingReasoning.events.count, 1, "r2 stays a single-event rollup after the command")
    } else {
        t.expect(false, "third block is a reasoning rollup")
    }
}
