import XCTest
import Foundation

final class MobileExpansionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "mobile-expansion-tests-\(UUID().uuidString)"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testRoundTripsPerConversation() {
        MobileExpansionStore.save([1: true, 2: false], computerID: "mac", sessionID: "s-1", defaults: defaults)
        XCTAssertEqual(MobileExpansionStore.load(computerID: "mac", sessionID: "s-1", defaults: defaults),
                       [1: true, 2: false])
        XCTAssertEqual(MobileExpansionStore.load(computerID: "mac", sessionID: "s-2", defaults: defaults), [:])
    }

    func testKeepsOnlyTheNewestTurns() {
        let states = Dictionary(uniqueKeysWithValues: (1...(MobileExpansionStore.maxTurns + 50)).map { ($0, true) })
        MobileExpansionStore.save(states, computerID: "mac", sessionID: "s-1", defaults: defaults)
        let loaded = MobileExpansionStore.load(computerID: "mac", sessionID: "s-1", defaults: defaults)
        XCTAssertEqual(loaded.count, MobileExpansionStore.maxTurns)
        XCTAssertTrue(loaded.keys.allSatisfy { $0 > 50 })
        XCTAssertNil(loaded[50])
    }

    func testEmptyStatesAndClearRemoveTheKey() {
        MobileExpansionStore.save([3: true], computerID: "mac", sessionID: "s-1", defaults: defaults)
        MobileExpansionStore.save([:], computerID: "mac", sessionID: "s-1", defaults: defaults)
        XCTAssertNil(defaults.data(forKey: MobileExpansionStore.key(computerID: "mac", sessionID: "s-1")))

        MobileExpansionStore.save([3: true], computerID: "mac", sessionID: "s-1", defaults: defaults)
        MobileExpansionStore.clear(computerID: "mac", sessionID: "s-1", defaults: defaults)
        XCTAssertEqual(MobileExpansionStore.load(computerID: "mac", sessionID: "s-1", defaults: defaults), [:])
    }
}
