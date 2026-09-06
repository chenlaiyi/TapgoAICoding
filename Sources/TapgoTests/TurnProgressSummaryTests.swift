import Foundation
import TapgoCore

func runTurnProgressSummaryTests(_ t: TestRunner) {
    let plan = ToolCall(
        id: "plan-turn-1",
        name: "执行计划",
        arguments: "",
        result: "先核对，再实现\n✓ 核对现有实现\n→ 实现步骤进度\n○ 补充测试\n○ 三机安装",
        status: .running
    )
    let diff = """
    diff --git a/A.swift b/A.swift
    --- a/A.swift
    +++ b/A.swift
    @@ -1,2 +1,3 @@
     keep
    -old
    +new
    +extra
    diff --git a/B.swift b/B.swift
    --- a/B.swift
    +++ b/B.swift
    @@ -1 +1 @@
    -before
    +after
    """
    let aggregate = FileChange(
        id: "diff-turn-1",
        kind: .update,
        path: "本轮聚合变更",
        diff: diff,
        status: .applied
    )
    let turn = Turn(
        id: "turn-1",
        userInput: "实现进度",
        items: [.toolCall(plan), .fileChange(aggregate)],
        status: .running,
        startedAt: Date()
    )

    guard let summary = TurnProgressSummary(turn: turn) else {
        t.expect(false, "plan snapshot creates a progress summary")
        return
    }
    t.expectEqual(summary.steps.count, 4, "all plan steps are retained")
    t.expectEqual(summary.currentStepNumber, 2, "in-progress step drives the current number")
    t.expectEqual(summary.completedSteps, 1, "completed steps are counted")
    t.expectEqual(summary.changedFiles, 2, "aggregate diff counts unique files")
    t.expectEqual(summary.additions, 3, "green additions match diff lines")
    t.expectEqual(summary.deletions, 2, "red deletions match diff lines")

    t.expectEqual(summary.statusText(for: .completed), "已结束 · 仍有未完成项", "finished turn does not falsely complete its plan")
    t.expectEqual(summary.statusText(for: .interrupted), "已暂停", "interrupted plan remains reviewable as paused")
    t.expectEqual(summary.statusText(for: .awaitingApproval), "待批准", "approval wait is not rendered as active work")
    t.expectEqual(summary.stepStatusText(summary.steps[1], turnStatus: .failed), "未完成", "failed turn cannot keep showing a running step")
    t.expectEqual(summary.stepStatusText(summary.steps[0], turnStatus: .failed), "已完成", "earlier completed steps survive later failure")
    let donePlan = ToolCall(id: "plan-done", name: "执行计划", arguments: "", result: "✓ 完成实现\n✓ 完成检查", status: .succeeded)
    if let done = TurnProgressSummary(id: "done", items: [.toolCall(donePlan)]) {
        t.expectEqual(done.statusText(for: .completed), "已完成", "all steps explicitly done yields completed plan")
    } else { t.expect(false, "completed plan remains available") }

    let blocks = TurnPresentation.compactBlocks(turn.items)
    t.expectEqual(blocks.count, 0, "plan and aggregate diff snapshots stay out of transcript rows")

    let noPlan = Turn(
        id: "turn-2",
        userInput: "普通任务",
        items: [.fileChange(aggregate)],
        status: .running,
        startedAt: Date()
    )
    t.expectNil(TurnProgressSummary(turn: noPlan), "no plan means no step-progress chip")

    let fallback = ToolCall(
        id: "worktree-stats-turn-3",
        name: "本轮变更统计",
        arguments: "",
        result: "files=1\nadditions=3\ndeletions=0",
        status: .running
    )
    let fallbackTurn = Turn(
        id: "turn-3",
        userInput: "仅 exec_command 的任务",
        items: [.toolCall(plan), .toolCall(fallback)],
        status: .running,
        startedAt: Date()
    )
    let fallbackSummary = TurnProgressSummary(turn: fallbackTurn)
    t.expectEqual(fallbackSummary?.changedFiles, 1, "worktree fallback counts current-turn files")
    t.expectEqual(fallbackSummary?.additions, 3, "worktree fallback supplies green additions")
    t.expectEqual(fallbackSummary?.deletions, 0, "worktree fallback supplies red deletions")
    t.expectEqual(
        TurnPresentation.compactBlocks(fallbackTurn.items).count,
        0,
        "worktree statistics stay out of transcript rows"
    )
}
