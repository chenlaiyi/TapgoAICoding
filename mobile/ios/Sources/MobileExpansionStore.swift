import Foundation

/// Remembers which turn disclosures a reader expanded, per paired computer and conversation.
enum MobileExpansionStore {
    /// Newest turns kept; older entries are dropped when the map grows past this.
    static let maxTurns = 200

    /// Storage key for one conversation's disclosure states.
    /// - Parameters:
    ///   - computerID: stable paired-computer identity.
    ///   - sessionID: conversation the states belong to.
    /// - Returns: the defaults key.
    static func key(computerID: String, sessionID: String) -> String {
        "mobile.expansion.\(computerID).\(sessionID)"
    }

    /// Reads the stored expansion states.
    /// - Parameters:
    ///   - computerID: stable paired-computer identity.
    ///   - sessionID: conversation the states belong to.
    ///   - defaults: defaults database; tests pass an isolated suite.
    /// - Returns: turn number to expanded flag.
    static func load(computerID: String, sessionID: String, defaults: UserDefaults = .standard) -> [Int: Bool] {
        guard let data = defaults.data(forKey: key(computerID: computerID, sessionID: sessionID)),
              let stored = try? JSONDecoder().decode([String: Bool].self, from: data) else { return [:] }
        var states: [Int: Bool] = [:]
        for (raw, value) in stored {
            if let turn = Int(raw) { states[turn] = value }
        }
        return states
    }

    /// Stores the expansion states, keeping only the newest turns.
    /// - Parameters:
    ///   - states: turn number to expanded flag.
    ///   - computerID: stable paired-computer identity.
    ///   - sessionID: conversation the states belong to.
    ///   - defaults: defaults database; tests pass an isolated suite.
    static func save(_ states: [Int: Bool], computerID: String, sessionID: String,
                     defaults: UserDefaults = .standard) {
        let key = key(computerID: computerID, sessionID: sessionID)
        guard !states.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        let newest = states.keys.sorted(by: >).prefix(maxTurns)
        var stored: [String: Bool] = [:]
        for turn in newest { stored[String(turn)] = states[turn] }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key)
    }

    /// Removes one conversation's expansion states.
    /// - Parameters:
    ///   - computerID: stable paired-computer identity.
    ///   - sessionID: conversation the states belong to.
    ///   - defaults: defaults database; tests pass an isolated suite.
    static func clear(computerID: String, sessionID: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(computerID: computerID, sessionID: sessionID))
    }
}
