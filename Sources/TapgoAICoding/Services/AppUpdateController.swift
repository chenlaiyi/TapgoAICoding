import Combine
import Sparkle

/// Owns Sparkle for the lifetime of the process and exposes its readiness to
/// SwiftUI. Feed URL, signing key and automatic-update policy live in
/// Info.plist so Sparkle remains the single source of truth for preferences.
@MainActor
final class AppUpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    /// True when the latest background check found a newer release. Drives the
    /// sidebar update badge: blue "update available" icon vs grey "check" arrow.
    @Published private(set) var updateFound = false

    private let updaterController: SPUStandardUpdaterController

    init() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)

        // Sparkle owns the scheduled cycle. This one immediate background
        // check makes a newly launched App discover a GitHub release without
        // waiting for the next interval, while respecting the persisted user
        // preference.
        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }

        // Track the outcome of every check so the sidebar badge can reflect
        // "update available" without the user having to open a menu.
        // Sparkle 2.x only exports these as ObjC NSString constants (no Swift
        // Notification.Name overlay), so reference them by literal name.
        NotificationCenter.default.publisher(for: Notification.Name("SUUpdaterDidFindValidUpdateNotification"))
            .receive(on: RunLoop.main)
            .map { _ in true }
            .assign(to: &$updateFound)
        NotificationCenter.default.publisher(for: Notification.Name("SUUpdaterDidNotFindUpdateNotification"))
            .receive(on: RunLoop.main)
            .map { _ in false }
            .assign(to: &$updateFound)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
