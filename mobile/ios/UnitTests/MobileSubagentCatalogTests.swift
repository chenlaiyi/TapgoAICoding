import XCTest

final class MobileSubagentCatalogTests: XCTestCase {
    func testParsesProjectionRowsAndLiveCatalogEvents() {
        let entries = MobileSubagentCatalog.parse([
            ["id": "child-1", "name": "Wedding cinematic", "label": "cinematic", "mode": "continuable", "createdAt": 1.0],
            ["id": "child-2", "mode": "external"],
        ])
        XCTAssertEqual(entries.map(\.displayName), ["Wedding cinematic", "child-2"])
        let updated = MobileSubagentCatalog.upsert(entries, data: ["childId": "child-2", "name": "Wedding eastern", "mode": "continuable"])
        XCTAssertEqual(updated.count, 2)
        XCTAssertEqual(updated[1].displayName, "Wedding eastern")
    }

    func testDelegationRunningMatchesTheDescription() {
        var activity = MobileChatActivity(id: "a", name: "subagent", detail: "", category: "",
                                          arguments: #"{"description":"cinematic","prompt":"x"}"#)
        let entry = MobileSubagentEntry(id: "child-1", name: "Wedding cinematic", label: "cinematic",
                                        mode: "continuable", createdAt: 0)
        XCTAssertTrue(MobileSubagentCatalog.isRunning(entry, activities: [activity]))
        activity.finished = true
        XCTAssertFalse(MobileSubagentCatalog.isRunning(entry, activities: [activity]))
        XCTAssertTrue(MobileSubagentCatalog.isDelegation("subagent_fork"))
        XCTAssertFalse(MobileSubagentCatalog.isDelegation("bash"))
    }
}
