import Foundation

/// Pairing-address rules shared by the connection list and the chat transport.
enum MobileConnectionAddress {
    /// Whether one pasted link may be paired: HTTPS anywhere, HTTP only on the local network.
    /// - Parameter url: Candidate pairing origin.
    /// - Returns: `true` when the app can dial this origin.
    static func isSupported(_ url: URL) -> Bool {
        guard let host = url.host, url.user == nil, url.password == nil,
              url.path.isEmpty || url.path == "/" else { return false }
        guard host.isEmpty == false else { return false }
        switch url.scheme {
        case "https": return true
        case "http": return isLocalNetworkHost(host)
        default: return false
        }
    }

    /// Whether a hostname names an address the phone can reach without the public internet.
    /// - Parameter hostname - WHATWG host from a parsed URL (IPv6 literals keep brackets).
    /// - Returns: `true` for loopback, private IPv4, link-local IPv4, mDNS `.local`, and local IPv6 addresses.
    static func isLocalNetworkHost(_ hostname: String) -> Bool {
        let host = hostname.lowercased()
        if host == "localhost" || host == "[::1]" { return true }
        if host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".")
        if parts.count == 4,
           parts.allSatisfy({ $0.allSatisfy(\.isNumber) && Int($0).map { $0 <= 255 } == true }),
           let first = Int(parts[0]), let second = Int(parts[1]) {
            switch (first, second) {
            case (10, _), (192, 168), (169, 254), (127, _): return true
            case (172, 16...31): return true
            default: return false
            }
        }
        if host.hasPrefix("["), let literal = host.split(separator: "]").first {
            let address = literal.dropFirst().lowercased()
            return address.hasPrefix("fc") || address.hasPrefix("fd")
                || address.hasPrefix("fe8") || address.hasPrefix("fe9")
                || address.hasPrefix("fea") || address.hasPrefix("feb")
        }
        return false
    }

    /// Canonical saved-computer identity for one pairing origin, including its scheme.
    /// - Parameter url - Pairing origin with at most a path of `/`.
    /// - Returns: `scheme://host[:port]`, or nil when the origin has no host.
    static func identity(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    /// WebSocket scheme matching one HTTP(S) origin.
    /// - Parameter origin - Host origin the app dials.
    /// - Returns: `ws` for a LAN HTTP Host, otherwise `wss`.
    static func webSocketScheme(for origin: URL) -> String {
        origin.scheme == "http" ? "ws" : "wss"
    }
}
