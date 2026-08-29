import Foundation
import Network
import Combine
import AppKit
import ApplicationServices
import SystemConfiguration
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

    init(store: SessionStore) {
        self.store = store
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
            let snapshot = PhoneRemote.buildState(threads: store.liveThreads,
                                                  activeId: store.activeThreadId,
                                                  rev: rev,
                                                  hostname: Self.displayName(),
                                                  appVersion: Self.appVersion,
                                                  control: PhoneRemote.ControlStatus(
                                                      enabled: controlEnabled,
                                                      screenAllowed: Self.screenCaptureAllowed,
                                                      accessibilityAllowed: Self.accessibilityAllowed))
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
        case .success(.controlScreen):
            lastPollAt = Date()
            phoneConnected = true
            guard controlEnabled else { return PhoneRemote.controlErrorResponse("controlDisabled") }
            guard Self.screenCaptureAllowed else { return PhoneRemote.controlErrorResponse("screenPermission") }
            guard let jpeg = takeScreenshotJPEG() else { return PhoneRemote.controlErrorResponse("screenshotFailed") }
            return PhoneRemote.httpResponse(status: 200, reason: "OK",
                                            contentType: "image/jpeg", body: jpeg)
        case .success(.controlClick(let x, let y, let double)):
            return controlGuard { performClick(nx: x, ny: y, doubleClick: double) }
        case .success(.controlScroll(let deltaY)):
            return controlGuard { performScroll(lines: deltaY) }
        case .success(.controlType(let text)):
            return controlGuard { performType(text: text) }
        case .success(.controlKey(let key)):
            return controlGuard { performKey(key) }
        case .success(.controlCommand(let action)):
            return controlGuard { performCommand(action) }
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

    // MARK: 电脑控制 (v0.5.17) — 权限 / 截屏 / CGEvent 注入

    /// 「屏幕录制」TCC 权限预检 (不弹窗)。
    static var screenCaptureAllowed: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 「辅助功能」TCC 权限预检 (不弹窗)。
    static var accessibilityAllowed: Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统授权弹窗 (ConnectPhoneView 的「申请授权」按钮调用)。
    nonisolated static func requestPermissions() {
        _ = CGRequestScreenCaptureAccess()
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// 主屏截图 → JPEG。限制最长边到 ~1200px (手机上足够看清, 轮询体量小),
    /// 点击坐标在 H5 端以归一化形式回传, 与分辨率无关。
    func takeScreenshotJPEG() -> Data? {
        let displayID = CGMainDisplayID()
        guard let image = CGDisplayCreateImage(displayID) else { return nil }
        let maxSide: CGFloat = 1200
        let longest = CGFloat(max(image.width, image.height))
        let scaled = Self.scaledImage(image, maxSide: longest > maxSide ? maxSide : longest)
        let rep = NSBitmapImageRep(cgImage: scaled ?? image)
        return rep.representation(using: .jpeg,
                                  properties: [.compressionFactor: 0.72])
    }

    /// 等比缩放 CGImage 到最长边 `maxSide` (若已小于则返回 nil 让调用方用原图)。
    static func scaledImage(_ image: CGImage, maxSide: CGFloat) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        guard maxSide > 0, max(w, h) > maxSide else { return nil }
        let scale = maxSide / max(w, h)
        let tw = max(1, Int(w * scale)), th = max(1, Int(h * scale))
        guard let ctx = CGContext(data: nil, width: tw, height: th,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
        return ctx.makeImage()
    }

    /// 归一化坐标 (0...1, 相对主屏截图、原点左上) → 全局 CG 坐标 (原点左下)。
    static func displayPoint(nx: Double, ny: Double) -> CGPoint {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        return CGPoint(x: bounds.minX + CGFloat(nx) * bounds.width,
                       y: bounds.minY + (1 - CGFloat(ny)) * bounds.height)
    }

    /// 在归一化坐标处单击 / 双击 (先移动光标再按抬)。
    func performClick(nx: Double, ny: Double, doubleClick: Bool) {
        let pt = Self.displayPoint(nx: nx, ny: ny)
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                           mouseCursorPosition: pt, mouseButton: .left)
        move?.post(tap: .cghidEventTap)
        usleep(20_000)
        let clicks = doubleClick ? 2 : 1
        for state in 1...clicks {
            let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                               mouseCursorPosition: pt, mouseButton: .left)
            down?.setIntegerValueField(.mouseEventClickState, value: Int64(state))
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                             mouseCursorPosition: pt, mouseButton: .left)
            up?.setIntegerValueField(.mouseEventClickState, value: Int64(state))
            up?.post(tap: .cghidEventTap)
            if state < clicks { usleep(120_000) }
        }
    }

    /// 滚轮: `lines` 行, 正数向下。限幅 ±20 行防误操作把页面滚飞。
    func performScroll(lines: Double) {
        let clamped = max(-20, min(20, lines))
        let ev = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                         wheel1: Int32(-clamped), wheel2: 0, wheel3: 0)
        ev?.post(tap: .cghidEventTap)
    }

    /// 逐字符注入键盘输入。`kCGKeyboardEventKeycode=0` + UnicodeString 的
    /// 形态对绝大多数 App 生效; 换行转成 Return 键。
    func performType(text: String) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        for ch in text {
            if ch == "\n" || ch == "\r" {
                postKey(36, source: src)
                continue
            }
            let units = Array(String(ch).utf16)
            for keyDown in [true, false] {
                let ev = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: keyDown)
                ev?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                ev?.post(tap: .cghidEventTap)
            }
            usleep(2_000)
        }
    }

    /// 单键: 普通键走虚拟键码, 媒体键走 systemDefined 事件。
    func performKey(_ key: PhoneRemote.ControlKey) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        if let code = key.virtualKeyCode {
            postKey(CGKeyCode(code), source: src)
        } else if let media = key.mediaKeyType {
            postMediaKey(media, source: src)
        }
    }

    private func postKey(_ code: CGKeyCode, source: CGEventSource?) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        up?.post(tap: .cghidEventTap)
    }

    /// 媒体键 (音量/亮度/播放): `NX_KEYTYPE_*` 打包进 NSEvent systemDefined
    /// subtype 8 的 data1 (高 16 位是按下 0x0A / 抬起 0x0B, 低 16 位是键型),
    /// 再取 CGEvent 投递 —— 这是苹果未文档化但长期稳定的公开接口形态。
    private func postMediaKey(_ type: Int, source: CGEventSource?) {
        for flag in [0x0a, 0x0b] {   // 0x0a = 按下, 0x0b = 抬起
            let data1 = (type << 16) | (flag << 8)
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                        modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
                                        timestamp: 0, windowNumber: 0, context: nil,
                                        subtype: 8, data1: data1, data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// 系统级命令。
    func performCommand(_ action: PhoneRemote.ControlAction) {
        switch action {
        case .lock:
            // Ctrl+Cmd+Q = 立即锁屏 (系统级快捷键)。
            guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
            for keyDown in [true, false] {
                let ev = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: keyDown)
                ev?.flags = [.maskControl, .maskCommand]
                ev?.post(tap: .cghidEventTap)
            }
        case .sleep:
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            p.arguments = ["sleepnow"]
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            try? p.run()
        }
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
