import XCTest
import Foundation

final class MobilePendingSubmissionTests: XCTestCase {
    func testUnchangedDraftMatchesForRequestIdReuse() {
        let attachment = MobileDraftAttachment(name: "photo.jpg", data: Data([1, 2, 3]), image: true)
        let first = MobilePendingSubmission(text: "继续", mode: .message, attachments: [attachment])
        let retry = MobilePendingSubmission(text: "继续", mode: .message, attachments: [attachment])
        XCTAssertNotEqual(first.requestId, retry.requestId)
        XCTAssertTrue(first.matches(retry))
    }

    func testEditedDraftDoesNotMatch() {
        let base = MobilePendingSubmission(text: "继续", mode: .message, attachments: [])
        XCTAssertFalse(base.matches(MobilePendingSubmission(text: "继续处理", mode: .message, attachments: [])))
        XCTAssertFalse(base.matches(MobilePendingSubmission(text: "继续", mode: .plan, attachments: [])))
    }

    func testChangedAttachmentsDoNotMatch() {
        let photo = MobileDraftAttachment(name: "photo.jpg", data: Data([1, 2, 3]), image: true)
        let base = MobilePendingSubmission(text: "看看这张图", mode: .message, attachments: [photo])
        XCTAssertFalse(base.matches(MobilePendingSubmission(text: "看看这张图", mode: .message, attachments: [])))
        XCTAssertFalse(base.matches(MobilePendingSubmission(
            text: "看看这张图", mode: .message,
            attachments: [MobileDraftAttachment(name: "photo.jpg", data: Data([1, 2, 3, 4]), image: true)])))
        XCTAssertFalse(base.matches(MobilePendingSubmission(
            text: "看看这张图", mode: .message,
            attachments: [MobileDraftAttachment(name: "other.jpg", data: Data([1, 2, 3]), image: true)])))
    }

    func testExplicitRequestIdSurvives() {
        let submission = MobilePendingSubmission(text: "继续", mode: .message, attachments: [],
                                                 requestId: "request-1")
        XCTAssertEqual(submission.requestId, "request-1")
    }
}
