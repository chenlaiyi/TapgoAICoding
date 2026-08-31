import Combine
import Sparkle

/// Owns Sparkle for the lifetime of the process and exposes its readiness to
/// SwiftUI. Feed URL, signing key and automatic-update policy live in
/// Info.plist so Sparkle remains the single source of truth for preferences.
@MainActor
final class AppUpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

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
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
