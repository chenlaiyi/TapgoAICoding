// TapgoTests/TrajectoryFilterTests.swift
import Foundation
import TapgoCore

@MainActor
func runTrajectoryFilter(_ t: TestRunner) {
    let cmd = TurnItem.commandExecution(CommandExecution(id: "c", command: "ls", startedAt: Date()))
    let fc = TurnItem.fileChange(FileChange(id: "f", kind: .update, path: "/a"))
    let err = TurnItem.error(id: "e", message: "boom")
    let tool = TurnItem.toolCall(ToolCall(id: "t", name: "apply_patch", arguments: "{}", status: .succeeded))
    let assistant = TurnItem.assistantMessage(id: "a", text: "hi")

    t.expect(TrajectoryFilter.matches(item: cmd, filter: .all), "all: matches command")
    t.expect(TrajectoryFilter.matches(item: cmd, filter: .commands), "commands: matches command")
    t.expect(!TrajectoryFilter.matches(item: cmd, filter: .files), "commands: not files")
    t.expect(TrajectoryFilter.matches(item: fc, filter: .files), "files: matches file")
    t.expect(!TrajectoryFilter.matches(item: fc, filter: .errors), "files: not errors")
    t.expect(TrajectoryFilter.matches(item: err, filter: .errors), "errors: matches error")
    t.expect(TrajectoryFilter.matches(item: tool, filter: .tools), "tools: matches tool")
    t.expect(!TrajectoryFilter.matches(item: tool, filter: .files), "tools: not files")
    t.expect(!TrajectoryFilter.matches(item: assistant, filter: .commands), "commands: excludes assistant")
    t.expect(TrajectoryFilter.matches(item: assistant, filter: .all), "all: includes assistant")
}
