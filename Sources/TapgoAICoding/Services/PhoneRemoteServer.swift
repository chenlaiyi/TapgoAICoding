import Foundation
import Network
import Combine
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import TapgoCore

/// Mac 端"扫码即开 H5"远程控制服务 (v0.5.16, 对标 ZCode 移动端远程控制)。
///
/// App 启动即监听 `0.0.0.0:8723`, 所有路由都要求路径里带 128-bit token
/// (`/r/<token>/...`), 因此局域网内扫描端口也拿不到任何数据。链接/token
/// 持久化在 UserDefaults, QR 保持稳定, 可在 UI 里一键轮换。
///
/// 每条 HTTP 连接固定 `Connection: close`, H5 每 2s 轮询一次
/// `/api/state`, 近 8s 内有轮询即视为"手机已连接"。
@MainActor
final class PhoneRemoteController: ObservableObject {

    enum Status: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    // MARK: Published state (ConnectPhoneView 消费)

    @Published private(set) var status: Status = .stopped
    /// 实际监听端口; 8723 被占时回落到系统自动分配端口。
    @Published private(set) var port: Int = PhoneRemote.defaultPort
    @Published private(set) var linkString: String = ""
    /// 近 8s 内手机有轮询 (H5 每 2s 一次)。
    @Published private(set) var phoneConnected: Bool = false
    @Published private(set) var lanAddress: String?

    // MARK: Internals

    private let store: SessionStore
    private var listener: NWListener?
    private var token: String
    private var rev = 0
    private var lastPollAt: Date?
    private var presenceTimer: Timer?
    private var pendingBuffers: [ObjectIdentifier: Data] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private let queue = DispatchQueue(label: "tapgo.phone-remote", qos: .userInitiated)

    static let tokenKey = "tapgo.remote.token"
    /// H5 轮询间隔 2s, 允许丢一轮。
    static let presenceTimeout: TimeInterval = 8

    // MARK: Init

