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

    let blocks = TurnPresentation.compactBlocks([
        .userMessage(id: "user", text: "修复"),
        .reasoning(id: "think-1", text: "先读文件"),
        .commandExecution(readCommand),
        .reasoning(id: "think-2", text: "已经找到原因"),
        .commandExecution(buildCommand),
        .assistantMessage(id: "milestone", text: "修跨模块依赖问题"),
    ])

    t.expectEqual(blocks.count, 3, "activity before a milestone collapses to one block")
    if case .activity(let activity) = blocks[1] {
        t.expectEqual(activity.latest.id, "cmd-build", "only the latest live activity remains visible")
        t.expect(!activity.isTail, "activity before a key message is a closed segment")
        let display = TurnPresentation.activityDisplay(for: activity, turnIsRunning: true)
        t.expectEqual(display.text, "已读取文件并构建了 App", "closed segment keeps categorized completed summary")
        t.expect(!display.isRunning, "closed segment no longer looks active")
    } else {
        t.expect(false, "middle block is compact activity")
    }

    let segmented = TurnPresentation.compactBlocks([
        .reasoning(id: "think-a", text: "A"),
        .commandExecution(readCommand),
        .assistantMessage(id: "progress", text: "关键进度"),
        .reasoning(id: "think-b", text: "B"),
        .commandExecution(buildCommand),
    ])
    t.expectEqual(segmented.count, 3, "a visible progress message starts a new activity segment")
    if case .activity(let first) = segmented[0],
       case .activity(let second) = segmented[2] {
        t.expectEqual(first.latest.id, "cmd-read", "first segment keeps its final event")
        t.expectEqual(second.latest.id, "cmd-build", "second segment rolls independently")
        t.expect(!first.isTail, "first segment is closed")
        t.expect(second.isTail, "last activity segment is the live tail")
        let live = TurnPresentation.activityDisplay(for: second, turnIsRunning: true)
        t.expectEqual(live.text, "正在构建 App", "live tail updates in place")
        let completed = TurnPresentation.activityDisplay(for: second, turnIsRunning: false)
        t.expectEqual(completed.text, "构建了 App", "completed turn changes tail to past tense")
    } else {
        t.expect(false, "activity remains on both sides of the milestone")
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
        t.expect(false, "context compaction becomes an activity summary")
    }

    let skillCommand = CommandExecution(
        id: "skill-read",
        command: "sed -n '1,200p' /tmp/product-design/skills/image-to-code/SKILL.md",
        status: .succeeded,
        startedAt: Date()
    )
    let skillBlocks = TurnPresentation.compactBlocks([
        .commandExecution(skillCommand),
        .assistantMessage(id: "skill-done", text: "已理解截图规范"),
    ])
    if case .activity(let skill) = skillBlocks[0] {
        let display = TurnPresentation.activityDisplay(for: skill, turnIsRunning: false)
        t.expectEqual(display.text, "已读取 Image to Code 技能", "skill path becomes a safe skill label")
        t.expect(!display.text.contains("/tmp/"), "skill summary does not expose its source path")
    } else {
        t.expect(false, "skill read becomes an activity summary")
    }

    let command = CommandExecution(
        id: "cmd-run",
        command: "git status --short",
        status: .succeeded,
        startedAt: Date()
    )
    let combined = TurnPresentation.compactBlocks([
        .commandExecution(readCommand),
        .commandExecution(command),
        .assistantMessage(id: "combined-done", text: "检查完成"),
    ])
    if case .activity(let rollup) = combined[0] {
        let display = TurnPresentation.activityDisplay(for: rollup, turnIsRunning: false)
        t.expectEqual(display.text, "已读取文件并运行了命令", "multiple tool categories compose one gray summary")
        t.expect(!display.text.contains("git status"), "combined summary hides raw command arguments")
    } else {
        t.expect(false, "combined read and command become one activity summary")
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

    let read = TurnPresentation.activityDisplay(for: .commandExecution(readCommand))
    t.expectEqual(read.kind, .read, "head command is recognized as reading")
    t.expectEqual(read.text, "已读取文件", "completed read uses quiet past tense")

    let searchCommand = CommandExecution(
        id: "search", command: "rg -n foo Sources", status: .running, startedAt: Date()
    )
    let search = TurnPresentation.activityDisplay(for: .commandExecution(searchCommand))
    t.expectEqual(search.kind, .search, "rg command is recognized as search")
    t.expectEqual(search.text, "正在搜索文件", "running search hides raw command")

    let reasoning = TurnPresentation.activityDisplay(
        for: .reasoning(id: "reasoning", text: "分析中\nInvestigating editor refresh")
    )
    t.expectEqual(reasoning.text, "Investigating editor refresh", "latest reasoning line becomes gray activity")
}
