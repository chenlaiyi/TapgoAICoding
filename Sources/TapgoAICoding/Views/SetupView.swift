import SwiftUI
import AppKit

struct SetupView: View {
    let error: SetupError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)
            Text(L10n.setupHeadline)
                .font(.title2)
                .bold()
            Text(L10n.setupBody)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)
            if let detail = (error.errorDescription) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.setupConsole)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("cd ~/TapgoAICoding && ./scripts/init-tapgo.sh --from-file <key_file>")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(DSHTheme.surface, in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.open(
                        URL(fileURLWithPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("TapgoAICoding/scripts").path)
                    )
                } label: {
                    Label(L10n.setupOpenScripts, systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(L10n.setupOpenScripts)

                Button {
                    onRetry()
                } label: {
                    Label(L10n.setupRetry, systemImage: "arrow.clockwise")
                }
                .buttonStyle(DSHPrimaryButtonStyle())
                .accessibilityLabel(L10n.setupRetry)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