    init(store: SessionStore) {
        self.store = store
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: Self.tokenKey) ?? ""
        let initial = PhoneRemote.isValidToken(saved) ? saved : PhoneRemote.makeToken()
        if saved != initial { defaults.set(initial, forKey: Self.tokenKey) }
        token = initial
        lanAddress = Self.primaryIPv4Address()
        rebuildLink()
        // 会话有任何变化就 bump rev, H5 端靠 JSON 全量对比感知更新。
        store.objectWillChange
            .sink { [weak self] _ in self?.rev &+= 1 }
            .store(in: &cancellables)
    }

    // MARK: Lifecycle

    /// 幂等启动: 先试固定端口 8723, 失败则让系统挑空闲端口。
    func startIfNeeded() {
        guard listener == nil else { return }
        status = .starting
        startListener(on: UInt16(PhoneRemote.defaultPort), fallbackToAutoPort: true)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        pendingBuffers.removeAll()
        presenceTimer?.invalidate()
        presenceTimer = nil
        lastPollAt = nil
        phoneConnected = false
        status = .stopped
        rebuildLink()
    }

    /// 轮换 token 并刷新链接 (旧链接立即失效)。监听器无需重启。
    func rotateToken() {
        token = PhoneRemote.makeToken()
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
        rebuildLink()
    }

    func copyLink() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(linkString, forType: .string)
    }

    private func startListener(on portValue: UInt16, fallbackToAutoPort: Bool) {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let newListener: NWListener
        do {
            newListener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: portValue))
        } catch {
            if fallbackToAutoPort {
                startAutoPortListener()
            } else {
                status = .failed("无法监听端口 \(portValue): \(error.localizedDescription)")
            }
            return
        }
        newListener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handleListenerState(state, portValue: portValue, fallbackToAutoPort: fallbackToAutoPort) }
        }
        newListener.newConnectionHandler = { [weak self] conn in
            // 回调在 queue 上; 立刻 hop 到 MainActor 统一处理。
            Task { @MainActor in self?.accept(conn) }
        }
        listener = newListener
        newListener.start(queue: queue)
    }

    private func startAutoPortListener() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let newListener: NWListener
        do {
            newListener = try NWListener(using: params)
        } catch {
            status = .failed("无法创建监听: \(error.localizedDescription)")
            return
        }
        newListener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handleListenerState(state, portValue: 0, fallbackToAutoPort: false) }
        }
        newListener.newConnectionHandler = { [weak self] conn in
            Task { @MainActor in self?.accept(conn) }
        }
        listener = newListener
        newListener.start(queue: queue)
    }

    private func handleListenerState(_ state: NWListener.State,
                                     portValue: UInt16,
                                     fallbackToAutoPort: Bool) {
        switch state {
        case .ready:
            if portValue > 0 {
                port = Int(portValue)
            } else if let p = listener?.port?.rawValue {
                port = Int(p)
            }
            status = .running
            rebuildLink()
            startPresenceTimer()
        case .failed(let error):
            guard listener != nil else { return }
            listener?.cancel()
            listener = nil
            if fallbackToAutoPort, portValue > 0 {
                startAutoPortListener()
            } else {
                status = .failed("监听失败: \(error)")
            }
        case .cancelled:
            break
        default:
            break
        }
    }

    private func startPresenceTimer() {
        presenceTimer?.invalidate()
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let last = self.lastPollAt else { return }
                self.phoneConnected = Date().timeIntervalSince(last) < Self.presenceTimeout
            }
        }
    }

    // MARK: Connection handling (全部在 MainActor; 2s 轮询量级足够)

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn)
    }

    private func receive(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                self?.gotBytes(conn, data: data, isComplete: isComplete, error: error)
            }
        }
    }

    private func gotBytes(_ conn: NWConnection,
                          data: Data?,
                          isComplete: Bool,
                          error: NWError?) {
        let key = ObjectIdentifier(conn)
        if let data {
            pendingBuffers[key, default: Data()].append(data)
        }
        if PhoneRemote.isRequestOversized(pendingBuffers[key] ?? Data()) {
            pendingBuffers.removeValue(forKey: key)
            conn.cancel()
            return
        }
        if let request = PhoneRemote.parseRequest(pendingBuffers[key] ?? Data()) {
            pendingBuffers.removeValue(forKey: key)
            let response = buildResponse(request)
            conn.send(content: response, completion: .contentProcessed { _ in
                conn.cancel()
            })
            return
        }
        if error != nil || isComplete {
            pendingBuffers.removeValue(forKey: key)
            conn.cancel()
            return
        }
        receive(conn)
    }

    /// 路由 → 响应。所有会话数据只在 MainActor 读取。
    func buildResponse(_ request: PhoneRemote.ParsedRequest) -> Data {
        switch PhoneRemote.route(method: request.method,
                                 path: request.path,
                                 body: request.body,
                                 expectedToken: token) {
        case .failure(.unauthorized):
            return PhoneRemote.forbiddenResponse
        case .failure(.notFound):
            return PhoneRemote.notFoundResponse
        case .failure(.badRequest):
            return PhoneRemote.badRequestResponse
        case .success(.page):
            let html = PhoneRemote.pageHTML(token: token)
            return PhoneRemote.httpResponse(status: 200, reason: "OK",
                                            contentType: "text/html; charset=utf-8",
                                            body: Data(html.utf8))
        case .success(.state):
            lastPollAt = Date()
            phoneConnected = true
            let snapshot = PhoneRemote.buildState(threads: store.liveThreads,
                                                  activeId: store.activeThreadId,
                                                  rev: rev,
                                                  hostname: Self.displayName(),
                                                  appVersion: Self.appVersion)
            return PhoneRemote.jsonOK(PhoneRemote.stateJSON(snapshot))
        case .success(.send(let text)):
            lastPollAt = Date()
            phoneConnected = true
            store.sendUserMessage(text)
            return PhoneRemote.jsonOK(Data(#"{"ok":true}"#.utf8))
        case .success(.select(let threadId)):
            lastPollAt = Date()
            phoneConnected = true
            store.selectThread(threadId)
            return PhoneRemote.jsonOK(Data(#"{"ok":true}"#.utf8))
        }
    }

    // MARK: Link & identity

    private func rebuildLink() {
        guard status == .running else {
            // 未运行时也给出预览链接 (按默认端口), UI 可显示但提示未开启。
            linkString = ""
            return
        }
        let host = lanAddress ?? "127.0.0.1"
        linkString = PhoneRemote.linkURL(host: host, port: port, token: token)?.absoluteString ?? ""
    }

    func makeQRImage() -> NSImage? {
        guard !linkString.isEmpty else { return nil }
        return Self.makeQRImage(string: linkString)
    }

    static func makeQRImage(string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static func displayName() -> String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    /// 局域网 IPv4: 优先 en0/en1, 否则取第一个 UP 的非回回环 AF_INET 地址。
    static func primaryIPv4Address() -> String? {
        var address: String? = nil
        var fallback: String? = nil
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let flags = Int32(p.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP,
                  (flags & IFF_LOOPBACK) == 0,
                  p.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let r = getnameinfo(p.pointee.ifa_addr,
                                socklen_t(p.pointee.ifa_addr.pointee.sa_len),
                                &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard r == 0 else { continue }
            let name = String(cString: p.pointee.ifa_name)
            if name.hasPrefix("en") {
                address = String(cString: host)
                break
            }
            if fallback == nil { fallback = String(cString: host) }
        }
        return address ?? fallback
    }
}
