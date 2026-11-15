import XCTest

final class MobileComposerStateTests: XCTestCase {
    func testLateBaselinePreservesNewerPerKeyChanges() {
        var state = MobileComposerState()
        state.consume(["seq": 8, "changes": [["key": "plan", "val": ["active": true]]]])
        state.restore(["asOfSeq": 4, "values": ["plan": ["active": false],
            "goal": ["goal": ["objective": "检查项目", "phase": "active"]]]])
        XCTAssertTrue(state.planActive)
        XCTAssertEqual(state.goalObjective, "检查项目")
        state.consume(["seq": 5, "changes": [["key": "goal", "val": NSNull()]]])
        state.restore(["asOfSeq": 4, "values": ["goal": ["goal": ["objective": "旧目标", "phase": "active"]]]])
        XCTAssertNil(state.goalObjective)
        XCTAssertTrue(state.planActive)
    }

    func testReplacementClearsAbsentCapabilitiesAndKeepsUnchangedKeys() {
        var state = MobileComposerState()
        state.restore(["asOfSeq": 3, "values": ["plan": ["active": true],
            "goal": ["goal": ["objective": "检查项目", "phase": "paused"]]]])
        state.consume(["seq": 4, "changes": [["key": "plan", "val": ["active": false]]]])
        XCTAssertFalse(state.planActive)
        XCTAssertEqual(state.goalPhase, "paused")
        state.restore(["asOfSeq": 5, "values": [:]])
        XCTAssertFalse(state.planActive)
        XCTAssertNil(state.goalPhase)
    }
    func testTitleProjectionRejectsStaleBaselinesAndClearsRemovedTitles() {
        var state = MobileComposerState()
        state.restore(["asOfSeq": 5, "values": ["title": "初始标题"]])
        XCTAssertEqual(state.sessionTitle, "初始标题")
        state.consume(["seq": 8, "changes": [["key": "title", "val": "最新任务标题"]]])
        state.restore(["asOfSeq": 6, "values": ["title": "旧标题"]])
        XCTAssertEqual(state.sessionTitle, "最新任务标题")
        state.consume(["seq": 9, "changes": [["key": "title", "val": NSNull()]]])
        XCTAssertNil(state.sessionTitle)
    }

}
