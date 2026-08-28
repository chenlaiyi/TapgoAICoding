// TapgoTests/TurnMarkdownTests.swift
import Foundation
import TapgoCore

@MainActor
func runTurnMarkdown(_ t: TestRunner) {
    let turn = Turn(
        id: "t", userInput: "hello",
        items: [
            .userMessage(id: "u", text: "hello"),
            .assistantMessage(id: "a", text: "hi **there**"),
            .assistantMessage(id: "app-progress-command-start-c", text: "步骤开始：正在执行命令"),
            .assistantMessage(id: "app-progress-command-c", text: "步骤完成：命令执行成功"),
            .commandExecution(CommandExecution(id: "c", command: "ls", status: .succeeded, stdout: "a\n", exitCode: 0, startedAt: Date())),
            .fileChange(FileChange(id: "f", kind: .update, path: "/x")),
            .error(id: "e", message: "boom"),
        ],
        status: .completed, startedAt: Date(), completedAt: Date()
    )
    let md = TurnMarkdown.render(turn)
    t.expect(md.contains("**用户**: hello"), "md: user")
    t.expect(md.contains("hi **there**"), "md: assistant passes through")
    t.expect(!md.contains("步骤开始"), "md: legacy routine start progress is omitted")
    t.expect(!md.contains("步骤完成"), "md: legacy routine completion progress is omitted")
    t.expectEqual(turn.items[2].searchableText, "", "search: legacy routine progress is omitted")
    t.expect(md.contains("$ ls"), "md: command")
    t.expect(md.contains("```sh"), "md: code fence")
    t.expect(md.contains("**update**: /x"), "md: file change")
    t.expect(md.contains("**错误**: boom"), "md: error")
}
