import XCTest
import Foundation

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

    func testPlanPendingAndGoalRoundsAreProjected() {
        var state = MobileComposerState()
        state.restore(["asOfSeq": 3, "values": [
            "plan": ["active": true, "pending": true],
            "goal": ["goal": ["objective": "对齐", "phase": "active", "maxGoalRounds": 12], "roundsStarted": 3],
        ]])
        XCTAssertTrue(state.planPending)
        XCTAssertEqual(state.goalRoundsStarted, 3)
        XCTAssertEqual(state.goalMaxRounds, 12)
        state.restore(["asOfSeq": 4, "values": ["plan": ["active": true]]])
        XCTAssertFalse(state.planPending)
        XCTAssertNil(state.goalRoundsStarted)
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

    func testImageLimitsProjectionReplacesTheFallback() {
        var state = MobileComposerState()
        XCTAssertEqual(state.imageLimits.maxImageBytes, MobileImageLimits.fallback.maxImageBytes)
        state.restore(["asOfSeq": 2, "values": ["imageLimits": [
            "maxImageBytes": 4_000,
            "maxImagesPerMessage": 2,
            "maxMessageImageBytes": 8_000,
            "maxImagePixels": 1_000_000,
            "maxImageDimension": 2_048,
        ]]])
        XCTAssertEqual(state.imageLimits.maxImageBytes, 4_000)
        XCTAssertEqual(state.imageLimits.maxImageDimension, 2_048)
    }

}
