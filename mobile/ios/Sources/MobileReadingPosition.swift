import Foundation

/// Persists the transcript row a reader left at, per paired computer and conversation.
enum MobileReadingPosition {
    /// Storage key for one conversation's reading anchor.
    /// - Parameters:
    ///   - computerID: stable paired-computer identity.
    ///   - sessionID: conversation the anchor belongs to.
    /// - Returns: the defaults key.
    static func key(computerID: String, sessionID: String) -> String {
        "mobile.reading.\(computerID).\(sessionID)"
    }

    /// Reads the stored transcript row.
    /// - Parameters:
    ///   - computerID: stable paired-computer identity.
    ///   - sessionID: conversation the anchor belongs to.
    ///   - defaults: defaults database; tests pass an isolated suite.
    /// - Returns: the stored presentation identity, or nil when the conversation follows the latest reply.
    static func load(computerID: String, sessionID: String, defaults: UserDefaults = .standard) -> String? {
        let value = defaults.string(forKey: key(computerID: computerID, sessionID: sessionID))
        return value?.isEmpty == false ? value : nil
    }

    /// Stores one transcript row, or clears the key when the reader is at the latest reply.
    /// - Parameters:
    ///   - anchorID: row's presentation identity.
    ///   - computerID: stable paired-computer identity.
    ///   - sessionID: conversation the anchor belongs to.
    ///   - defaults: defaults database; tests pass an isolated suite.
    static func save(_ anchorID: String?, computerID: String, sessionID: String,
                     defaults: UserDefaults = .standard) {
        let key = key(computerID: computerID, sessionID: sessionID)
        guard let anchorID, !anchorID.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(anchorID, forKey: key)
    }

    /// Removes one conversation's reading anchor.
    /// - Parameters:
    ///   - computerID: stable paired-computer identity.
    ///   - sessionID: conversation the anchor belongs to.
    ///   - defaults: defaults database; tests pass an isolated suite.
    static func clear(computerID: String, sessionID: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(computerID: computerID, sessionID: sessionID))
    }
}
