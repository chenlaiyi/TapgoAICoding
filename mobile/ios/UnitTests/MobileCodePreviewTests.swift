import XCTest

final class MobileCodePreviewTests: XCTestCase {
    func testShortBlocksStayWhole() {
        let code = "let a = 1\nlet b = 2"
        XCTAssertEqual(MobileCodePreview.visible(code, expanded: false, limit: 40), code)
        XCTAssertFalse(MobileCodePreview.isCollapsible(code, limit: 40))
        XCTAssertEqual(MobileCodePreview.lineCount(code), 2)
    }

    func testLongBlocksCollapseAndExpand() {
        let code = (1...50).map { "line \($0)" }.joined(separator: "\n")
        let collapsed = MobileCodePreview.visible(code, expanded: false, limit: 40)
        XCTAssertEqual(collapsed.split(separator: "\n").count, 40)
        XCTAssertTrue(collapsed.hasPrefix("line 1"))
        XCTAssertFalse(collapsed.contains("line 50"))
        XCTAssertEqual(MobileCodePreview.visible(code, expanded: true, limit: 40), code)
        XCTAssertTrue(MobileCodePreview.isCollapsible(code, limit: 40))
        XCTAssertEqual(MobileCodePreview.lineCount(code), 50)
    }

    func testZeroLimitDisablesCollapsing() {
        let code = "a\nb\nc"
        XCTAssertEqual(MobileCodePreview.visible(code, expanded: false, limit: 0), code)
        XCTAssertFalse(MobileCodePreview.isCollapsible(code, limit: 0))
    }
}
