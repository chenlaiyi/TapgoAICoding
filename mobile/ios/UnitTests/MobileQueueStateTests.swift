import XCTest
import Foundation

final class MobileQueueStateTests: XCTestCase {
    private let image: [String: Any] = ["type": "image", "attachment": [
        "attachmentId": "sha256:queue-image",
        "mediaType": "image/png",
        "bytes": 69,
        "width": 1,
        "height": 1,
    ]]

    func testDecodesQueuedAndSteeringItems() {
        let state = MobileQueueState.decode([
            "cursor": 12,
            "running": true,
            "queue": [
                ["id": "message-1", "placement": "queued",
                 "content": [["type": "text", "text": "补充一句"]]],
                ["id": "message-2", "placement": "steering",
                 "content": [["type": "text", "text": "立即纠正"]]],
            ],
        ])
        XCTAssertEqual(state?.items.count ?? -1, 2)
        XCTAssertEqual(state?.items.first?.text ?? "", "补充一句")
        XCTAssertTrue(state?.items.first?.isSteering == false)
        XCTAssertTrue(state?.items.last?.isSteering == true)
        XCTAssertTrue(state?.items.first?.isEditable == true)
        XCTAssertTrue(state?.running == true)
        XCTAssertEqual(state?.cursor ?? -1, 12)
        XCTAssertTrue(state?.steeringAvailable == true)
    }

    func testNullQueueMeansNoLiveAgentAndHidesTheStrip() {
        let state = MobileQueueState.decode(["cursor": 3, "running": false, "queue": NSNull()])
        XCTAssertEqual(state?.items.count ?? -1, 0)
        XCTAssertTrue(state?.running == false)
    }

    func testContextPlacementAndEmptyItemsAreIgnored() {
        let state = MobileQueueState.decode([
            "cursor": 1,
            "running": true,
            "queue": [
                ["id": "context-1", "placement": "context",
                 "content": [["type": "text", "text": "隐藏上下文"]]],
                ["id": "empty", "placement": "queued", "content": []],
            ],
        ])
        XCTAssertEqual(state?.items.count ?? -1, 0)
    }

    func testImageOnlyQueuedItemIsVisibleButNotEditable() {
        let state = MobileQueueState.decode([
            "cursor": 4,
            "running": true,
            "queue": [["id": "image-1", "placement": "queued", "content": [image]]],
        ])
        let item = state?.items.first
        XCTAssertEqual(item?.text ?? "", "")
        XCTAssertEqual(item?.attachments.count ?? -1, 1)
        XCTAssertTrue(item?.isEditable == false)
        XCTAssertEqual(item?.preview ?? "", "附件")
    }

    func testEditActionCarriesTextOnlyContent() {
        let wire = MobileQueueAction.edit("改一下").wire
        XCTAssertEqual(wire["kind"] as? String, "edit")
        let content = wire["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count ?? -1, 1)
        XCTAssertEqual(content?.first?["type"] as? String, "text")
        XCTAssertEqual(content?.first?["text"] as? String, "改一下")
    }

    func testRemoveAndSteerActionsCarryOnlyTheirKind() {
        XCTAssertEqual(MobileQueueAction.remove.wire["kind"] as? String, "remove")
        XCTAssertNil(MobileQueueAction.remove.wire["content"] as? [[String: Any]])
        XCTAssertEqual(MobileQueueAction.steer.wire["kind"] as? String, "steer")
        XCTAssertNil(MobileQueueAction.steer.wire["content"] as? [[String: Any]])
    }

    func testHostRefusalCodesMapToReadableMessages() {
        XCTAssertEqual(MobileQueueFailure.message(for: "session/queue-item-not-found"), "这条消息已被处理")
        XCTAssertEqual(MobileQueueFailure.message(for: "session/steer-unavailable"), "当前回合已结束，消息仍在队列")
        XCTAssertEqual(MobileQueueFailure.message(for: "session/attachment-invalid"), "含附件的排队消息请在电脑上编辑")
        XCTAssertEqual(MobileQueueFailure.message(for: "gateway/internal"), "队列操作失败，请重试")
    }

    func testMalformedStateIsRejectedInsteadOfInventingAnEmptyQueue() {
        XCTAssertNil(MobileQueueState.decode(["queue": []]))
        XCTAssertNil(MobileQueueState.decode(["running": "yes", "queue": []]))
    }
}
