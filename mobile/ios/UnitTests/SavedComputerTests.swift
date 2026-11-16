import XCTest
import Foundation

final class SavedComputerTests: XCTestCase {
    func testLegacyRecordWithoutRoutesStillDecodes() throws {
        let json = #"{"id":"https://mac.remote.example","name":"Mac","url":"https://mac.remote.example/?token=relay"}"#
        let computer = try JSONDecoder().decode(SavedComputer.self, from: Data(json.utf8))
        XCTAssertEqual(computer.connectionURL, "https://mac.remote.example/?token=relay")
        XCTAssertEqual(computer.origin, "https://mac.remote.example")
        XCTAssertFalse(computer.usingFallback)
    }

    func testFallbackRouteChangesTheDialedOrigin() {
        let computer = SavedComputer(id: "http://192.168.1.20:19389", name: "Mac",
                                     url: "http://192.168.1.20:19389/?token=lan",
                                     fallbackURL: "https://mac.remote.example/?token=relay",
                                     activeURL: "https://mac.remote.example/?token=relay")
        XCTAssertTrue(computer.usingFallback)
        XCTAssertEqual(computer.connectionURL, "https://mac.remote.example/?token=relay")
        XCTAssertEqual(computer.origin, "https://mac.remote.example")
    }

    func testPreferredOriginKeepsItsPort() {
        let computer = SavedComputer(id: "http://192.168.1.20:19389", name: "Mac",
                                     url: "http://192.168.1.20:19389/?token=lan")
        XCTAssertEqual(computer.origin, "http://192.168.1.20:19389")
        XCTAssertFalse(computer.usingFallback)
    }
}
