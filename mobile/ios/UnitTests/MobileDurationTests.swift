import XCTest

final class MobileDurationTests: XCTestCase {
    func testFormatsSecondsMinutesAndHours() {
        XCTAssertEqual(MobileDuration.text(0), "0 秒")
        XCTAssertEqual(MobileDuration.text(59), "59 秒")
        XCTAssertEqual(MobileDuration.text(84), "1 分 24 秒")
        XCTAssertEqual(MobileDuration.text(3_723), "1 小时 2 分 3 秒")
        XCTAssertEqual(MobileDuration.text(-5), "0 秒")
    }
}
