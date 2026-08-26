import SwiftUI
import TapgoCore
import AppKit

struct SetupView: View {
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    let error: SetupError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)
            Text(L10n.setupHeadline)
                .font(AppFont.scaled(.title2, multiplier: appFontScale.multiplier))
                .bold()
            Text(L10n.setupBody)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)
            if let detail = (error.errorDescription) {
                Text(detail)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.setupConsole)
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                Text("cd ~/TapgoAICoding && ./scripts/init-tapgo.sh --from-file <key_file>")
                    .font(AppFont.monoScaled(size: 13, multiplier: appFontScale.multiplier))
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
