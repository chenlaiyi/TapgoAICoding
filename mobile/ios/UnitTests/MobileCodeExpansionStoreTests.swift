import XCTest
import Foundation

final class MobileCodeExpansionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "mobile-code-expansion-tests-\(UUID().uuidString)"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testRoundTripsPerConversation() {
        MobileCodeExpansionStore.save(["assistant-1-1:0": true, "assistant-1-1:2": false],
                                      computerID: "mac", sessionID: "s-1", defaults: defaults)
        XCTAssertEqual(MobileCodeExpansionStore.load(computerID: "mac", sessionID: "s-1", defaults: defaults),
                       ["assistant-1-1:0": true, "assistant-1-1:2": false])
        XCTAssertTrue(MobileCodeExpansionStore.load(computerID: "mac", sessionID: "s-2", defaults: defaults).isEmpty)
    }

    func testKeepsABoundedNumberOfBlocks() {
        var states: [String: Bool] = [:]
        for index in 0..<(MobileCodeExpansionStore.maxBlocks + 20) {
            states["assistant-1-1:\(index)"] = true
        }
        MobileCodeExpansionStore.save(states, computerID: "mac", sessionID: "s-1", defaults: defaults)
        let loaded = MobileCodeExpansionStore.load(computerID: "mac", sessionID: "s-1", defaults: defaults)
        XCTAssertEqual(loaded.count, MobileCodeExpansionStore.maxBlocks)
    }

    func testClearingRemovesTheKey() {
        MobileCodeExpansionStore.save(["a:0": true], computerID: "mac", sessionID: "s-1", defaults: defaults)
        MobileCodeExpansionStore.clear(computerID: "mac", sessionID: "s-1", defaults: defaults)
        XCTAssertTrue(MobileCodeExpansionStore.load(computerID: "mac", sessionID: "s-1", defaults: defaults).isEmpty)
        XCTAssertNil(defaults.data(forKey: MobileCodeExpansionStore.key(computerID: "mac", sessionID: "s-1")))
    }
}
