import XCTest
import Foundation

final class MobileFileBrowserTests: XCTestCase {
    func testJoinsAndWalksPaths() {
        XCTAssertEqual(MobileFileBrowser.child("src", of: ""), "src")
        XCTAssertEqual(MobileFileBrowser.child("main.swift", of: "src/app"), "src/app/main.swift")
        XCTAssertEqual(MobileFileBrowser.parent(of: "src/app/main.swift"), "src/app")
        XCTAssertEqual(MobileFileBrowser.parent(of: "src"), "")
        XCTAssertEqual(MobileFileBrowser.parent(of: ""), "")
        XCTAssertEqual(MobileFileBrowser.display(""), "/")
        XCTAssertEqual(MobileFileBrowser.display("src"), "src")
    }

    func testSortsDirectoriesBeforeFilesByName() {
        let entries = [
            MobileDirectoryEntry(name: "zeta.txt", type: "file", size: 12),
            MobileDirectoryEntry(name: "Alpha", type: "directory", size: nil),
            MobileDirectoryEntry(name: "beta.txt", type: "file", size: nil),
            MobileDirectoryEntry(name: "beta", type: "directory", size: nil),
        ]
        XCTAssertEqual(MobileFileBrowser.sorted(entries).map(\.name),
                       ["Alpha", "beta", "beta.txt", "zeta.txt"])
    }

    func testDecodesTheHostListing() throws {
        let json = #"{"path":"src","entries":[{"name":"main.swift","type":"file","size":42},{"name":"sub","type":"directory"}],"truncated":false}"#
        let listing = try JSONDecoder().decode(MobileDirectoryListing.self, from: Data(json.utf8))
        XCTAssertEqual(listing.path, "src")
        XCTAssertEqual(listing.entries.count, 2)
        XCTAssertTrue(listing.entries[1].isDirectory)
        XCTAssertEqual(listing.entries[0].size, 42)
        XCTAssertFalse(listing.truncated)
    }
}
