import XCTest

final class MobileAssistantStreamTests: XCTestCase {
    private func start(id: String = "a", revision: Int = 1) -> [String: Any] {
        ["type": "start", "attemptId": id, "revision": revision, "turn": 1, "step": 1, "startedAfterSeq": 2]
    }

    private func chunk(_ text: String, index: Int, revision: Int, block: Int = 0, id: String = "a") -> [String: Any] {
        ["type": "chunk", "attemptId": id, "revision": revision, "index": index,
         "chunk": ["type": "text-delta", "index": block, "text": text]]
    }

    func testDenseChunksKeepUnicodeAndSeparateTextBlocks() {
        var stream = MobileAssistantStream()
        XCTAssertEqual(stream.receive(start()), .updated)
        let first = chunk("你好😊", index: 0, revision: 2)
        XCTAssertEqual(stream.receive(first), .updated)
        XCTAssertEqual(stream.receive(first), .ignored)
        XCTAssertEqual(stream.receive(["type": "chunk", "attemptId": "a", "revision": 3, "index": 1,
                                       "chunk": ["type": "tool-call-delta", "index": 1, "id": "tool", "argumentsDelta": "{}"]]), .updated)
        XCTAssertEqual(stream.receive(chunk("第二段", index: 2, revision: 4, block: 2)), .updated)
        XCTAssertEqual(stream.text, "你好😊\n\n第二段")
        let event: [String: Any] = ["type": "assistant/message", "seq": 10, "surfaceOp": "append", "data": ["turn": 1, "step": 1]]
        XCTAssertTrue(stream.matches(event))
        XCTAssertEqual(stream.receive(["type": "end", "attemptId": "a", "revision": 5, "index": 3,
                                      "outcome": ["kind": "committed", "seq": 10, "eventType": "assistant/message"]]),
                       .committed(sequence: 10, eventType: "assistant/message"))
        XCTAssertEqual(stream.text, "你好😊\n\n第二段")
        stream.retire()
        XCTAssertFalse(stream.active)
        XCTAssertEqual(stream.text, "")
        XCTAssertEqual(stream.revision, 5)
    }

    func testReconnectRestoresCompactPrefixAndRejectsGapsWithoutCorruptingIt() {
        var stream = MobileAssistantStream()
        let baseline: [String: Any] = ["revision": 12, "activeAttempt": [
            "attemptId": "a", "turn": 1, "step": 1, "startedAfterSeq": 2, "nextIndex": 4,
            "stream": [["type": "text-chunks", "index": 0, "texts": ["前缀"]],
                       ["type": "tool-call-chunks", "index": 1, "args": ["{}"]],
                       ["type": "chunk", "chunk": ["type": "block-start", "index": 2]],
                       ["type": "text-chunks", "index": 2, "texts": ["初段"]]]]]
        XCTAssertTrue(stream.restore(baseline))
        XCTAssertTrue(stream.restore(baseline))
        XCTAssertEqual(stream.receive(chunk("续", index: 4, revision: 13, block: 2)), .updated)
        XCTAssertEqual(stream.text, "前缀\n\n初段续")
        XCTAssertEqual(stream.receive(chunk("丢失", index: 6, revision: 14)), .resync)
        XCTAssertEqual(stream.receive(chunk("其他请求", index: 5, revision: 14, id: "foreign")), .resync)
        XCTAssertEqual(stream.text, "前缀\n\n初段续")
        XCTAssertEqual(stream.nextIndex, 5)
        XCTAssertEqual(stream.revision, 13)
        var bad = baseline
        var attempt = baseline["activeAttempt"] as! [String: Any]
        attempt["nextIndex"] = 100
        bad["activeAttempt"] = attempt
        XCTAssertFalse(stream.restore(bad))
        XCTAssertEqual(stream.text, "前缀\n\n初段续")
    }

    func testSettlementMatchesOnlyItsOwnStepAndAppend() {
        var stream = MobileAssistantStream()
        _ = stream.receive(start())
        XCTAssertFalse(stream.matches(["type": "assistant/message", "seq": 3, "data": ["turn": 1, "step": 2]]))
        XCTAssertFalse(stream.matches(["type": "assistant/message", "seq": 2, "data": ["turn": 1, "step": 1]]))
        XCTAssertFalse(stream.matches(["type": "assistant/message", "seq": 3, "surfaceOp": ["op": "replace"], "data": ["turn": 1, "step": 1]]))
        XCTAssertTrue(stream.matches(["type": "assistant/attempt", "seq": 3, "data": ["turn": 1, "step": 1]]))
        XCTAssertEqual(stream.receive(["type": "end", "attemptId": "a", "revision": 2, "index": 0,
                                      "outcome": ["kind": "abandoned"]]), .abandoned)
        XCTAssertFalse(stream.active)
    }
}
