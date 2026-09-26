import AVFoundation
import Security
import SwiftUI
import WebKit

@main
struct DshMobileApp: App {
    @StateObject private var connection = MobileConnection()

    var body: some Scene {
        WindowGroup {
            Group {
                if let url = connection.url {
                    NavigationStack {
                        DshWebView(url: url, onUnauthorized: connection.disconnect)
                            .ignoresSafeArea(edges: .bottom)
                            .navigationTitle("点点够终端")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                Button("断开", action: connection.disconnect)
                            }
                    }
                } else {
                    ConnectView(connection: connection)
                }
            }
            .onOpenURL { connection.connect($0) }
        }
    }
}

@MainActor
final class MobileConnection: ObservableObject {
    @Published private(set) var url: URL?
    @Published var error: String?
    private let service = "com.devtools.terminalSimple.dsh-url"
    private let account = "connection-url"

    init() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let text = String(data: data, encoding: .utf8),
           let saved = URL(string: text) {
            connect(saved)
        }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--dsh-mobile-test-url"),
           arguments.indices.contains(index + 1),
           let fixture = URL(string: arguments[index + 1]) {
            connect(fixture)
        }
        #endif
    }

    func connect(_ candidate: URL) {
        let destination: URL
        if candidate.scheme == "dsh-mobile",
           let encoded = URLComponents(url: candidate, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value,
           let decoded = URL(string: encoded) {
            destination = decoded
        } else {
            destination = candidate
        }
        guard destination.scheme == "https", destination.host != nil,
              destination.path.isEmpty || destination.path == "/" else {
            error = "请输入 HTTPS DSH 连接链接"
            return
        }
        guard URLComponents(url: destination, resolvingAgainstBaseURL: false)?
            .queryItems?.contains(where: { $0.name == "token" && !$0.value.isNilOrEmpty }) == true else {
            error = "连接链接缺少认证令牌"
            return
        }
        let data = Data(destination.absoluteString.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            #if targetEnvironment(simulator)
            url = destination
            error = nil
            return
            #else
            error = "无法安全保存连接链接"
            return
            #endif
        }
        url = destination
        error = nil
    }

    func disconnect() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        url = nil
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}

struct ConnectView: View {
    @ObservedObject var connection: MobileConnection
    @State private var text = ""
    @State private var scanning = false

    var body: some View {
        NavigationStack {
            Form {
                Section("连接 Mac") {
                    Text("手机与 Mac 加入同一 Tailscale 网络后，从 Mac 应用菜单复制 HTTPS 连接链接并粘贴到这里；也可扫描该链接的二维码。")
                    Button("扫描二维码") { scanning = true }
                    TextField("https://…?token=…", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("连接") {
                        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            connection.connect(url)
                        } else {
                            connection.error = "连接链接无效"
                        }
                    }
                }
                if let error = connection.error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("点点够终端")
            .sheet(isPresented: $scanning) {
                QRScanner { value in
                    scanning = false
                    if let url = URL(string: value) { connection.connect(url) }
                    else { connection.error = "二维码不是连接链接" }
                }
            }
        }
    }
}

struct DshWebView: UIViewRepresentable {
    let url: URL
    let onUnauthorized: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(origin: url, onUnauthorized: onUnauthorized) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let origin: URL
        let onUnauthorized: () -> Void
        init(origin: URL, onUnauthorized: @escaping () -> Void) {
            self.origin = origin
            self.onUnauthorized = onUnauthorized
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = action.request.url else { decisionHandler(.cancel); return }
            if target.scheme == origin.scheme && target.host == origin.host && target.port == origin.port {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if (response.response as? HTTPURLResponse)?.statusCode == 401 { onUnauthorized() }
            decisionHandler(.allow)
        }
    }
}

struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController {
        ScannerController(onCode: onCode)
    }
    func updateUIViewController(_ controller: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let onCode: (String) -> Void
    private var delivered = false

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async { self?.start() }
        }
    }

    private func start() {
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !delivered, let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        delivered = true
        onCode(code)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }
}
