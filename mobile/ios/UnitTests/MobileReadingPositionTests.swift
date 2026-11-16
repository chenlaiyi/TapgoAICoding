import XCTest
import Foundation

final class MobileReadingPositionTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "mobile-reading-tests-\(UUID().uuidString)"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testRoundTripsOneAnchorPerConversation() {
        MobileReadingPosition.save("assistant-2-1", computerID: "mac", sessionID: "s-1", defaults: defaults)
        XCTAssertEqual(MobileReadingPosition.load(computerID: "mac", sessionID: "s-1", defaults: defaults),
                       "assistant-2-1")
        XCTAssertNil(MobileReadingPosition.load(computerID: "mac", sessionID: "s-2", defaults: defaults))
    }

    func testClearingAndEmptyAnchorsRemoveTheKey() {
        MobileReadingPosition.save("assistant-1-1", computerID: "mac", sessionID: "s-1", defaults: defaults)
        MobileReadingPosition.save(nil, computerID: "mac", sessionID: "s-1", defaults: defaults)
        XCTAssertNil(MobileReadingPosition.load(computerID: "mac", sessionID: "s-1", defaults: defaults))

        MobileReadingPosition.save("assistant-1-1", computerID: "mac", sessionID: "s-1", defaults: defaults)
        MobileReadingPosition.clear(computerID: "mac", sessionID: "s-1", defaults: defaults)
        XCTAssertNil(defaults.string(forKey: MobileReadingPosition.key(computerID: "mac", sessionID: "s-1")))

        MobileReadingPosition.save("", computerID: "mac", sessionID: "s-1", defaults: defaults)
        XCTAssertNil(MobileReadingPosition.load(computerID: "mac", sessionID: "s-1", defaults: defaults))
    }

    func testComputersAndSessionsDoNotShareAnchors() {
        MobileReadingPosition.save("a", computerID: "mac-a", sessionID: "s-1", defaults: defaults)
        MobileReadingPosition.save("b", computerID: "mac-a", sessionID: "s-2", defaults: defaults)
        MobileReadingPosition.save("c", computerID: "mac-b", sessionID: "s-1", defaults: defaults)
        XCTAssertEqual(MobileReadingPosition.load(computerID: "mac-a", sessionID: "s-1", defaults: defaults), "a")
        XCTAssertEqual(MobileReadingPosition.load(computerID: "mac-a", sessionID: "s-2", defaults: defaults), "b")
        XCTAssertEqual(MobileReadingPosition.load(computerID: "mac-b", sessionID: "s-1", defaults: defaults), "c")
    }
}
