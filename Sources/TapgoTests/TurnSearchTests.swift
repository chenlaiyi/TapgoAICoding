// TapgoTests/TurnSearchTests.swift
import Foundation
import TapgoCore

/// Tests for the in-conversation search (`Turn.matches(query:)` and
/// `TurnItem.searchableText`). The chat view's "上一处 / 下一处" UI and
/// position counter depend on this contract — if `matches(query:)`
/// drifts from how the user expects "find in conversation" to behave,
/// jump-to-next becomes confusing. These pin the rules so future
/// refactors can't silently change them.

@MainActor
func runTurnSearch(_ t: TestRunner) {
    // Empty / whitespace query never matches.
    let empty = makeTurn(userInput: "hello world", items: [])
    t.expect(!empty.matches(query: ""), "matches: empty query → false")
    t.expect(!empty.matches(query: "   "), "matches: whitespace query → false")

    // Match against userInput (case-insensitive).
    t.expect(makeTurn(userInput: "Fix the auth bug", items: [])
        .matches(query: "auth"), "matches: userInput substring")
    t.expect(makeTurn(userInput: "Fix the AUTH bug", items: [])
        .matches(query: "auth"), "matches: case-insensitive userInput")

    // Match against assistantMessage.
    let turnWithAssistant = makeTurn(userInput: "x", items: [
        .assistantMessage(id: "a", text: "I'll check the database")
    ])
    t.expect(turnWithAssistant.matches(query: "database"),
                 "matches: assistantMessage substring")
    t.expect(!turnWithAssistant.matches(query: "kubernetes"),
                  "no-match: unrelated query")

    // Match against command output (stdout).
    let turnWithCmd = makeTurn(userInput: "list pods", items: [
        .commandExecution(CommandExecution(
            id: "c1", command: "kubectl get pods",
            stdout: "NAME   READY   STATUS\nweb-0  1/1     Running",
            stderr: "", exitCode: 0,
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 1)))
    ])
    t.expect(turnWithCmd.matches(query: "kubectl"),
                 "matches: command in commandExecution.command")
    t.expect(turnWithCmd.matches(query: "Running"),
                 "matches: text in commandExecution.stdout")

    // Match against tool call args + result.
    let turnWithTool = makeTurn(userInput: "y", items: [
        .toolCall(ToolCall(id: "t1", name: "web_search",
                           arguments: "swiftui autocomplete",
                           result: "https://example.com",
                           status: .succeeded))
    ])
    t.expect(turnWithTool.matches(query: "swiftui"),
                 "matches: toolCall.arguments")
    t.expect(turnWithTool.matches(query: "example.com"),
                 "matches: toolCall.result")
    t.expect(!turnWithTool.matches(query: "danger"),
                  "no-match: not in any tool field")

    // Match against file path / diff.
    let turnWithFile = makeTurn(userInput: "z", items: [
        .fileChange(FileChange(id: "f1", kind: .update, path: "/src/Sidebar.swift",
                               diff: "- old line\n+ new line", status: .applied))
    ])
    t.expect(turnWithFile.matches(query: "Sidebar.swift"),
                 "matches: fileChange.path")
    t.expect(turnWithFile.matches(query: "new line"),
                 "matches: fileChange.diff")

    // Match against reasoning text.
    let turnWithReasoning = makeTurn(userInput: "r", items: [
        .reasoning(id: "rs", text: "thinking about the best approach")
    ])
    t.expect(turnWithReasoning.matches(query: "best approach"),
                 "matches: reasoning text")

    // searchableText is the join of all item shapes for highlighting.
    let t1 = TurnItem.toolCall(ToolCall(id: "t", name: "shell",
                                        arguments: "ls -la",
                                        result: "total 4\ndrwx",
                                        status: .succeeded))
    let s = t1.searchableText
    t.expect(s.contains("shell"), "searchableText: tool name")
    t.expect(s.contains("ls -la"), "searchableText: tool args")
    t.expect(s.contains("total 4"), "searchableText: tool result")

    let t2 = TurnItem.commandExecution(CommandExecution(
        id: "c", command: "echo hi", stdout: "hi\n", stderr: "warn!",
        exitCode: 0, startedAt: Date(timeIntervalSince1970: 0),
        completedAt: Date(timeIntervalSince1970: 1)))
    let s2 = t2.searchableText
    t.expect(s2.contains("echo hi"), "searchableText: command")
    t.expect(s2.contains("hi"), "searchableText: stdout")
    t.expect(s2.contains("warn!"), "searchableText: stderr")

    // Turn with no items but a matching userInput still matches.
    let onlyUser = makeTurn(userInput: "search this please", items: [])
    t.expect(onlyUser.matches(query: "search"), "matches: userInput-only turn")

    // Turn with no matching content anywhere.
    let miss = makeTurn(userInput: "foo", items: [
        .assistantMessage(id: "a", text: "bar")
    ])
    t.expect(!miss.matches(query: "baz"), "no-match: not in userInput or items")

    // Whitespace handling: "  auth  " should match "auth".
    let sp = makeTurn(userInput: "Fix the auth bug", items: [])
    t.expect(sp.matches(query: "  auth  "),
                 "matches: leading/trailing whitespace in query")

    // Cyrillic / CJK: search is case-insensitive but still substring.
    let cjk = makeTurn(userInput: "查找中文", items: [
        .assistantMessage(id: "a", text: "处理完成")
    ])
    t.expect(cjk.matches(query: "中文"), "matches: CJK in userInput")
    t.expect(cjk.matches(query: "处理"), "matches: CJK in assistant text")
}

private func makeTurn(userInput: String, items: [TurnItem]) -> Turn {
    Turn(id: "t", userInput: userInput, items: items, status: .completed,
         startedAt: Date(timeIntervalSince1970: 0))
}
