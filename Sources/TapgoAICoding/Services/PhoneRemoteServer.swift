import Foundation
import Network
import Combine
import AppKit
import ApplicationServices
import SystemConfiguration
import CoreImage
import CoreImage.CIFilterBuiltins
import TapgoCore
import TapgoComputerUse

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
    /// Tailscale 地址 (100.64/10); nil 表示本机不在 tailnet。
    @Published private(set) var tailnetAddress: String?
    /// 手机链接的接入方式 (局域网 / Tailscale / 公网域名)。
    @Published var activeMode: PhoneRemote.AccessMode = .lan {
        didSet {
            guard activeMode != oldValue else { return }
            rebuildLink()
        }
    }

    /// 公网中继隧道 (本机未登记预设时为 nil)。
    let relayTunnel: PhoneRelayTunnel?

    /// 是否允许手机控制这台电脑 (v0.5.17)。UserDefaults 持久化, 默认开启;
    /// 关闭后所有 `/api/ctrl/*` 请求立即返回 403, H5 据此显示提示。
    @Published var controlEnabled: Bool {
        didSet {
            guard controlEnabled != oldValue else { return }
            UserDefaults.standard.set(controlEnabled, forKey: Self.controlEnabledKey)
        }
    }

    /// 当前可用的接入方式, 按展示顺序排列。
    var availableModes: [PhoneRemote.AccessMode] {
        var modes: [PhoneRemote.AccessMode] = [.lan]
        if tailnetAddress != nil { modes.append(.tailnet) }
        if relayTunnel != nil { modes.append(.relay) }
        return modes
    }

    /// 指定模式的手机链接 (模式不可用时返回空串)。
    func linkString(for mode: PhoneRemote.AccessMode) -> String {
        let host: String
        switch mode {
        case .lan:
            host = lanAddress ?? "127.0.0.1"
            return PhoneRemote.linkURL(host: host, port: port, token: token)?.absoluteString ?? ""
        case .tailnet:
            guard let addr = tailnetAddress else { return "" }
            host = addr
            return PhoneRemote.linkURL(host: host, port: port, token: token)?.absoluteString ?? ""
        case .relay:
            guard let tunnel = relayTunnel else { return "" }
            return PhoneRemote.relayLinkURL(preset: tunnel.preset, token: token)?.absoluteString ?? ""
        }
    }

    // MARK: Internals

    private let store: SessionStore
    /// 项目列表 / 活动项目来源 (v0.5.20 手机端项目切换)。
    private let workspace: WorkspaceStore
    private var listener: NWListener?
    private var token: String
    private var rev = 0
    private var lastPollAt: Date?
    private var presenceTimer: Timer?
    private var pendingBuffers: [ObjectIdentifier: Data] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private let queue = DispatchQueue(label: "tapgo.phone-remote", qos: .userInitiated)

    static let tokenKey = "tapgo.remote.token"
    static let controlEnabledKey = "tapgo.remote.controlEnabled"
    /// H5 轮询间隔 2s, 允许丢一轮。
    static let presenceTimeout: TimeInterval = 8

    // MARK: Init

    init(store: SessionStore, workspace: WorkspaceStore) {
        self.store = store
        self.workspace = workspace
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: Self.tokenKey) ?? ""
        let initial = PhoneRemote.isValidToken(saved) ? saved : PhoneRemote.makeToken()
        if saved != initial { defaults.set(initial, forKey: Self.tokenKey) }
        token = initial
        controlEnabled = (defaults.object(forKey: Self.controlEnabledKey) as? Bool) ?? true
        let addresses = Self.detectAddresses()
        lanAddress = addresses.lan
        tailnetAddress = addresses.tailnet
        // 公网中继: 多来源主机名候选取预设 (ComputerName 可能是本地化名字,
        // 如 fafa 机的 "发发的Mac mini", 不含机器代号); 未登记机器无此入口。
        let relayPreset = PhoneRemote.relayPreset(hostCandidates: Self.hostNameCandidates())
        relayTunnel = relayPreset.flatMap { PhoneRelayTunnel(preset: $0) }
        // 默认接入方式: 有公网中继用公网 (任意网络可用), 否则局域网。
        activeMode = relayTunnel != nil ? .relay : .lan
        rebuildLink()
        // 隧道 spawn 时取实时端口; 放在 init 末尾避免提前捕获 self。
        relayTunnel?.localPortProvider = { [weak self] in self?.port ?? PhoneRemote.defaultPort }
        // 会话有任何变化就 bump rev, H5 端靠 JSON 全量对比感知更新。
        store.objectWillChange
            .sink { [weak self] _ in self?.rev &+= 1 }
            .store(in: &cancellables)
    }

    // MARK: Lifecycle

    /// 幂等启动: 先试固定端口 8723, 失败则让系统挑空闲端口。
    /// 公网中继隧道一并常驻。
    func startIfNeeded() {
        guard listener == nil else { return }
        status = .starting
        relayTunnel?.start()
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
        relayTunnel?.stop()
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
            let seeds = workspace.projects.map {
                PhoneRemote.ProjectSeed(id: $0.id,
                                        name: $0.displayName,
                                        path: $0.worktreeRoot.path,
                                        lastActivityAt: $0.lastUsedAt,
                                        isLocal: $0.kind == .local)
            }
            let snapshot = PhoneRemote.buildState(threads: store.liveThreads,
                                                  activeId: store.activeThreadId,
                                                  rev: rev,
                                                  hostname: Self.displayName(),
                                                  appVersion: Self.appVersion,
                                                  control: PhoneRemote.ControlStatus(
                                                      enabled: controlEnabled,
                                                      screenAllowed: Self.screenCaptureAllowed,
                                                      accessibilityAllowed: Self.accessibilityAllowed),
                                                  projects: seeds,
                                                  activeProjectId: workspace.state.activeProjectId,
                                                  model: store.modelDisplayName,
                                                  attachedCount: store.attachedImages.count)
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
        case .success(.project(let id)):
            lastPollAt = Date()
            phoneConnected = true
            // setActiveProject 会自动选中该项目最近的会话, H5 下一轮轮询
            // 即拿到新项目上下文。
            store.setActiveProject(id)
            return PhoneRemote.jsonOK(Data(#"{"ok":true}"#.utf8))
        case .success(.newSession(let projectId)):
            lastPollAt = Date()
            phoneConnected = true
            if workspace.state.activeProjectId != projectId {
                store.setActiveProject(projectId)
            }
            store.newThread()
            return PhoneRemote.jsonOK(Data(#"{"ok":true}"#.utf8))
        case .success(.attach(let name, let dataBase64)):
            lastPollAt = Date()
            phoneConnected = true
            guard let url = Self.writeAttachment(name: name, dataBase64: dataBase64) else {
                return PhoneRemote.badRequestResponse
            }
            store.addImages([url])
            return PhoneRemote.jsonOK(Data(#"{"ok":true}"#.utf8))
        case .success(.turnImage(let turnId, let index)):
            lastPollAt = Date()
            let turn = store.liveThreads.flatMap(\.turns).first(where: { $0.id == turnId })
            guard let path = turn.flatMap({ $0.userImagePaths.indices.contains(index) ? $0.userImagePaths[index] : nil })
            else { return PhoneRemote.notFoundResponse }
            return Self.imageResponse(at: path)
        case .success(.pendingImage(let index)):
            lastPollAt = Date()
            guard store.attachedImages.indices.contains(index) else {
                return PhoneRemote.notFoundResponse
            }
            return Self.imageResponse(at: store.attachedImages[index].path)
        case .success(.controlScreen):
            lastPollAt = Date()
            phoneConnected = true
            guard controlEnabled else { return PhoneRemote.controlErrorResponse("controlDisabled") }
            guard Self.screenCaptureAllowed else { return PhoneRemote.controlErrorResponse("screenPermission") }
            guard let jpeg = takeScreenshotJPEG() else { return PhoneRemote.controlErrorResponse("screenshotFailed") }
            return PhoneRemote.httpResponse(status: 200, reason: "OK",
                                            contentType: "image/jpeg", body: jpeg)
        case .success(.controlClick(let x, let y, let double)):
            return controlGuard { ComputerUse.click(nx: x, ny: y, doubleClick: double) }
        case .success(.controlScroll(let deltaY)):
            return controlGuard { ComputerUse.scroll(lines: deltaY) }
        case .success(.controlType(let text)):
            return controlGuard { ComputerUse.typeText(text) }
        case .success(.controlKey(let key)):
            return controlGuard { ComputerUse.pressKey(name: key.rawValue) }
        case .success(.controlCommand(let action)):
            return controlGuard { ComputerUse.performCommand(action) }
        }
    }

    /// 控制类 POST 的公共前置检查 + 执行。`body` 只在检查全部通过后调用。
    private func controlGuard(_ body: () -> Void) -> Data {
        lastPollAt = Date()
        phoneConnected = true
        guard controlEnabled else { return PhoneRemote.controlErrorResponse("controlDisabled") }
        guard Self.accessibilityAllowed else { return PhoneRemote.controlErrorResponse("accessibilityPermission") }
        body()
        return PhoneRemote.controlOKResponse
    }

    // MARK: 电脑控制 — 实现统一走 TapgoComputerUse 库 (v0.5.20 起 MCP
    // server 共用同一套原语); 这里只保留薄转发与权限透传。

    /// 「屏幕录制」TCC 权限预检 (ConnectPhoneView 权限行读取)。
    static var screenCaptureAllowed: Bool { ComputerUse.screenCaptureAllowed }

    /// 「辅助功能」TCC 权限预检。
    static var accessibilityAllowed: Bool { ComputerUse.accessibilityAllowed }

    /// 弹出系统授权弹窗 (ConnectPhoneView 的「申请授权」按钮调用)。
    nonisolated static func requestPermissions() {
        ComputerUse.requestPermissions()
    }

    private func takeScreenshotJPEG() -> Data? {
        ComputerUse.screenshotJPEG(maxSide: 1200)
    }

    // MARK: Link & identity

    private func rebuildLink() {
        guard status == .running else {
            // 未运行时不展示链接, 避免手机扫到打不开的地址。
            linkString = ""
            return
        }
        linkString = linkString(for: activeMode)
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

    /// 手机上传的图片附件: base64 解码 → 魔数校验 → 写临时文件 → 返回 URL
    /// (交 `store.addImages` 转存)。扩展名取自文件名并限制在图片白名单内。
    static func writeAttachment(name: String, dataBase64: String) -> URL? {        guard let data = Data(base64Encoded: dataBase64, options: [.ignoreUnknownCharacters]),
              !data.isEmpty, data.count <= 12_000_000
        else { return nil }
        let ext: String
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            ext = "jpg"
        } else if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            ext = "png"
        } else if bytes.starts(with: [0x47, 0x49, 0x46]) {
            ext = "gif"
        } else if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]), data.count > 12 {
            ext = "webp"
        } else if data.count > 11, String(decoding: data[4..<8], as: UTF8.self) == "ftyp" {
            ext = "heic"
        } else {
            return nil
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tapgo-attach-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        _ = name // 文件名仅用于展示, 实际落盘名用 UUID 防路径注入。
        return url
    }

    /// 按扩展名推断 Content-Type 并输出图片 (允许浏览器缓存, URL 含 token)。
    static func imageResponse(at path: String) -> Data {
        let ext = (path as NSString).pathExtension.lowercased()
        let type: String
        switch ext {
        case "png": type = "image/png"
        case "jpg", "jpeg": type = "image/jpeg"
        case "gif": type = "image/gif"
        case "webp": type = "image/webp"
        case "heic": type = "image/heic"
        default: type = "application/octet-stream"
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return PhoneRemote.notFoundResponse
        }
        var head = "HTTP/1.1 200 OK\r\n"
        head += "Content-Type: \(type)\r\n"
        head += "Content-Length: \(data.count)\r\n"
        head += "Connection: close\r\n"
        head += "Cache-Control: private, max-age=3600\r\n"
        head += "\r\n"
        var out = Data(head.utf8)
        out.append(data)
        return out
    }

    static func displayName() -> String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    /// 主机名候选集: LocalizedName / LocalHostName / ComputerName / DNS 主机名。
    /// 任一来源可能缺失或被本地化 (如 "发发的Mac mini"), 全部交给
    /// `PhoneRemote.relayPreset(hostCandidates:)` 匹配。
    static func hostNameCandidates() -> [String] {
        var names: [String] = [
            Host.current().localizedName ?? "",
            Self.scName("LocalHostName") ?? "",
            Self.scName("ComputerName") ?? "",
            ProcessInfo.processInfo.hostName,
        ]
        var seen = Set<String>()
        names.removeAll { !seen.insert($0).inserted }
        return names
    }

    /// 读 SystemConfiguration 动态存储里的主机名键。
    private static func scName(_ key: String) -> String? {
        guard let store = SCDynamicStoreCreate(nil, "tapgo.remote" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, key as CFString) as? String else {
            return nil
        }
        return value
    }

    /// 一次 getifaddrs 遍历同时取局域网 IPv4 (优先 en0/en1) 与
    /// Tailscale 地址 (utun 上的 100.64/10)。
    static func detectAddresses() -> (lan: String?, tailnet: String?) {
        var lanPreferred: String? = nil
        var lanFallback: String? = nil
        var tailnet: String? = nil
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (nil, nil) }
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
            let ip = String(cString: host)
            if PhoneRemote.isTailnetIPv4(ip), name.hasPrefix("utun") {
                tailnet = ip
            }
            if name.hasPrefix("en"), lanPreferred == nil {
                lanPreferred = ip
            }
            if lanFallback == nil && !name.hasPrefix("utun") {
                lanFallback = ip
            }
        }
        return (lanPreferred ?? lanFallback, tailnet)
    }
}
