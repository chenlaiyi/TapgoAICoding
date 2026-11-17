import XCTest

final class MobileVoicePunctuationTests: XCTestCase {
    func testPauseBecomesCommaAndEndsWithFullStop() {
        let segments = [
            (text: "今天我们", start: 0.0, duration: 0.5),
            (text: "先看商品", start: 1.0, duration: 0.5),
            (text: "再看进度", start: 2.0, duration: 0.5),
        ]
        XCTAssertEqual(MobileVoicePunctuation.punctuated(segments, fallback: "今天我们 先看商品 再看进度"),
                       "今天我们，先看商品，再看进度。")
    }

    func testKeepsRecognizerPunctuation() {
        let segments = [(text: "已经好了。", start: 0.0, duration: 0.5)]
        XCTAssertEqual(MobileVoicePunctuation.punctuated(segments, fallback: "已经好了。"), "已经好了。")
        XCTAssertEqual(MobileVoicePunctuation.finalStop("等等！"), "等等！")
    }

    func testFallbackGetsOnlyFinalStop() {
        XCTAssertEqual(MobileVoicePunctuation.punctuated([], fallback: "没有分段"), "没有分段。")
        XCTAssertEqual(MobileVoicePunctuation.punctuated([], fallback: ""), "")
    }
}
