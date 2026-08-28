import TapgoCore

@MainActor
func runTurnSteerPayloadTests(_ t: TestRunner) {
    do {
        let payload = try TurnSteerPayload.make(
            threadId: "thread-1",
            expectedTurnId: "turn-9",
            text: "调整实现方向",
            imagePaths: ["/tmp/reference.png"]
        )
        t.expectEqual(payload["threadId"], .string("thread-1"), "thread id is preserved")
        t.expectEqual(payload["expectedTurnId"], .string("turn-9"), "active turn precondition is preserved")
        let input = payload["input"]?.arrayValue ?? []
        t.expectEqual(input.count, 2, "text and image are both included")
        t.expectEqual(input.first?.objectValue?["type"], .string("text"), "text input comes first")
        t.expectEqual(input.first?.objectValue?["text"], .string("调整实现方向"), "text is preserved")
        t.expectEqual(input.last?.objectValue?["type"], .string("localImage"), "image uses localImage protocol type")
        t.expectEqual(input.last?.objectValue?["path"], .string("/tmp/reference.png"), "image path is preserved")
    } catch {
        t.expect(false, "valid steering payload does not throw: \(error)")
    }

    t.expectThrows({
        _ = try TurnSteerPayload.make(threadId: "", expectedTurnId: "turn", text: "方向")
    }, "missing thread id is rejected")
    t.expectThrows({
        _ = try TurnSteerPayload.make(threadId: "thread", expectedTurnId: "", text: "方向")
    }, "missing turn id is rejected")
    t.expectThrows({
        _ = try TurnSteerPayload.make(threadId: "thread", expectedTurnId: "turn", text: "   ")
    }, "empty text and images are rejected")
}
