import ActivityKit
import Foundation

/// Publishes the running turn as a Live Activity so the Dynamic Island and Lock Screen keep it visible.
@available(iOS 16.1, *)
@MainActor
enum MobileLiveActivity {
    private static var current: Activity<DshTaskActivityAttributes>?
    private static var tokenTask: Task<Void, Never>?

    /// Receives the per-activity push token and the activity it belongs to.
    static var registrar: ((String, String) async -> Void)?
    /// Drops one activity's registration when it ends.
    static var unregisterer: ((String) async -> Void)?

    /// Starts the activity for a turn, or refreshes the one already showing it.
    /// - Parameters:
    ///   - sessionTitle: title shown in the expanded presentation.
    ///   - project: project label shown under the title.
    ///   - startedAt: when the turn started; the widget counts from here without further updates.
    ///   - detail: current work summary.
    static func show(sessionTitle: String, project: String, startedAt: Date, detail: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = DshTaskActivityAttributes.ContentState(startedAt: startedAt.timeIntervalSince1970,
                                                          detail: detail, running: true)
        if let activity = current {
            publish(state, to: activity)
            return
        }
        let attributes = DshTaskActivityAttributes(sessionTitle: sessionTitle, project: project)
        let requested: Activity<DshTaskActivityAttributes>?
        if #available(iOS 16.2, *) {
            requested = try? Activity.request(attributes: attributes,
                                              content: ActivityContent(state: state, staleDate: nil), pushType: .token)
        } else {
            requested = try? Activity.request(attributes: attributes, contentState: state, pushType: .token)
        }
        current = requested
        if let requested { observePushToken(of: requested) }
    }

    /// Ends every activity this app owns, including one left over from an earlier launch.
    static func end() {
        tokenTask?.cancel()
        tokenTask = nil
        for activity in Activity<DshTaskActivityAttributes>.activities {
            let id = activity.id
            if let unregisterer { Task { await unregisterer(id) } }
            end(activity)
        }
        current = nil
    }

    /// Streams ActivityKit push tokens to the paired Host so background updates keep working.
    /// - Parameter activity: activity whose token changes.
    private static func observePushToken(of activity: Activity<DshTaskActivityAttributes>) {
        tokenTask?.cancel()
        guard #available(iOS 16.2, *) else { return }
        tokenTask = Task {
            for await token in activity.pushTokenUpdates {
                let hex = token.map { String(format: "%02x", $0) }.joined()
                if let registrar { await registrar(hex, activity.id) }
            }
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
