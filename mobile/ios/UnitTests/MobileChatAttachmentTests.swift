import XCTest
import Foundation

final class MobileChatAttachmentTests: XCTestCase {
    private let imageAttachment: [String: Any] = [
        "attachmentId": "sha256:image",
        "mediaType": "image/jpeg",
        "bytes": 1_024,
        "width": 640,
        "height": 480,
        "name": "photo.jpg",
    ]

    private let fileAttachment: [String: Any] = [
        "attachmentId": "sha256:file",
        "name": "notes.txt",
        "bytes": 16,
    ]

    func testParsesImageOnlyMessageWithoutText() {
        let content = MobileMessageContent.parse(blocks: [["type": "image", "attachment": imageAttachment]])
        XCTAssertEqual(content.text, "")
        XCTAssertEqual(content.reasoning, "")
        XCTAssertEqual(content.attachments.count, 1)
        XCTAssertEqual(content.attachments.first?.image?.attachmentID ?? "", "sha256:image")
        XCTAssertEqual(content.attachments.first?.image?.aspectRatio ?? 0, 4.0 / 3.0, accuracy: 0.001)
    }

    func testParsesMixedTextAndAttachmentsInOrder() {
        let blocks: [[String: Any]] = [
            ["type": "text", "text": "请看这两项"],
            ["type": "image", "attachment": imageAttachment],
            ["type": "file", "attachment": fileAttachment],
            ["type": "text", "text": "然后给出结论"],
        ]
        let content = MobileMessageContent.parse(blocks: blocks)
        XCTAssertEqual(content.text, "请看这两项\n\n然后给出结论")
        XCTAssertEqual(content.attachments.count, 2)
        XCTAssertEqual(content.attachments[0].image?.name ?? "", "photo.jpg")
        XCTAssertEqual(content.attachments[1].file?.name ?? "", "notes.txt")
        XCTAssertEqual(content.attachments[1].file?.bytes ?? -1, 16)
    }

    func testMalformedAttachmentIsIgnoredWithoutDroppingText() {
        let blocks: [[String: Any]] = [
            ["type": "text", "text": "仍然显示"],
            ["type": "image", "attachment": ["mediaType": "image/png"]],
            ["type": "file", "attachment": ["name": "missing-id.txt"]],
            ["type": "image", "attachment": "not-an-object"],
        ]
        let content = MobileMessageContent.parse(blocks: blocks)
        XCTAssertEqual(content.text, "仍然显示")
        XCTAssertTrue(content.attachments.isEmpty)
    }

    func testImageReferenceRoundTripsTheWireFieldsUsedForReads() {
        let reference = MobileImageRef(wire: imageAttachment)
        XCTAssertEqual(reference?.attachmentID ?? "", "sha256:image")
        XCTAssertEqual(reference?.width ?? -1, 640)
        let wire = reference?.wire ?? [:]
        XCTAssertEqual(wire["attachmentId"] as? String ?? "", "sha256:image")
        XCTAssertEqual(wire["mediaType"] as? String ?? "", "image/jpeg")
        XCTAssertEqual(wire["width"] as? Int ?? -1, 640)
        XCTAssertEqual(wire["height"] as? Int ?? -1, 480)
        XCTAssertEqual(wire["name"] as? String ?? "", "photo.jpg")
    }

    func testHostImageLimitsAreDecodedAndInvalidValuesAreRejected() {
        let limits = MobileImageLimits(wire: [
            "maxImageBytes": 4_000,
            "maxImagesPerMessage": 3,
            "maxMessageImageBytes": 9_000,
            "maxImagePixels": 1_000_000,
            "maxImageDimension": 2_048,
        ])
        XCTAssertEqual(limits?.maxImageBytes ?? -1, 4_000)
        XCTAssertEqual(limits?.maxImagesPerMessage ?? -1, 3)
        XCTAssertEqual(limits?.maxImageDimension ?? -1, 2_048)
        XCTAssertNil(MobileImageLimits(wire: ["maxImageBytes": 0]))
        XCTAssertEqual(MobileImageLimits.fallback.maxImagesPerMessage, 20)
    }
}
