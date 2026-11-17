import XCTest

final class MobileNotificationTextTests: XCTestCase {
    func testPreviewCollapsesWhitespaceAndTruncates() {
        XCTAssertEqual(MobileNotificationText.preview("a\n\nb   c"), "a b c")
        let long = String(repeating: "字", count: 200)
        XCTAssertEqual(MobileNotificationText.preview(long).count, 121)
        XCTAssertTrue(MobileNotificationText.preview(long).hasSuffix("…"))
    }

    func testCompletedUsesReplyOrFallback() {
        XCTAssertEqual(MobileNotificationText.completed(sessionTitle: "修复", reply: "已完成"),
                       "修复 · 已完成")
        XCTAssertEqual(MobileNotificationText.completed(sessionTitle: "修复", reply: "   "),
                       "修复 · 回合完成")
    }

    func testFailedAndApprovalHaveContext() {
        XCTAssertEqual(MobileNotificationText.failed(sessionTitle: "修复", reason: nil), "修复 · 运行出错")
        XCTAssertEqual(MobileNotificationText.failed(sessionTitle: "修复", reason: "error"), "修复 · error")
        XCTAssertEqual(MobileNotificationText.approval(sessionTitle: "修复", toolName: "bash"),
                       "修复 · 等待批准：bash")
    }
}
