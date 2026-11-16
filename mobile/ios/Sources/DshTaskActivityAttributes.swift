import ActivityKit
import Foundation

/// Content shared by the app and its widget extension for one running turn.
@available(iOS 16.1, *)
struct DshTaskActivityAttributes: ActivityAttributes {
    /// Snapshot rendered on the Lock Screen and in the Dynamic Island.
    struct ContentState: Codable, Hashable {
        /// When the running turn started; the widget renders it as a system timer.
        var startedAt: Date
        /// Current work, such as `正在运行命令 · git status`.
        var detail: String
        /// Whether the turn is still running.
        var running: Bool
    }

    /// Session title reported by the Host.
    var sessionTitle: String
    /// Project label shown under the title.
    var project: String
}
