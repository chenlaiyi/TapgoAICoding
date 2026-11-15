import XCTest

final class MobileToolOutputTests: XCTestCase {
    private func opened(_ from: Int = 0) -> [String: Any] {
        ["type": "opened", "from": from, "job": ["id": "job", "owner": "session"]]
    }

    func testOffsetsResumeWithoutDuplicateUnicodeOrPartialLines() {
        var output = MobileToolOutput(id: "job", owner: "session")
        output.receive(opened())
        output.receive(["type": "output", "chunks": [["at": 0, "text": "你好\nhel"]], "next": 10])
        output.disconnect()
        XCTAssertEqual(output.phase, .disconnected)
        output.begin()
        output.receive(opened(10))
        output.receive(["type": "output", "chunks": [["at": 0, "text": "你好\nhel"], ["at": 10, "text": "lo\n"]], "next": 13])
        XCTAssertEqual(output.text, "你好\nhello\n")
        XCTAssertEqual(output.nextOffset, 13)
        XCTAssertFalse(output.gap)
        output.receive(["type": "status", "job": ["id": "job", "status": "killed"]])
        XCTAssertEqual(output.phase, .stopped)
        XCTAssertTrue(output.text.contains("hello"))
    }

    func testRetentionAndServerGapsAreVisibleWithoutCorruptingUnicode() {
        var output = MobileToolOutput(id: "job", owner: "session")
        output.receive(opened(30))
        let text = String(repeating: "中文日志\n", count: 10000)
        output.receive(["type": "output", "chunks": [["at": 30, "text": text]], "next": 30 + text.utf8.count, "lossy": true])
        XCTAssertLessThanOrEqual(output.text.utf8.count, MobileToolOutput.retainedBytes)
        XCTAssertFalse(output.text.contains("�"))
        XCTAssertTrue(output.gap)
        XCTAssertEqual(output.nextOffset, 30 + text.utf8.count)
    }

    func testMalformedOrForeignFramesDoNotReplaceTrustedOutput() {
        var output = MobileToolOutput(id: "job", owner: "session")
        output.receive(["type": "opened", "from": 0, "job": ["id": "job", "owner": "other"]])
        XCTAssertEqual(output.phase, .unavailable)
        output.receive(["type": "output", "chunks": [["at": 0, "text": "secret"]], "next": 6])
        XCTAssertEqual(output.text, "")
        output.begin()
        output.receive(opened())
        output.receive(["type": "output", "chunks": [["at": 0, "text": "safe\n"]], "next": 5])
        output.receive(["type": "output", "chunks": [["at": 5, "text": "bad"]], "next": 6])
        XCTAssertEqual(output.phase, .unavailable)
        XCTAssertEqual(output.text, "safe\n")
        XCTAssertEqual(output.nextOffset, 5)
    }
    func testTerminalStatusReportsAnUndrainedTailAsPartial() {
        var output = MobileToolOutput(id: "job", owner: "session")
        output.receive(opened())
        output.receive(["type": "output", "chunks": [["at": 0, "text": "first\n"]], "next": 6])
        output.receive(["type": "status", "job": ["id": "job", "status": "completed", "output": ["total": 20]]])
        XCTAssertEqual(output.phase, .completed)
        XCTAssertEqual(output.text, "first\n")
        XCTAssertTrue(output.gap)
    }

}
