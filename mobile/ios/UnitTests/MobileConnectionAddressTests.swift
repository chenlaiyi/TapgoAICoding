import XCTest
import Foundation

final class MobileConnectionAddressTests: XCTestCase {
    func testAcceptsHTTPSAnywhereAndHTTPOnTheLocalNetwork() throws {
        for value in ["https://mac.remote.example/?token=x", "http://192.168.1.20:19389/?token=x",
                      "http://mac-mini.local:19389/?token=x", "http://127.0.0.1:19389/?token=x",
                      "http://10.0.0.7:19389/?token=x"] {
            XCTAssertTrue(MobileConnectionAddress.isSupported(try XCTUnwrap(URL(string: value))), value)
        }
    }

    func testRejectsPublicHTTPAndMalformedPaths() throws {
        for value in ["http://8.8.8.8:19389/", "http://phone.example/?token=x", "ftp://192.168.1.20/?token=x",
                      "https://mac.remote.example/path?token=x"] {
            XCTAssertFalse(MobileConnectionAddress.isSupported(try XCTUnwrap(URL(string: value))), value)
        }
    }

    func testIdentityKeepsTheSchemeAndPort() throws {
        XCTAssertEqual(MobileConnectionAddress.identity(for: try XCTUnwrap(URL(string: "http://192.168.1.20:19389/?token=x"))),
                       "http://192.168.1.20:19389")
        XCTAssertEqual(MobileConnectionAddress.identity(for: try XCTUnwrap(URL(string: "https://mac.remote.example/?token=x"))),
                       "https://mac.remote.example")
    }

    func testWebSocketSchemeFollowsTheOrigin() throws {
        XCTAssertEqual(MobileConnectionAddress.webSocketScheme(for: try XCTUnwrap(URL(string: "http://192.168.1.20:19389"))), "ws")
        XCTAssertEqual(MobileConnectionAddress.webSocketScheme(for: try XCTUnwrap(URL(string: "https://mac.remote.example"))), "wss")
    }
}
