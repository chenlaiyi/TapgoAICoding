import Foundation

/// Remembers which code blocks a reader expanded, per paired computer and conversation.
enum MobileCodeExpansionStore {
    /// Newest blocks kept; oldest entries are dropped when the map grows past this.
    static let maxBlocks = 500

    /// Storage key for one conversation's code-block states.
    /// - Parameters:
    ///   - computerID: stable paired-computer identity.
    ///   - sessionID: conversation the states belong to.
    /// - Returns: the defaults key.
    static func key(computerID: String, sessionID: String) -> String {
        "mobile.expansion.code.\(computerID).\(sessionID)"
    }

    /// Reads the stored code-block states.
    /// - Parameters:
    ///   - computerID: stable paired-computer identity.
    ///   - sessionID: conversation the states belong to.
    ///   - defaults: defaults database; tests pass an isolated suite.
    /// - Returns: `line:block` identity to expanded flag.
    static func load(computerID: String, sessionID: String, defaults: UserDefaults = .standard) -> [String: Bool] {
        guard let data = defaults.data(forKey: key(computerID: computerID, sessionID: sessionID)),
              let stored = try? JSONDecoder().decode([String: Bool].self, from: data) else { return [:] }
        return stored
    }

    /// Stores the code-block states, keeping a bounded number of entries.
    /// - Parameters:
    ///   - states: `line:block` identity to expanded flag.
    ///   - computerID: stable paired-computer identity.
    ///   - sessionID: conversation the states belong to.
    ///   - defaults: defaults database; tests pass an isolated suite.
    static func save(_ states: [String: Bool], computerID: String, sessionID: String,
                     defaults: UserDefaults = .standard) {
        let key = key(computerID: computerID, sessionID: sessionID)
        guard !states.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        let kept = Dictionary(uniqueKeysWithValues: states.sorted { $0.key < $1.key }.prefix(maxBlocks)
            .map { ($0.key, $0.value) })
        guard let data = try? JSONEncoder().encode(kept) else { return }
        defaults.set(data, forKey: key)
    }

    /// Removes one conversation's code-block states.
    /// - Parameters:
    ///   - computerID: stable paired-computer identity.
    ///   - sessionID: conversation the states belong to.
    ///   - defaults: defaults database; tests pass an isolated suite.
    static func clear(computerID: String, sessionID: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(computerID: computerID, sessionID: sessionID))
    }
}
