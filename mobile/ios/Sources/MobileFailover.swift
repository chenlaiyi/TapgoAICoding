import Foundation

/// Decides when a failed route should switch to the paired fallback.
enum MobileFailover {
    /// Whether one thrown error means the route itself is unreachable.
    /// - Parameter error: Error thrown while dialing a paired origin.
    /// - Returns: `true` for connection, DNS, timeout, lost-network, and TLS trust failures.
    static func isRouteFailure(_ error: Error) -> Bool {
        guard let failure = error as? URLError else { return false }
        switch failure.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
             .notConnectedToInternet, .dnsLookupFailed, .resourceUnavailable,
             .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .clientCertificateRejected,
             .appTransportSecurityRequiresSecureConnection:
            return true
        default:
            return false
        }
    }
}
