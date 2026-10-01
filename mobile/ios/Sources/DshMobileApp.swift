import AVFoundation
import Security
import SwiftUI
import UIKit
import WebKit

@main
struct DshMobileApp: App {
    @StateObject private var connection = MobileConnection()
    @StateObject private var interactions = MobileInteractionCenter()
    @State private var showingLaunch = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if let computer = connection.activeComputer {
                        RemoteHomeView(connection: connection, computer: computer)
                            .id(computer.id)
                    } else {
                        RemoteLandingView(connection: connection)
                    }
                }
                .overlay {
                    MobileInteractionOverlay(center: interactions, computer: connection.activeComputer)
                }

                if showingLaunch {
                    MobileLaunchView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(1100))
                withAnimation(.easeOut(duration: 0.2)) { showingLaunch = false }
            }
            .task(id: connection.activeComputer?.url) {
                await interactions.connect(computer: connection.activeComputer)
            }
            .onOpenURL { connection.connect($0) }
        }
    }
}

/// Brand header shared by startup and the unpaired welcome page.
struct MobileWelcomeBrand: View {
    var body: some View {
        HStack(spacing: 12) {
            Image("SplashMark")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text("点点够终端")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("welcomeBrand")
    }
}

/// Desktop welcome copy with semantic colors and Dynamic Type support.
struct MobileWelcomeMessage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            (Text("点点够").bold() + Text("，一切都一点点变好！"))
                .foregroundStyle(.primary)
            Text("组装无限可能，共探智能上限")
                .foregroundStyle(.secondary)
        }
        .font(.title3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("welcomeMessage")
    }
}

private struct MobileLaunchView: View {
    var body: some View {
        VStack(spacing: 0) {
            MobileWelcomeBrand()
            Spacer()
            MobileWelcomeMessage()
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 44)
        .padding(.bottom, 100)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }
}

struct SavedComputer: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var url: String
    var sourceName: String? = nil
    var customName: String? = nil
}

private struct SavedComputers: Codable {
    var items: [SavedComputer]
    var activeID: String?
}

