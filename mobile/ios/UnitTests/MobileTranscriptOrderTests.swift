import XCTest

final class MobileTranscriptOrderTests: XCTestCase {
    func testInsertsAfterTheLastEarlierRow() {
        let ids = [3, 7, 9]
        XCTAssertEqual(MobileTranscriptOrder.insertionIndex(ids: ids, after: 3), 1)
        XCTAssertEqual(MobileTranscriptOrder.insertionIndex(ids: ids, after: 8), 2)
        XCTAssertEqual(MobileTranscriptOrder.insertionIndex(ids: ids, after: 100), 3)
    }

    func testMergesOnlyAdjacentProcessRowsInTheSameTurn() {
        XCTAssertTrue(MobileTranscriptOrder.canMergeProcess(lastRole: "process", lastTurn: 2, turn: 2))
        XCTAssertFalse(MobileTranscriptOrder.canMergeProcess(lastRole: "process", lastTurn: 1, turn: 2))
        XCTAssertFalse(MobileTranscriptOrder.canMergeProcess(lastRole: "assistant", lastTurn: 2, turn: 2))
        XCTAssertFalse(MobileTranscriptOrder.canMergeProcess(lastRole: nil, lastTurn: nil, turn: 2))
    }

    func testLiveTextSitsAboveTheProcessRow() {
        XCTAssertEqual(MobileTranscriptOrder.liveTextIndex(processIndex: 4, fallback: 0), 4)
        XCTAssertEqual(MobileTranscriptOrder.liveTextIndex(processIndex: nil, fallback: 2), 2)
    }

    func testFallsBackToTheTopAndSkipsSynthesizedRows() {
        XCTAssertEqual(MobileTranscriptOrder.insertionIndex(ids: [3, 7], after: 2), 0)
        XCTAssertEqual(MobileTranscriptOrder.insertionIndex(ids: [-1_000_003, -1, 4], after: 0), 0)
        XCTAssertEqual(MobileTranscriptOrder.insertionIndex(ids: [-1], after: 9), 0)
    }
}
