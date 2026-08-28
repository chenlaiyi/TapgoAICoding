import SwiftUI

/// 已配对后的工作面板。
///
/// v0.5.6 仅做最小骨架：展示已配对 Mac 的元信息，提供"取消配对"按钮，
/// 真正跟 Mac 通信（心跳、消息推送、AI 同步）由后续版本接入。
struct DashboardView: View {
    let macInfo: MobilePairing.PairedMac
    let connected: Bool

    @EnvironmentObject var pairing: PairingStore

    var body: some View {
        NavigationStack {
            List {
                Section("已配对 Mac") {
                    LabeledContent("设备 ID", value: macInfo.deviceId)
                    LabeledContent("主机名", value: macInfo.hostname)
                    LabeledContent("主机", value: macInfo.host)
                    LabeledContent("端口", value: String(macInfo.port))
                    LabeledContent("配对时间",
                                   value: macInfo.pairedAt.formatted(date: .abbreviated,
                                                                    time: .shortened))
                }
                Section("连接状态") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(connected ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        Text(connected ? "已连接" : "未连接（等待 Bonjour 发现）")
                            .font(.subheadline)
                    }
                }
                Section {
                    Button(role: .destructive) {
                        pairing.unpair()
                    } label: {
                        Text("取消配对")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("点点够终端")
        }
    }
}
