import SwiftUI
import TapgoCore
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

/// Mac 端"连接手机"弹窗。
///
/// 显示当前 6 位配对码、QR、倒计时进度与上次配对状态。
/// 真实 Bonjour 长链接在 v0.5.6 接入; v0.5.5 只生成 URL, QR 用 CoreImage 渲染。
struct ConnectPhoneView: View {
    @StateObject private var pairing = MobilePairingStore()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            codeBlock
            qrBlock
            statusBlock
            footer
        }
        .padding(24)
        .frame(width: 460)
        .background(Color(.windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("连接手机 · 点点够终端").font(.title3.weight(.semibold))
                Text("用 iPhone 扫码或手动输入配对码, 即可在手机端继续会话。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var codeBlock: some View {
        VStack(spacing: 10) {
            Text(pairing.code.value)
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .tracking(4)
                .foregroundStyle(.primary)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .foregroundStyle(.secondary)
                Text("\(pairing.code.remainingSeconds()) 秒后自动轮换")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView(value: pairing.progressFraction)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
            }
        }
    }

    private var qrBlock: some View {
        HStack(alignment: .center, spacing: 16) {
            Group {
                if let img = pairing.qrImage {
                    Image(nsImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.15))
                        .overlay(Text("QR 生成中").font(.footnote).foregroundStyle(.secondary))
                }
            }
            .frame(width: 140, height: 140)
            .background(Color.white)
            .cornerRadius(8)
            VStack(alignment: .leading, spacing: 6) {
                Text("扫码配对").font(.subheadline.weight(.semibold))
                Text(pairing.pairURLString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .truncationMode(.middle)
                Button {
                    pairing.copyURLToPasteboard()
                } label: {
                    Label("复制链接", systemImage: "doc.on.doc")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var statusBlock: some View {
        HStack(spacing: 8) {
            statusDot
            Text(statusText).font(.footnote).foregroundStyle(.secondary)
            Spacer()
            if pairing.state.isPaired {
                Button("解除配对", role: .destructive) {
                    pairing.unpair()
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("刷新配对码") { pairing.regenerate() }
                .buttonStyle(.bordered)
            Spacer()
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch pairing.state {
        case .unpaired: return .gray
        case .paired(_, let connected): return connected ? .green : .orange
        }
    }

    private var statusText: String {
        switch pairing.state {
        case .unpaired:
            return "未配对"
        case .paired(let mac, let connected):
            if connected {
                return "已连接 · \(mac.hostname)"
            } else {
                return "已配对 · 等待 iOS 端建立链接 (\(mac.hostname))"
            }
        }
    }
}

/// Mac 端配对状态机。封装 PairCode 倒计时、QR 渲染与 UserDefaults 持久化。
/// Bonjour 监听 / 真实 TCP 握手在 v0.5.6 接入, 当前 UI 主要展示协议层面。
@MainActor
final class MobilePairingStore: ObservableObject {

    @Published private(set) var code: MobilePairing.PairCode
    @Published private(set) var state: MobilePairing.State
    @Published private(set) var qrImage: NSImage? = nil
    @Published private(set) var pairURLString: String = ""

    private var timer: Timer? = nil
    private static let macDeviceIdKey = MobilePairing.StorageKeys.userDefaultsMacDeviceIdKey
    private static let lastPairedMacKey = MobilePairing.StorageKeys.userDefaultsLastPairedMacKey

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.lastPairedMacKey),
           let mac = try? JSONDecoder().decode(MobilePairing.PairedMac.self, from: data) {
            self.state = .paired(mac, connected: false)
        } else {
            self.state = .unpaired
        }
        self.code = MobilePairing.generateCode()
        rebuildArtifacts()
        startTimer()
    }

    deinit {
        timer?.invalidate()
    }

    /// 距过期还剩多少 (0–1), 给 ProgressView 用。
    var progressFraction: Double {
        let total = code.expiresAt.timeIntervalSince(code.issuedAt)
        guard total > 0 else { return 0 }
        let remaining = max(0, code.expiresAt.timeIntervalSinceNow)
        return min(1, max(0, remaining / total))
    }

    func regenerate() {
        code = MobilePairing.generateCode()
        rebuildArtifacts()
    }

    func unpair() {
        state = .unpaired
        UserDefaults.standard.removeObject(forKey: Self.lastPairedMacKey)
    }

    func copyURLToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(pairURLString, forType: .string)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.code.isValid() {
                    self.regenerate()
                }
                // 触发 ProgressView 刷新
                self.objectWillChange.send()
            }
        }
    }

    private func rebuildArtifacts() {
        let host = Host.current().localizedName ?? "mac"
        let addr = Self.primaryIPv4Address() ?? "127.0.0.1"
        let deviceId = Self.macDeviceId()
        guard let url = MobilePairing.pairingURL(macDeviceId: deviceId,
                                                  hostname: host,
                                                  host: addr,
                                                  code: code) else {
            pairURLString = ""
            qrImage = nil
            return
        }
        pairURLString = url.absoluteString
        qrImage = Self.makeQRImage(string: pairURLString)
    }

    private static func macDeviceId() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: macDeviceIdKey), !existing.isEmpty {
            return existing
        }
        // 用 hostname + 4 位随机后缀生成稳定设备 ID
        let host = Host.current().localizedName ?? "mac"
        let suffix = String(MobilePairing.generateCode(rng: { UInt64.random(in: 0...UInt64.max) }).value.prefix(4))
        let id = host
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .appending("-\(suffix)")
        defaults.set(id, forKey: macDeviceIdKey)
        return id
    }

    /// 简单 IPv4 地址提取, 失败回落到 127.0.0.1。
    private static func primaryIPv4Address() -> String? {
        var address: String? = nil
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let flags = Int32(p.pointee.ifa_flags)
            let family = p.pointee.ifa_addr.pointee.sa_family
            guard (flags & IFF_UP) == IFF_UP, family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let r = getnameinfo(p.pointee.ifa_addr,
                                socklen_t(p.pointee.ifa_addr.pointee.sa_len),
                                &host,
                                socklen_t(host.count),
                                nil, 0, NI_NUMERICHOST)
            guard r == 0 else { continue }
            let name = String(cString: p.pointee.ifa_name)
            // 优先 en0/en1; 其它网卡 (utun, lo) 跳过
            if name.hasPrefix("en") {
                address = String(cString: host)
                break
            }
        }
        return address
    }

    /// CoreImage QR 生成。失败返回 nil, UI 占位。
    private static func makeQRImage(string: String) -> NSImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}