@MainActor
final class MobileConnection: ObservableObject {
    @Published private(set) var computers: [SavedComputer] = []
    @Published private(set) var activeID: String?
    @Published var error: String?
    var activeComputer: SavedComputer? { computers.first(where: { $0.id == activeID }) }
    private let service = "com.devtools.terminalSimple.dsh-computers"
    private let account = "connections"
    private var ephemeralFixture = false

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--dsh-mobile-test-welcome") {
            ephemeralFixture = true
            return
        }
        #endif
        if let data = read(service: service, account: account),
           let saved = try? JSONDecoder().decode(SavedComputers.self, from: data) {
            computers = saved.items
            activeID = saved.activeID
        } else if let data = read(service: "com.devtools.terminalSimple.dsh-url", account: "connection-url"),
                  let text = String(data: data, encoding: .utf8), let saved = URL(string: text) {
            connect(saved)
            if activeComputer != nil {
                SecItemDelete(query(service: "com.devtools.terminalSimple.dsh-url",
                                    account: "connection-url") as CFDictionary)
            }
        }
        #if DEBUG
        if computers.contains(where: { URL(string: $0.id)?.host?.hasSuffix(".example") == true }) {
            let retained = computers.filter { URL(string: $0.id)?.host?.hasSuffix(".example") != true }
            let restored = retained.contains(where: { $0.id == activeID }) ? activeID : retained.last?.id
            commit(retained, active: restored)
        }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--dsh-mobile-test-url"),
           arguments.indices.contains(index + 1),
           let fixture = URL(string: arguments[index + 1]) {
            ephemeralFixture = true
            connect(fixture)
        }
        #endif
    }

    private func query(service: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func read(service: String, account: String) -> Data? {
        var lookup = query(service: service, account: account)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func commit(_ items: [SavedComputer], active: String?) {
        if ephemeralFixture {
            computers = items
            activeID = active
            error = nil
            return
        }
        guard let data = try? JSONEncoder().encode(SavedComputers(items: items, activeID: active)) else {
            error = "无法保存电脑列表"
            return
        }
        let lookup = query(service: service, account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let existing = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        var status = existing
        if existing == errSecItemNotFound {
            var insert = lookup
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        if status != errSecSuccess {
            #if !targetEnvironment(simulator)
            error = "无法安全保存电脑列表"
            return
            #endif
        }
        computers = items
        activeID = active
        error = nil
    }

    func connect(_ candidate: URL, name: String = "") {
        let destination: URL
        if candidate.scheme == "dsh-mobile",
           let encoded = URLComponents(url: candidate, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value,
           let decoded = URL(string: encoded) {
            destination = decoded
        } else {
            destination = candidate
        }
        guard destination.scheme == "https", let host = destination.host,
              destination.user == nil, destination.password == nil,
              destination.path.isEmpty || destination.path == "/" else {
            error = "请输入 HTTPS DSH 连接链接"
            return
        }
        guard URLComponents(url: destination, resolvingAgainstBaseURL: false)?
            .queryItems?.contains(where: { $0.name == "token" && !$0.value.isNilOrEmpty }) == true else {
            error = "连接链接缺少认证令牌"
            return
        }
        let id = "https://\(host)\(destination.port.map { ":\($0)" } ?? "")"
        let previous = computers.first(where: { $0.id == id })
        let transmittedName = URLComponents(url: destination, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "name" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceName = transmittedName.flatMap { $0.isEmpty ? nil : String($0.prefix(80)) } ?? host
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyName = previous?.sourceName == nil && previous?.name != host ? previous?.name : nil
        let customName = label.isEmpty ? (previous?.customName ?? legacyName) : label
        let computer = SavedComputer(id: id, name: customName ?? sourceName,
                                     url: destination.absoluteString, sourceName: sourceName,
                                     customName: customName)
        commit(computers.filter { $0.id != id } + [computer], active: id)
    }

    func renameActive(_ value: String) {
        guard let activeID else { return }
        let label = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.count <= 80 else {
            error = "电脑名称需为 1–80 个字符"
            return
        }
        var updated = computers
        guard let index = updated.firstIndex(where: { $0.id == activeID }) else { return }
        updated[index].name = label
        updated[index].customName = label
        commit(updated, active: activeID)
    }

    func select(_ id: String) { commit(computers, active: id) }
    func leave() { commit(computers, active: nil) }
    func expireActive() {
        leave()
        error = "连接已失效，请从这台 Mac 重新复制连接链接"
    }
    func remove(_ id: String) {
        commit(computers.filter { $0.id != id }, active: activeID == id ? nil : activeID)
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
                if !connection.computers.isEmpty {
                    Section("已配对的 Mac") {
                        ForEach(connection.computers) { computer in
                            Button { connection.select(computer.id) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(computer.name).font(.headline)
                                    Text(computer.id).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { connection.computers[$0].id }
                            for id in ids { connection.remove(id) }
                        }
                    }
                }
                Section("连接 Mac") {
                    Text("从电脑扫码或粘贴连接链接，电脑名称会自动识别。连接后可在手机上改名。")
                    Button("扫描二维码") { scanning = true }
                    TextField("https://…?token=…", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("从剪贴板粘贴") {
                        text = UIPasteboard.general.string ?? ""
                    }
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
    var sessionId: String? = nil
    let onUnauthorized: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        if let sessionId,
           let selection = try? JSONSerialization.data(withJSONObject: ["sessionId": sessionId]),
           let value = String(data: selection, encoding: .utf8),
           let quoted = try? JSONSerialization.data(withJSONObject: ["dsh.sessions.current", value]),
           let arguments = String(data: quoted, encoding: .utf8) {
            configuration.userContentController.addUserScript(WKUserScript(
                source: "localStorage.setItem(...\(arguments))",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
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
