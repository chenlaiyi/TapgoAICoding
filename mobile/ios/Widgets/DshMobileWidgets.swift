import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DshMobileWidgets: WidgetBundle {
    var body: some Widget {
        DshTaskLiveActivityWidget()
    }
}

/// Live Activity for the running turn: lock-screen banner, expanded island, compact timer.
struct DshTaskLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DshTaskActivityAttributes.self) { context in
            LockScreenTaskView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("点点够", systemImage: "terminal")
                        .font(.caption.bold())
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Elapsed(startedAt: Date(timeIntervalSince1970: context.state.startedAt))
                        .font(.caption2.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.sessionTitle)
                            .font(.caption).lineLimit(1)
                        Text(context.state.detail.isEmpty ? "正在运行" : context.state.detail)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: "terminal")
            } compactTrailing: {
                Elapsed(startedAt: Date(timeIntervalSince1970: context.state.startedAt))
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: 54)
            } minimal: {
                Image(systemName: "terminal")
            }
        }
    }
}

private struct LockScreenTaskView: View {
    let context: ActivityViewContext<DshTaskActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal").font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.sessionTitle).font(.headline).lineLimit(1)
                Text(context.state.detail.isEmpty ? "正在运行" : context.state.detail)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Elapsed(startedAt: Date(timeIntervalSince1970: context.state.startedAt)).font(.caption.monospacedDigit())
        }
        .padding(12)
    }
}

/// Counts from the turn start without asking the app for further updates.
private struct Elapsed: View {
    let startedAt: Date

    var body: some View {
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .lineLimit(1)
    }
}
