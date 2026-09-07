import SwiftUI

/// 配对界面: 扫码 + 手动输入两个入口。
/// v1.0.0 起接 AVFoundation 真扫码 (`QRScannerView`)。
/// 手动输入作为兜底。
struct PairingView: View {
    @EnvironmentObject var pairing: PairingStore
    @State private var manualCode: String = ""
    @State private var error: String? = nil
    @State private var showScanner = false

    var body: some View {
        VStack(spacing: 24) {
            header
            manualEntry
            scanEntry
            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            Spacer()
        }
        .padding(24)
        .background(Color(.systemBackground))
        .sheet(isPresented: $showScanner) {
            QRScannerView { code in
                showScanner = false
                handleScannedCode(code)
            } onCancel: {
                showScanner = false
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("点点够终端")
                .font(.title.bold())
            Text("扫描 Mac 端「连接手机」弹窗中的二维码\n或手动输入 6 位配对码")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var manualEntry: some View {
        VStack(spacing: 12) {
            TextField("6 位配对码", text: $manualCode)
                .autocorrectionDisabled()
                .font(.system(size: 32, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.3))
                )
                .onChange(of: manualCode) { newValue in
                    manualCode = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                }
            Button {
                pairing.acceptManualCode(manualCode) { result in
                    if case .failure(let msg) = result { error = msg }
                }
            } label: {
                Text("配对")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(manualCode.count != 6)
        }
    }

    private var scanEntry: some View {
        Button {
            showScanner = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.title3)
                Text("扫码配对")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
    }

    private func handleScannedCode(_ raw: String) {
        if let url = URL(string: raw), url.scheme == MobilePairing.urlScheme {
            pairing.handleIncomingURL(url)
        } else {
            // 也支持把 QR 文本当作裸 6 位码。
            pairing.acceptManualCode(raw) { result in
                if case .failure(let msg) = result { error = msg }
            }
        }
    }
}
