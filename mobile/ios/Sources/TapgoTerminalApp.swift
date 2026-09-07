import SwiftUI

@main
struct TapgoTerminalApp: App {
    @StateObject private var pairing = PairingStore()

    init() {
        // 与 Tapgo AICoding Mac 端约定一致的 URL Scheme 注册: tapgo-pair://
        // 触发配对流程; iOS 端通过 .onOpenURL 接收。

        #if DEBUG
        // 仅 Debug 构建: 启动时若环境变量 TAPGO_FORCE_PAIRED=1, 注入一个示例 Mac
        // 让 DashboardView 可被直接截图回归。
        if ProcessInfo.processInfo.environment["TAPGO_FORCE_PAIRED"] == "1" {
            let store = PairingStore()
            let demo = MobilePairing.PairedMac(
                deviceId: "demo-mac",
                hostname: "JKmacmini",
                host: "100.71.223.108",
                port: 8723,
                pairedAt: Date()
            )
            try? (UserDefaults.standard).set(
                try? JSONEncoder().encode(demo),
                forKey: "tapgo.pair.lastPairedMac"
            )
        }
        #endif
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
        case .paired:
            DashboardView()
        }
    }
}
