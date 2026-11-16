import ActivityKit
import Foundation

/// Publishes the running turn as a Live Activity so the Dynamic Island and Lock Screen keep it visible.
@available(iOS 16.1, *)
@MainActor
enum MobileLiveActivity {
    private static var current: Activity<DshTaskActivityAttributes>?

    /// Starts the activity for a turn, or refreshes the one already showing it.
    /// - Parameters:
    ///   - sessionTitle: title shown in the expanded presentation.
    ///   - project: project label shown under the title.
    ///   - startedAt: when the turn started; the widget counts from here without further updates.
    ///   - detail: current work summary.
    static func show(sessionTitle: String, project: String, startedAt: Date, detail: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = DshTaskActivityAttributes.ContentState(startedAt: startedAt, detail: detail, running: true)
        if let activity = current {
            publish(state, to: activity)
            return
        }
        let attributes = DshTaskActivityAttributes(sessionTitle: sessionTitle, project: project)
        current = try? Activity.request(attributes: attributes, contentState: state, pushType: nil)
    }

    /// Ends every activity this app owns, including one left over from an earlier launch.
    static func end() {
        current = nil
        for activity in Activity<DshTaskActivityAttributes>.activities {
            end(activity)
        }
    }

    private static func publish(_ state: DshTaskActivityAttributes.ContentState,
                                to activity: Activity<DshTaskActivityAttributes>) {
        if #available(iOS 16.2, *) {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            Task { await activity.update(using: state) }
        }
    }

    private static func end(_ activity: Activity<DshTaskActivityAttributes>) {
        if #available(iOS 16.2, *) {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        } else {
            Task { await activity.end(dismissalPolicy: .immediate) }
        }
    }
}
