import SwiftUI
import TapgoCore
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

/// Mac 端"移动端远程控制"弹窗 (v0.5.16 重写)。
///
/// 对标 ZCode 的扫码体验: Mac 内置 HTTP 服务, QR 直接编码
/// `http://<局域网IP>:<端口>/r/<token>`, iPhone 相机扫码立刻在 Safari 打开
/// H5 控制页, 不再依赖原生 iOS App 与 6 位配对码 (`MobilePairing` 保留为
/// 协议层历史, UI 不再使用)。
struct ConnectPhoneView: View {
    @EnvironmentObject private var remote: PhoneRemoteController
    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: NSImage? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            scanCard
            hintFooter
            doneFooter
        }
        .padding(24)
        .frame(width: 480)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            remote.startIfNeeded()
            qrImage = remote.makeQRImage()
        }
        .onChange(of: remote.linkString) { _ in
            qrImage = remote.makeQRImage()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.landscape.rotate")
                .font(.system(size: 26))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.accentColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text("移动端远程控制").font(.title3.weight(.semibold))
                Text("扫码或在手机上打开链接, 即可远程控制当前工作区。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - 扫码卡片

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "iphone")
                    .foregroundStyle(.tint)
                Text("手机扫码连接").font(.headline)
            }
            Text("用 iPhone 相机扫码, 在手机上打开这个工作区。")
                .font(.callout)
                .foregroundStyle(.secondary)

            statusCard

            HStack(alignment: .center, spacing: 0) {
                Text("无法扫码? 可以在手机上打开链接。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    remote.rotateToken()
                } label: {
                    Label("刷新二维码", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
                .disabled(!remote.isRunning)
                .accessibilityLabel("刷新二维码并轮换链接")
                Button {
                    remote.copyLink()
                } label: {
                    Label("复制链接", systemImage: "doc.on.doc")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
                .disabled(!remote.isRunning)
            }

            qrView
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    /// 运行状态卡: 服务状态 + 手机在线状态 + 停止/启动。
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(remote.phoneTitle).font(.subheadline.weight(.semibold))
                if remote.isRunning {
                    Circle()
                        .fill(remote.phoneConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    if remote.phoneConnected {
                        Text("iPhone")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
                Spacer()
                toggleButton
            }
            Text(remote.phoneSubtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if case .failed(let message) = remote.status {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var toggleButton: some View {
        if remote.isRunning {
            Button {
                remote.stop()
            } label: {
                Label("停止", systemImage: "link.badge.plus")
                    .font(.footnote)
            }
            .buttonStyle(.bordered)
        } else if remote.status == .stopped || isFailed {
            Button("启动服务") { remote.startIfNeeded() }
                .buttonStyle(.borderedProminent)
                .font(.footnote)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    private var isFailed: Bool {
        if case .failed = remote.status { return true }
        return false
    }

    // MARK: - QR

    @ViewBuilder
    private var qrView: some View {
        HStack(alignment: .center, spacing: 16) {
            Group {
                if let img = qrImage {
                    Image(nsImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text(remote.isRunning ? "QR 生成中" : "服务未开启")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 172, height: 172)
            .background(Color.white)
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 6) {
                Text("手机打开的链接").font(.subheadline.weight(.semibold))
                Text(remote.linkString.isEmpty ? "—" : remote.linkString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Label("本机局域网地址 \(remote.lanAddress ?? "不可用")",
                      systemImage: "wifi")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Footer

    private var hintFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("手机需与 Mac 在同一 Wi-Fi; 扫码后用 Safari 打开, 无需安装 App。", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label("手机端可以: 查看 / 切换会话 · 阅读对话与执行进度 · 发送新指令。", systemImage: "checkmark.seal")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var doneFooter: some View {
        HStack {
            Spacer()
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
    }
}

/// `PhoneRemoteController` 上给 UI 用的小推导, 收在这里避免控制器堆 UI 字符串。
extension PhoneRemoteController {
    var isRunning: Bool { status == .running }

    var phoneTitle: String {
        switch status {
        case .stopped: return "服务已停止"
        case .starting: return "服务启动中…"
        case .running: return phoneConnected ? "手机已连接" : "等待手机连接…"
        case .failed: return "服务启动失败"
        }
    }

    var phoneSubtitle: String {
        switch status {
        case .stopped:
            return "手机暂时无法控制当前工作区。"
        case .starting:
            return "正在监听端口…"
        case .running:
            return phoneConnected
                ? "手机可以控制当前工作区。"
                : "打开链接后手机会自动出现在这里。"
        case .failed:
            return "请点击『启动服务』重试。"
        }
    }
}
