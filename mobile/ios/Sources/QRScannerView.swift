import SwiftUI
import AVFoundation

/// SwiftUI 包装的 QR 扫码相机视图。
///
/// 用法:
/// ```swift
/// QRScannerView { code in ... } onCancel: { ... }
/// ```
///
/// - 启动时自动请求相机权限 (Info.plist 已声明 `NSCameraUsageDescription`)。
/// - 权限拒绝 / 相机不可用时显示引导文案, 不会崩溃。
/// - 检到首个有效 `tapgo-pair://...` URL 后回调 `onCode`, 由调用方决定是否 dismiss。
/// - iOS 16+ deployment target (本工程要求)。
struct QRScannerView: View {
    let onCode: (String) -> Void
    let onCancel: () -> Void

    @State private var status: CameraStatus = .preparing

    enum CameraStatus {
        case preparing
        case ready
        case denied
        case unavailable(String)
    }

    var body: some View {
        ZStack {
            switch status {
            case .preparing:
                Color.black.ignoresSafeArea()
                ProgressView("准备相机…")
                    .tint(.white)
                    .foregroundStyle(.white)
            case .ready:
                CameraPreview(onCode: { code in
                    onCode(code)
                })
                .ignoresSafeArea()
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            onCancel()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                        .padding(20)
                    }
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 56))
                            .foregroundStyle(.white)
                        Text("将二维码对准取景框")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Mac 端「点点够终端」→ 连接手机")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.black.opacity(0.55))
                    )
                    .padding(.bottom, 60)
                }
            case .denied:
                CameraDeniedView(onCancel: onCancel)
            case .unavailable(let msg):
                CameraUnavailableView(message: msg, onCancel: onCancel)
            }
        }
        .task {
            await prepareCamera()
        }
    }

    @MainActor
    private func prepareCamera() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            self.status = .ready
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            self.status = granted ? .ready : .denied
        case .denied, .restricted:
            self.status = .denied
        @unknown default:
            self.status = .denied
        }
    }
}

// MARK: - AVFoundation 预览层

private struct CameraPreview: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> CameraPreviewController {
        let c = CameraPreviewController()
        c.onCode = onCode
        return c
    }
    func updateUIViewController(_ uiViewController: CameraPreviewController, context: Context) {}
}

private final class CameraPreviewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasReportedCode = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureSession() {
        session.beginConfiguration()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        if output.availableMetadataObjectTypes.contains(.qr) {
            output.metadataObjectTypes = [.qr]
        }
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        self.previewLayer = layer
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !hasReportedCode,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue else { return }
        hasReportedCode = true
        session.stopRunning()
        onCode?(value)
    }
}

// MARK: - 权限 / 不可用占位

private struct CameraDeniedView: View {
    let onCancel: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("相机权限未开启")
                .font(.title3.bold())
            Text("请在「设置 → 点点够终端」中开启相机权限, 然后再试。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("返回") { onCancel() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

private struct CameraUnavailableView: View {
    let message: String
    let onCancel: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("相机不可用")
                .font(.title3.bold())
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("返回") { onCancel() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
