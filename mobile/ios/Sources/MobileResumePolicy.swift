import Foundation

/// Decides when a foreground return or a quiet poll must read Host state again.
enum MobileResumePolicy {
    /// iOS suspends app sockets shortly after backgrounding; after this absence an open-looking socket may deliver nothing.
    static let staleSocketAfter: TimeInterval = 3
    /// Quiet session-list polls read the model catalog and balances at most this often.
    static let composerRefreshInterval: TimeInterval = 60

    /// Whether a conversation socket must be replaced when the app becomes active.
    /// - Parameters:
    ///   - backgroundedAt: when the scene entered the background, or nil when it never left the foreground.
    ///   - now: current clock.
    /// - Returns: `true` when the absence lasted long enough for iOS to suspend the socket.
    static func mustReconnect(backgroundedAt: Date?, now: Date = Date()) -> Bool {
        guard let backgroundedAt else { return false }
        return now.timeIntervalSince(backgroundedAt) >= staleSocketAfter
    }

    /// Whether a session-list load should also read the model catalog and balances.
    /// - Parameters:
    ///   - lastRefreshedAt: when they were last requested for this computer, or nil when never.
    ///   - quietly: whether the load is a background poll rather than a user-visible refresh.
    ///   - hasModels: whether a model catalog is already shown.
    ///   - now: current clock.
    /// - Returns: `true` for visible refreshes, missing catalogs, and quiet polls past the refresh interval.
    static func shouldRefreshComposer(lastRefreshedAt: Date?, quietly: Bool, hasModels: Bool,
                                      now: Date = Date()) -> Bool {
        guard quietly, hasModels, let lastRefreshedAt else { return true }
        return now.timeIntervalSince(lastRefreshedAt) >= composerRefreshInterval
    }
}
