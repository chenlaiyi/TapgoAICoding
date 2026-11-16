import Foundation

/// Remembers which step process rows a reader expanded, per paired computer and conversation.
enum MobileExpansionStore {
    /// Newest steps kept; older entries are dropped when the map grows past this.
    static let maxEntries = 400

    /// Storage key for one conversation's disclosure states.
    /// - Parameters:
    ///   - computerID: stable paired-computer identity.
    ///   - sessionID: conversation the states belong to.
    /// - Returns: the defaults key.
    static func key(computerID: String, sessionID: String) -> String {
        "mobile.expansion.\(computerID).\(sessionID)"
    }

    /// Identity of one step's process row.
    /// - Parameters:
    ///   - turn: durable turn number.
    ///   - step: step number inside the turn.
    /// - Returns: the persisted entry key.
    static func entryKey(turn: Int, step: Int) -> String {
        "\(turn):\(step)"
    }

    /// Reads the stored step expansion states.
    /// - Parameters:
    ///   - computerID: stable paired-computer identity.
    ///   - sessionID: conversation the states belong to.
    ///   - defaults: defaults database; tests pass an isolated suite.
    /// - Returns: `turn:step` identity to expanded flag; legacy turn-only entries are ignored.
    static func load(computerID: String, sessionID: String, defaults: UserDefaults = .standard) -> [String: Bool] {
        guard let data = defaults.data(forKey: key(computerID: computerID, sessionID: sessionID)),
              let stored = try? JSONDecoder().decode([String: Bool].self, from: data) else { return [:] }
        return stored.filter { $0.key.contains(":") }
    }

    /// Stores the step expansion states, keeping only the newest steps.
    /// - Parameters:
    ///   - states: `turn:step` identity to expanded flag.
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
        let kept = Dictionary(uniqueKeysWithValues: states.sorted { order($0.key) > order($1.key) }
            .prefix(maxEntries).map { ($0.key, $0.value) })
        guard let data = try? JSONEncoder().encode(kept) else { return }
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

    /// Sorts step identities by turn, then step.
    /// - Parameter key: stored `turn:step` identity.
    /// - Returns: a comparable pair.
    private static func order(_ key: String) -> (Int, Int) {
        let parts = key.split(separator: ":").compactMap { Int($0) }
        return (parts.first ?? 0, parts.count > 1 ? parts[1] : 0)
    }
}
