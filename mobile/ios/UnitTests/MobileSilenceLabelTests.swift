import XCTest

final class MobileSilenceLabelTests: XCTestCase {
    func testShortWaitsStayInSeconds() {
        XCTAssertEqual(MobileSilenceLabel.text(seconds: 59), "已 59 秒没有收到新输出")
        XCTAssertEqual(MobileSilenceLabel.text(seconds: 0), "已 0 秒没有收到新输出")
    }

    func testLongerWaitsReadAsMinutesAndSeconds() {
        XCTAssertEqual(MobileSilenceLabel.text(seconds: 60), "已 1 分 0 秒没有收到新输出")
        XCTAssertEqual(MobileSilenceLabel.text(seconds: 90), "已 1 分 30 秒没有收到新输出")
        XCTAssertEqual(MobileSilenceLabel.text(seconds: 1723), "已 28 分 43 秒没有收到新输出")
    }

    func testHourlyWaitsDropTheSeconds() {
        XCTAssertEqual(MobileSilenceLabel.text(seconds: 3725), "已 1 小时 2 分没有收到新输出")
    }

    func testNegativeInputClampsToZero() {
        XCTAssertEqual(MobileSilenceLabel.text(seconds: -5), "已 0 秒没有收到新输出")
    }
}
