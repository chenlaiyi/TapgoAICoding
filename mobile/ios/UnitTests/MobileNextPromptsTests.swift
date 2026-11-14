import XCTest

final class MobileNextPromptsTests: XCTestCase {
    func testRecommendationsFollowTheirTurnAndNeverReplaceDraftText() {
        var state = MobileNextPrompts()
        state.consume(["type": "turn/start", "data": ["turn": 1]])
        state.consume(["type": "session/next-prompts-result", "data": ["turn": 1, "status": "ready", "prompts": [" 实施方案二 ", "列出步骤", "实施方案二"]]])
        XCTAssertEqual(state.prompts, ["实施方案二", "列出步骤"])
        XCTAssertEqual(MobileNextPrompts.appending(state.prompts[0], to: "已有草稿"), "已有草稿\n\n实施方案二")
        XCTAssertEqual(MobileNextPrompts.appending("实施方案二", to: ""), "实施方案二")
        state.consume(["type": "turn/start", "data": ["turn": 2]])
        state.consume(["type": "session/next-prompts-result", "data": ["turn": 1, "status": "ready", "prompts": ["过期建议"]]])
        XCTAssertTrue(state.prompts.isEmpty)
    }

    func testSnapshotRecoveryAndInvalidResultsDoNotInventRecommendations() {
        var state = MobileNextPrompts()
        state.restore(["turn": 3, "status": "ready", "prompts": ["继续"]], running: false)
        XCTAssertEqual(state.prompts, ["继续"])
        state.restore(["turn": 3, "status": "ready", "prompts": [" "]], running: false)
        state.restore(["turn": 3, "status": "ready", "prompts": ["a", "b", "c", "d"]], running: false)
        XCTAssertEqual(state.prompts, ["继续"])
        state.restore(["turn": 4, "status": "ready", "prompts": ["运行中不可显示"]], running: true)
        XCTAssertEqual(state.prompts, ["继续"])
        state.restore(["turn": 3, "status": "error", "prompts": []], running: false)
        XCTAssertTrue(state.failed)
        XCTAssertTrue(state.prompts.isEmpty)
    }
}
