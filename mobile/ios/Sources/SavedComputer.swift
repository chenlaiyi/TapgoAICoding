import Foundation

struct SavedComputer: Codable, Equatable, Identifiable {
    /// Preferred origin, which also stays the stable identity for preferences and the list.
    let id: String
    var name: String
    /// Preferred pairing URL, normally the plain-HTTP LAN link.
    var url: String
    var sourceName: String? = nil
    var customName: String? = nil
    /// HTTPS relay link the same token also authenticates, when the pairing provided one.
    var fallbackURL: String? = nil
    /// Pairing URL currently dialed; nil keeps the preferred route.
    var activeURL: String? = nil

    /// The pairing URL the app dials now.
    var connectionURL: String { activeURL ?? url }

    /// Origin matching `connectionURL`, or the preferred origin when it cannot be parsed.
    var origin: String {
        guard let parsed = URL(string: connectionURL), let scheme = parsed.scheme,
              let host = parsed.host else { return id }
        return "\(scheme)://\(host)\(parsed.port.map { ":\($0)" } ?? "")"
    }

    /// Whether the app is dialing the fallback route instead of the preferred one.
    var usingFallback: Bool { activeURL != nil }
}
