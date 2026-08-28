import SwiftUI

@main
struct TapgoTerminalApp: App {
    @StateObject private var pairing = PairingStore()

    init() {
        // 与 Tapgo AICoding Mac 端约定一致的 URL Scheme 注册: tapgo-pair://
        // 触发配对流程; iOS 端通过 .onOpenURL 接收。
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(pairing)
                .onOpenURL { url in
                    pairing.handleIncomingURL(url)
                }
        }
    }
}

/// 根视图: 启动时按配对状态分流。
struct RootView: View {
    @EnvironmentObject var pairing: PairingStore

    var body: some View {
        switch pairing.state {
        case .unpaired:
            PairingView()
        case .paired(let macInfo, let connected):
            DashboardView(macInfo: macInfo, connected: connected)
        }
    }
}
