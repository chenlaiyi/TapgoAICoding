import Foundation
import XCTest

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

    func testRoundTripsPerStep() {
        MobileExpansionStore.save(["1:1": true, "1:2": false, "2:1": true],
                                  computerID: "mac", sessionID: "s-1", defaults: defaults)
        XCTAssertEqual(MobileExpansionStore.load(computerID: "mac", sessionID: "s-1", defaults: defaults),
                       ["1:1": true, "1:2": false, "2:1": true])
        XCTAssertEqual(MobileExpansionStore.load(computerID: "mac", sessionID: "s-2", defaults: defaults), [:])
    }

    func testKeepsOnlyTheNewestSteps() {
        var states: [String: Bool] = [:]
        for step in 1...(MobileExpansionStore.maxEntries + 20) {
            states[MobileExpansionStore.entryKey(turn: 1, step: step)] = true
        }
        MobileExpansionStore.save(states, computerID: "mac", sessionID: "s-1", defaults: defaults)
        let loaded = MobileExpansionStore.load(computerID: "mac", sessionID: "s-1", defaults: defaults)
        XCTAssertEqual(loaded.count, MobileExpansionStore.maxEntries)
        XCTAssertNil(loaded["1:20"])
        XCTAssertEqual(loaded["1:420"], true)
    }

    func testIgnoresLegacyTurnOnlyEntriesAndClears() {
        let legacy = try! JSONEncoder().encode(["3": true])
        defaults.set(legacy, forKey: MobileExpansionStore.key(computerID: "mac", sessionID: "s-1"))
        XCTAssertEqual(MobileExpansionStore.load(computerID: "mac", sessionID: "s-1", defaults: defaults), [:])

        MobileExpansionStore.save(["3:1": true], computerID: "mac", sessionID: "s-1", defaults: defaults)
        MobileExpansionStore.clear(computerID: "mac", sessionID: "s-1", defaults: defaults)
        XCTAssertEqual(MobileExpansionStore.load(computerID: "mac", sessionID: "s-1", defaults: defaults), [:])
        XCTAssertNil(defaults.data(forKey: MobileExpansionStore.key(computerID: "mac", sessionID: "s-1")))
    }
}
