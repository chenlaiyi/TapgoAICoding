import SwiftUI

/// Finalized-message actions remain separate from the Markdown and live generation views.
struct MobileReplyActionsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let text: String
    let timestamp: Double?
    let rating: MobileMessageFeedback.Rating?
    let feedbackEnabled: Bool
    let feedbackBusy: Bool
    let pendingRating: MobileMessageFeedback.Rating?
    let feedbackError: String?
    let forkEnabled: Bool
    let forkBusy: Bool
    let rate: (MobileMessageFeedback.Rating) -> Void
    let fork: () -> Void
    let retryFeedback: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if dynamicTypeSize.isAccessibilitySize {
                actionButtons
                timeLabel
            } else {
                HStack(spacing: 6) { actionButtons; timeLabel; Spacer(minLength: 0) }
            }
            if let feedbackError {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(feedbackError).font(.caption).foregroundStyle(.orange)
                    Button("刷新反馈", action: retryFeedback).font(.caption).frame(minHeight: 44)
                }
            }
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .milliseconds(1500))
            if !Task.isCancelled { copied = false }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            Button {
                UIPasteboard.general.string = text
                copied = true
            } label: {
                Image(systemName: copied ? "checkmark" : "square.on.square")
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(copied ? "已复制回复" : "复制回复")
            Button { rate(.positive) } label: {
                ZStack {
                    if feedbackBusy && pendingRating == .positive { ProgressView() }
                    else { Image(systemName: rating == .positive ? "hand.thumbsup.fill" : "hand.thumbsup") }
                }
                .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(rating == .positive ? "撤回赞" : "赞这条回复")
            .disabled(!feedbackEnabled || feedbackBusy)
            Button { rate(.negative) } label: {
                ZStack {
                    if feedbackBusy && pendingRating == .negative { ProgressView() }
                    else { Image(systemName: rating == .negative ? "hand.thumbsdown.fill" : "hand.thumbsdown") }
                }
                .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(rating == .negative ? "撤回踩" : "踩这条回复")
            .disabled(!feedbackEnabled || feedbackBusy)
            Menu {
                Button("从这条回复分支新对话", action: fork)
            } label: {
                if forkBusy { ProgressView().frame(width: 44, height: 44) }
                else { Image(systemName: "arrow.triangle.branch").frame(width: 44, height: 44) }
            }
            .accessibilityLabel("分支新对话")
            .disabled(!forkEnabled || forkBusy)
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
    }

    @ViewBuilder private var timeLabel: some View {
        if let timestamp, timestamp.isFinite {
            let date = Date(timeIntervalSince1970: timestamp / 1000)
            Text(date, format: .dateTime.weekday(.wide).hour().minute())
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityLabel(date.formatted(date: .complete, time: .shortened))
                .accessibilityIdentifier("replyTimestamp")
        }
    }
}
