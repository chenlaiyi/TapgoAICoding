import Foundation
import SwiftUI

/// Microphone control before Send, with the same idle and recording states in both composers.
struct MobileVoiceButton: View {
    @ObservedObject var voice: MobileVoiceInput
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: voice.recording ? "stop.fill" : "mic")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(voice.recording ? "停止语音输入" : "语音输入")
    }
}

/// Recording bar: cancel, live level dots, stop, and send.
struct MobileRecordingBar: View {
    @ObservedObject var voice: MobileVoiceInput
    let onCancel: () -> Void
    let onStop: () -> Void
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Color(uiColor: .secondarySystemBackground), in: Circle())
            }
            .frame(width: 44, height: 44)
            .accessibilityLabel("取消语音输入")
            TimelineView(.animation(minimumInterval: 0.1)) { context in
                let tick = Int(context.date.timeIntervalSince1970 * 10)
                HStack(spacing: 3) {
                    ForEach(0..<28, id: \.self) { index in
                        let pattern = 0.35 + 0.65 * abs(sin(Double(index) * 0.55 + Double(tick) * 0.25))
                        let height = 3 + voice.level * 26 * pattern
                        Capsule()
                            .fill(Color.secondary.opacity(0.45))
                            .frame(width: 2, height: max(3, height))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            .frame(width: 44, height: 44)
            .accessibilityLabel("停止语音输入")
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.blue, in: Circle())
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("发送")
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .mobileGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
