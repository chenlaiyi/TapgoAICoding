import Foundation

/// Text and mode kept for one unsent composer draft.
struct MobileDraft: Codable, Equatable {
    var text: String
    var mode: MobileComposerMode
}

/// Persists unsent composer text and mode per paired computer and conversation.
enum MobileDraftStore {
    /// Longest text kept; longer drafts are truncated rather than rejected.
    static let maxCharacters = 8_000

    /// Storage key for one conversation's draft.
    /// - Parameters:
    ///   - computerID: stable paired-computer identity.
    ///   - sessionID: conversation the draft belongs to.
    /// - Returns: the defaults key.
    static func sessionKey(computerID: String, sessionID: String) -> String {
        "mobile.draft.\(computerID).\(sessionID)"
    }

    /// Storage key for one computer's new-conversation draft.
    /// - Parameter computerID: stable paired-computer identity.
    /// - Returns: the defaults key.
    static func newConversationKey(computerID: String) -> String {
        "mobile.draft.\(computerID).new"
    }

    /// Reads one stored draft.
    /// - Parameters:
    ///   - key: key from `sessionKey` or `newConversationKey`.
    ///   - defaults: defaults database; tests pass an isolated suite.
    /// - Returns: the draft, or nil when nothing meaningful was stored.
    static func load(key: String, defaults: UserDefaults = .standard) -> MobileDraft? {
        guard let data = defaults.data(forKey: key),
              let draft = try? JSONDecoder().decode(MobileDraft.self, from: data),
              !(draft.text.isEmpty && draft.mode == .message) else { return nil }
        return draft
    }

    /// Stores one draft, or clears the key when it holds no meaningful input.
    /// - Parameters:
    ///   - draft: text and mode to keep.
    ///   - key: key from `sessionKey` or `newConversationKey`.
    ///   - defaults: defaults database; tests pass an isolated suite.
    static func save(_ draft: MobileDraft, key: String, defaults: UserDefaults = .standard) {
        var limited = draft
        limited.text = String(draft.text.prefix(maxCharacters))
        guard !(limited.text.isEmpty && limited.mode == .message),
              let data = try? JSONEncoder().encode(limited) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    /// Removes one stored draft.
    /// - Parameters:
    ///   - key: key from `sessionKey` or `newConversationKey`.
    ///   - defaults: defaults database; tests pass an isolated suite.
    static func clear(key: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
