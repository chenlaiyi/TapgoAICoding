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
