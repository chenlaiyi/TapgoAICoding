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
    func testPicksOneActionableNonQuestionPrompt() {
        var prompts = MobileNextPrompts()
        prompts.restore(["turn": 1, "status": "ready", "prompts": ["要不要继续？", "运行测试并修复失败"]], running: false)
        XCTAssertEqual(prompts.bestExecutionPrompt, "运行测试并修复失败")
        prompts.restore(["turn": 2, "status": "ready", "prompts": ["如何优化？", "检查结果"]], running: false)
        XCTAssertEqual(prompts.bestExecutionPrompt, "检查结果")
        prompts.restore(["turn": 3, "status": "ready", "prompts": ["如何优化？", "要不要继续"]], running: false)
        XCTAssertNil(prompts.bestExecutionPrompt)
        XCTAssertTrue(MobileNextPrompts.isQuestion("检查是否需要迁移？"))
        XCTAssertFalse(MobileNextPrompts.isQuestion("运行测试"))
    }

    func testEchoedUserMessageIsNotPrefilled() {
        XCTAssertTrue(MobileNextPrompts.isEcho("先修顶部第一行", of: "先修顶部第一行：加顶部渐隐"))
        XCTAssertTrue(MobileNextPrompts.isEcho("先修顶部第一行：加顶部渐隐", of: "先修顶部第一行 加顶部渐隐"))
        XCTAssertFalse(MobileNextPrompts.isEcho("运行测试", of: "先修顶部第一行：加顶部渐隐"))
        var prompts = MobileNextPrompts()
        prompts.restore(["turn": 1, "status": "ready",
                         "prompts": ["先修顶部第一行：加顶部渐隐", "运行测试并修复失败"]], running: false)
        var composer = MobileRecommendationDraft()
        XCTAssertEqual(composer.receiving(prompts, draft: "", lastUserText: "先修顶部第一行：加顶部渐隐"),
                       "运行测试并修复失败")
        prompts.restore(["turn": 2, "status": "ready", "prompts": ["先修顶部第一行：加顶部渐隐"]], running: false)
        XCTAssertEqual(composer.receiving(prompts, draft: "", lastUserText: "先修顶部第一行：加顶部渐隐"), "")
    }

    func testPrefillOnceAndSwitchWithoutDuplicatingRecommendations() {
        var prompts = MobileNextPrompts()
        prompts.restore(["turn": 3, "status": "ready", "prompts": ["继续", "运行测试"]], running: false)
        var composer = MobileRecommendationDraft()
        XCTAssertEqual(composer.receiving(prompts, draft: ""), "继续")
        XCTAssertEqual(composer.selecting("运行测试", draft: "继续"), "运行测试")
        XCTAssertEqual(composer.receiving(prompts, draft: ""), "")
        XCTAssertEqual(composer.selecting("继续", draft: "我的草稿"), "我的草稿\n\n继续")
        prompts.restore(["turn": 4, "status": "ready", "prompts": ["下一步"]], running: false)
        XCTAssertEqual(composer.receiving(prompts, draft: "保留草稿"), "保留草稿")
        XCTAssertEqual(composer.receiving(prompts, draft: ""), "")
    }

}
