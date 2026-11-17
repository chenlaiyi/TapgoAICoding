import XCTest
import Foundation

final class MobileDraftStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "mobile-draft-tests-\(UUID().uuidString)"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testRoundTripsTextAndModePerConversation() {
        let key = MobileDraftStore.sessionKey(computerID: "http://192.168.1.20:19389", sessionID: "s-1")
        MobileDraftStore.save(MobileDraft(text: "继续检查队列", mode: .plan), key: key, defaults: defaults)
        XCTAssertEqual(MobileDraftStore.load(key: key, defaults: defaults),
                       MobileDraft(text: "继续检查队列", mode: .plan))
    }

    func testLongDraftsAreTruncated() {
        let key = MobileDraftStore.sessionKey(computerID: "mac", sessionID: "s-1")
        MobileDraftStore.save(MobileDraft(text: String(repeating: "字", count: 9_000), mode: .message),
                              key: key, defaults: defaults)
        XCTAssertEqual(MobileDraftStore.load(key: key, defaults: defaults)?.text.count, MobileDraftStore.maxCharacters)
    }

    func testEmptyMessageDraftClearsTheKey() {
        let key = MobileDraftStore.sessionKey(computerID: "mac", sessionID: "s-1")
        MobileDraftStore.save(MobileDraft(text: "草稿", mode: .message), key: key, defaults: defaults)
        MobileDraftStore.save(MobileDraft(text: "", mode: .message), key: key, defaults: defaults)
        XCTAssertNil(MobileDraftStore.load(key: key, defaults: defaults))
        XCTAssertNil(defaults.data(forKey: key))
    }

    func testComputersSessionsAndNewConversationsDoNotShareDrafts() {
        let first = MobileDraftStore.sessionKey(computerID: "mac-a", sessionID: "s-1")
        let second = MobileDraftStore.sessionKey(computerID: "mac-a", sessionID: "s-2")
        let otherComputer = MobileDraftStore.sessionKey(computerID: "mac-b", sessionID: "s-1")
        let newConversation = MobileDraftStore.newConversationKey(computerID: "mac-a")
        MobileDraftStore.save(MobileDraft(text: "A", mode: .message), key: first, defaults: defaults)
        MobileDraftStore.save(MobileDraft(text: "B", mode: .message), key: second, defaults: defaults)
        MobileDraftStore.save(MobileDraft(text: "C", mode: .message), key: otherComputer, defaults: defaults)
        XCTAssertEqual(MobileDraftStore.load(key: first, defaults: defaults)?.text, "A")
        XCTAssertEqual(MobileDraftStore.load(key: second, defaults: defaults)?.text, "B")
        XCTAssertEqual(MobileDraftStore.load(key: otherComputer, defaults: defaults)?.text, "C")
        XCTAssertNil(MobileDraftStore.load(key: newConversation, defaults: defaults))
    }

    func testClearAllRemovesOnlyDraftKeys() {
        let first = MobileDraftStore.sessionKey(computerID: "mac-a", sessionID: "s-1")
        let second = MobileDraftStore.newConversationKey(computerID: "mac-b")
        defaults.set("keep", forKey: "mobile.other")
        MobileDraftStore.save(MobileDraft(text: "A", mode: .message), key: first, defaults: defaults)
        MobileDraftStore.save(MobileDraft(text: "B", mode: .message), key: second, defaults: defaults)
        MobileDraftStore.clearAll(defaults: defaults)
        XCTAssertNil(MobileDraftStore.load(key: first, defaults: defaults))
        XCTAssertNil(MobileDraftStore.load(key: second, defaults: defaults))
        XCTAssertEqual(defaults.string(forKey: "mobile.other"), "keep")
    }

    func testModeWithoutTextSurvivesAndClearingRemovesIt() {
        let key = MobileDraftStore.newConversationKey(computerID: "mac")
        MobileDraftStore.save(MobileDraft(text: "", mode: .goal), key: key, defaults: defaults)
        XCTAssertEqual(MobileDraftStore.load(key: key, defaults: defaults)?.mode, .goal)
        MobileDraftStore.clear(key: key, defaults: defaults)
        XCTAssertNil(MobileDraftStore.load(key: key, defaults: defaults))
    }
}
