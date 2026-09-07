import Foundation
import Network

/// iOS 端长链接 (Bonjour + TCP + JSON-RPC)。
///
/// 状态机:
///   .idle  ── start() ──▶  .discovering ── found ──▶  .connecting ── ready ──▶  .connected
///                                          └─ fail ──▶  .failed
///
/// 维护一个 NWBrowser + 一条 NWConnection; 每 10s 推 hello 心跳帧。
/// 收到的 server push 通过 `onPush` 回调给上层 (DashboardView)。
@MainActor
final class PairingLink: ObservableObject {

    enum Status: Equatable {
        case idle
        case discovering
        case connecting(String)        // host:port
        case connected(String)         // host:port
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastError: String? = nil

    /// Bonjour 搜索目标 service。
    private let serviceType: String
    /// 期望的 mac deviceId (PairedMac.deviceId); nil 表示任意 mac。
    var expectedDeviceId: String?
    /// 心跳间隔。
    private let heartbeatInterval: TimeInterval = 10.0

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var pendingRequests: [String: (Result<MobileRemoteLink.Params, Error>) -> Void] = [:]
    private var heartbeatTimer: Timer?
    private var inboundBuffer = Data()

    /// 服务端 push (无 id) 回调。
    var onPush: ((MobileRemoteLink.Frame) -> Void)?
    /// 连接状态切换回调 (true=已 connected, false=断)。
    var onConnectionChange: ((Bool) -> Void)?

    init(serviceType: String = MobileRemoteLink.bonjourServiceType,
         expectedDeviceId: String? = nil) {
        self.serviceType = serviceType
        self.expectedDeviceId = expectedDeviceId
    }

    // MARK: - Lifecycle

    func start() {
        guard case .idle = status else { return }
        status = .discovering
        lastError = nil
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: serviceType, domain: nil)
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        browser = NWBrowser(for: descriptor, using: params)
        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleBrowserState(state)
            }
        }
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.handleBrowseResults(results)
            }
        }
        browser?.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        inboundBuffer = Data()
        pendingRequests.removeAll()
        transitionTo(.idle)
        onConnectionChange?(false)
    }

    // MARK: - Request

    /// 发送 JSON-RPC 请求并通过 completion 拿到 result params 或 error。
    func request(method: String,
                 params: MobileRemoteLink.Params = .init(),
                 timeout: TimeInterval = 8.0,
                 completion: @escaping (Result<MobileRemoteLink.Params, Error>) -> Void) {
        let id = UUID().uuidString
        let frame = MobileRemoteLink.makeRequest(id: id, method: method, params: params)
        pendingRequests[id] = completion
        send(frame)
        // 超时回收, 避免 pendingRequests 累积。
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard let self = self else { return }
            if let cb = self.pendingRequests.removeValue(forKey: id) {
                cb(.failure(NSError(domain: "PairingLink", code: -2,
                                    userInfo: [NSLocalizedDescriptionKey: "timeout: \(method)"])))
            }
        }
    }

    // MARK: - Browser callbacks

    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .failed(let err):
            lastError = "browser failed: \(err.localizedDescription)"
            transitionTo(.failed(lastError ?? "browser failed"))
        case .cancelled:
            // stop() 已经 transitionTo(.idle)
            break
        default:
            break
        }
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        // 选第一个匹配 (或第一个匹配 expectedDeviceId) 的 endpoint。
        // "demo-mac" 是 TAPGO_FORCE_PAIRED 注入的伪 deviceId, 不参与 include 检查
        // (TAPGO_FORCE_PAIRED 模式下 Mac 端 listener 的 instance name 是 hostname,
        // 不会包含 "demo-mac" 字面量).
        var chosen: NWEndpoint? = nil
        for r in results {
            if case .service(let name, _, _, _) = r.endpoint {
                if let expected = expectedDeviceId, expected != "demo-mac",
                   !name.contains(expected) { continue }
                chosen = r.endpoint
                break
            }
        }
        guard let endpoint = chosen else { return }
        connect(to: endpoint)
    }

    // MARK: - Connection

    private func connect(to endpoint: NWEndpoint) {
        connection?.cancel()
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let conn = NWConnection(to: endpoint, using: params)
        connection = conn
        transitionTo(.connecting(describe(endpoint)))
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionState(state, endpoint: endpoint)
            }
        }
        conn.start(queue: .main)
    }

    private func handleConnectionState(_ state: NWConnection.State, endpoint: NWEndpoint) {
        switch state {
        case .ready:
            transitionTo(.connected(describe(endpoint)))
            onConnectionChange?(true)
            startHeartbeat()
            receive()
        case .failed(let err):
            lastError = "conn failed: \(err.localizedDescription)"
            transitionTo(.failed(lastError ?? "conn failed"))
            onConnectionChange?(false)
        case .cancelled:
            transitionTo(.idle)
            onConnectionChange?(false)
        default:
            break
        }
    }

    // MARK: - Send / Receive

    private func send(_ frame: MobileRemoteLink.Frame) {
        guard let conn = connection else { return }
        guard let data = try? MobileRemoteLink.encode(frame) else { return }
        var line = data
        line.append(0x0A) // '\n'
        conn.send(content: line, completion: .contentProcessed { [weak self] error in
            if let err = error {
                Task { @MainActor in
                    self?.lastError = "send failed: \(err.localizedDescription)"
                }
            }
        })
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        send(MobileRemoteLink.makeHeartbeat())
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.send(MobileRemoteLink.makeHeartbeat()) }
        }
    }

    private func receive() {
        guard let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            Task { @MainActor in
                if let data = data, !data.isEmpty {
                    self.inboundBuffer.append(data)
                    self.drainFrames()
                }
                if let err = error {
                    self.lastError = "recv error: \(err.localizedDescription)"
                    self.connection?.cancel()
                    return
                }
                if !isComplete { self.receive() }
            }
        }
    }

    private func drainFrames() {
        while let nl = inboundBuffer.firstIndex(of: 0x0A) {
            let line = inboundBuffer.subdata(in: 0..<nl)
            inboundBuffer.removeSubrange(0...nl)
            guard !line.isEmpty else { continue }
            do {
                let frame = try MobileRemoteLink.decode(line)
                handleFrame(frame)
            } catch {
                lastError = "decode error: \(error.localizedDescription)"
            }
        }
    }

    private func handleFrame(_ frame: MobileRemoteLink.Frame) {
        if let id = frame.id {
            if let cb = pendingRequests.removeValue(forKey: id) {
                if let err = frame.error {
                    cb(.failure(NSError(domain: "PairingLink", code: err.code,
                                        userInfo: [NSLocalizedDescriptionKey: err.message])))
                } else {
                    cb(.success(frame.result ?? MobileRemoteLink.Params()))
                }
            }
        } else if frame.isPush {
            onPush?(frame)
        }
    }

    // MARK: - Helpers

    private func describe(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .service(let name, _, _, _): return name
        case .hostPort(let host, let port): return "\(host):\(port)"
        default: return "unknown"
        }
    }

    private func transitionTo(_ next: Status) {
        status = next
    }
}
