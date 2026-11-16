import XCTest
import Foundation

final class MobileFailoverTests: XCTestCase {
    func testTransportFailuresSwitchRoutes() {
        for code in [URLError.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                     .notConnectedToInternet, .dnsLookupFailed, .secureConnectionFailed,
                     .serverCertificateUntrusted, .appTransportSecurityRequiresSecureConnection] {
            XCTAssertTrue(MobileFailover.isRouteFailure(URLError(code)), "\(code)")
        }
    }

    func testProtocolAndAuthFailuresKeepTheRoute() {
        XCTAssertFalse(MobileFailover.isRouteFailure(URLError(.badServerResponse)))
        XCTAssertFalse(MobileFailover.isRouteFailure(URLError(.userAuthenticationRequired)))
        XCTAssertFalse(MobileFailover.isRouteFailure(NSError(domain: "app", code: 1)))
        XCTAssertFalse(MobileFailover.isRouteFailure(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
    }
}
