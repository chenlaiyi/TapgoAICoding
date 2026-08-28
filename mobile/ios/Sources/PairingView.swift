import SwiftUI

/// 配对界面: 显示扫码 / 手动输入两个入口。
/// v1 暂不接 AVFoundation 相机 (避免一上来就塞一堆权限请求文案),
/// 优先做手动输入 6 位码; QR 扫描在 v0.5.6 加入。
struct PairingView: View {
    @EnvironmentObject var pairing: PairingStore
    @State private var manualCode: String = ""
    @State private var error: String? = nil

    var body: some View {
        VStack(spacing: 24) {
            header
            manualEntry
            qrPlaceholder
            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
            Spacer()
        }
        .padding(24)
        .background(Color(.systemBackground))
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("点点够终端")
                .font(.title.bold())
            Text("请输入 Mac 端\"连接手机\"弹窗里显示的 6 位配对码")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var manualEntry: some View {
        VStack(spacing: 12) {
            TextField("6 位配对码", text: $manualCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(size: 32, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.3))
                )
                .onChange(of: manualCode) { _, new in
                    manualCode = String(new.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
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

    private var qrPlaceholder: some View {
        VStack(spacing: 6) {
            Divider().padding(.vertical, 4)
            Text("扫码配对")
                .font(.subheadline.bold())
            Text("v0.5.6 起支持相机扫码 (URL Scheme: tapgo-pair://)。\n当前请使用手动输入。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}
