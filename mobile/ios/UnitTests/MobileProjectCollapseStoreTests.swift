import Foundation
import XCTest

final class MobileProjectCollapseStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "mobile-project-collapse-tests-\(UUID().uuidString)"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testRoundTripsPerComputer() {
        MobileProjectCollapseStore.save(["/work/a", "/work/b"], computerID: "mac-a", defaults: defaults)
        XCTAssertEqual(MobileProjectCollapseStore.load(computerID: "mac-a", defaults: defaults),
                       ["/work/a", "/work/b"])
        XCTAssertTrue(MobileProjectCollapseStore.load(computerID: "mac-b", defaults: defaults).isEmpty)
    }

    func testEmptySetClearsTheKey() {
        MobileProjectCollapseStore.save(["/work/a"], computerID: "mac-a", defaults: defaults)
        MobileProjectCollapseStore.save([], computerID: "mac-a", defaults: defaults)
        XCTAssertNil(defaults.data(forKey: MobileProjectCollapseStore.key(computerID: "mac-a")))
        XCTAssertTrue(MobileProjectCollapseStore.load(computerID: "mac-a", defaults: defaults).isEmpty)
    }

    func testClearRemovesOnlyOneComputer() {
        MobileProjectCollapseStore.save(["/a"], computerID: "mac-a", defaults: defaults)
        MobileProjectCollapseStore.save(["/b"], computerID: "mac-b", defaults: defaults)
        MobileProjectCollapseStore.clear(computerID: "mac-a", defaults: defaults)
        XCTAssertTrue(MobileProjectCollapseStore.load(computerID: "mac-a", defaults: defaults).isEmpty)
        XCTAssertEqual(MobileProjectCollapseStore.load(computerID: "mac-b", defaults: defaults), ["/b"])
    }
}
