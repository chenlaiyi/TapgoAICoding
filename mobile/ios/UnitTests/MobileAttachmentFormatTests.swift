import XCTest

final class MobileAttachmentFormatTests: XCTestCase {
    func testBytesUseTheLargestSmallUnit() {
        XCTAssertEqual(MobileAttachmentFormat.byteText(0), "0 B")
        XCTAssertEqual(MobileAttachmentFormat.byteText(1_023), "1023 B")
        XCTAssertEqual(MobileAttachmentFormat.byteText(1_536), "1.5 KB")
        XCTAssertEqual(MobileAttachmentFormat.byteText(3_355_443), "3.2 MB")
    }

    func testNegativeBytesClampToZero() {
        XCTAssertEqual(MobileAttachmentFormat.byteText(-8), "0 B")
    }
}
