import XCTest

final class MobileChangesFilterTests: XCTestCase {
    private func file(_ path: String, added: Int = 1) -> MobileChangesSummary.File {
        MobileChangesSummary.File(path: path, display: path, added: added, deleted: 0, binary: nil, oversized: nil)
    }

    func testAllFilesAndDeliverablesAreSeparated() {
        let files = [file("Sources/a.swift"), file("docs/b.md"), file("README.md")]
        let deliverables: Set<String> = ["/Users/me/project/docs/b.md"]
        XCTAssertEqual(MobileChangesFilter.files(files, category: .all, search: "", deliverables: deliverables).count, 3)
        XCTAssertEqual(MobileChangesFilter.files(files, category: .deliverables, search: "",
                                                  deliverables: deliverables).map(\.path), ["docs/b.md"])
    }

    func testSearchFiltersOnPathAndDisplay() {
        let files = [file("Sources/a.swift"), file("docs/b.md")]
        XCTAssertEqual(MobileChangesFilter.files(files, category: .all, search: "  SWIFT ",
                                                  deliverables: []).map(\.path), ["Sources/a.swift"])
        XCTAssertEqual(MobileChangesFilter.files(files, category: .all, search: "docs",
                                                  deliverables: []).map(\.path), ["docs/b.md"])
        XCTAssertTrue(MobileChangesFilter.files(files, category: .all, search: "missing", deliverables: []).isEmpty)
    }

    func testDeliverableMatchingAcceptsAbsoluteSuffixes() {
        XCTAssertTrue(MobileChangesFilter.matches(file: file("a/b.txt"), deliverables: ["/root/a/b.txt"]))
        XCTAssertTrue(MobileChangesFilter.matches(file: file("a/b.txt"), deliverables: ["a/b.txt"]))
        XCTAssertFalse(MobileChangesFilter.matches(file: file("a/b.txt"), deliverables: ["/root/x/a/b.txt.bak"]))
    }
}
