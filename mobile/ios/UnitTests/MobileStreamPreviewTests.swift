import XCTest

final class MobileStreamPreviewTests: XCTestCase {
    func testShortTextIsUnchanged() {
        XCTAssertEqual(MobileStreamPreview.bounded("正在检查队列"), "正在检查队列")
        XCTAssertFalse(MobileStreamPreview.isTruncated("正在检查队列"))
        XCTAssertEqual(MobileStreamPreview.bounded(String(repeating: "a", count: 8_000)).count, 8_000)
    }

    func testLongTextKeepsTheNewestTail() {
        let text = String(repeating: "a", count: 8_000) + "TAIL"
        let bounded = MobileStreamPreview.bounded(text)
        XCTAssertEqual(bounded.count, 8_001)
        XCTAssertTrue(bounded.hasPrefix("…"))
        XCTAssertTrue(bounded.hasSuffix("TAIL"))
        XCTAssertTrue(MobileStreamPreview.isTruncated(text))
    }

    func testNonPositiveLimitDisablesBounding() {
        XCTAssertEqual(MobileStreamPreview.bounded("abc", limit: 0), "abc")
        XCTAssertFalse(MobileStreamPreview.isTruncated("abc", limit: 0))
    }
}

final class MobileStreamTableHoldbackTests: XCTestCase {
    func testHoldsBackAnUnfinishedTrailingTable() {
        let text = "先说明一下：\n\n| a | b |\n| --- | --- |\n| 1 | 2 |"
        XCTAssertEqual(MobileStreamPreview.stableTail(text), "先说明一下：\n")
    }

    func testShowsACompletedTableAfterABlankLine() {
        let text = "| a | b |\n| --- | --- |\n| 1 | 2 |\n\n后文"
        XCTAssertEqual(MobileStreamPreview.stableTail(text), text)
    }

    func testSingleTrailingNewlineKeepsTheTableHeld() {
        let text = "| a | b |\n| --- | --- |\n| 1 | 2 |\n"
        XCTAssertEqual(MobileStreamPreview.stableTail(text), "")
    }

    func testWholeTableWaitsForItsBlock() {
        XCTAssertEqual(MobileStreamPreview.stableTail("| a |\n| --- |\n| 1 |"), "")
        XCTAssertEqual(MobileStreamPreview.stableTail("普通正文"), "普通正文")
    }
}

final class MobileStreamFenceTests: XCTestCase {
    func testPipesInsideAnOpenCodeFenceAreNotHeld() {
        let text = "```\n| not a table |\nmore code |"
        XCTAssertEqual(MobileStreamPreview.stableTail(text), text)
    }

    func testClosedFenceThenTableStillHolds() {
        let text = "```\ncode\n```\n\n| a |\n| --- |\n| 1 |"
        XCTAssertEqual(MobileStreamPreview.stableTail(text), "```\ncode\n```\n")
    }
}
