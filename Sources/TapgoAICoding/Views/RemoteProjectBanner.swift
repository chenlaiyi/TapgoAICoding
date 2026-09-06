import SwiftUI
import TapgoCore

struct RemoteProjectBanner: View {
    @Environment(\.tapgoFontScale) private var appFontScale: AppFontScale

    let project: Project
    let host: RemoteHost?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "network").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(host.map { "远程 · \($0.alias)" } ?? "远程主机配置缺失")
                    .font(AppFont.scaled(.subheadline, multiplier: appFontScale.multiplier))
                Text(host.map { "\($0.user)@\($0.host):\($0.port) · \(project.remotePath ?? "目录未设置")" } ?? "请在设置中重新关联主机")
                    .font(AppFont.scaled(.caption, multiplier: appFontScale.multiplier))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if let host = host {
                Button {
                    var components = URLComponents()
                    components.scheme = "ssh"
                    components.user = host.user
                    components.host = host.host
                    components.port = host.port
                    if let url = components.url { NSWorkspace.shared.open(url) }
                } label: {
                    Label("在 Terminal 中打开", systemImage: "terminal")
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(DSHTheme.titlebarBg)
        .accessibilityElement(children: .contain)
    }
}
