import Foundation
import Network
import TapgoCore

/// Mac 端 Bonjour `_tapgo-pair._tcp` 监听器 + JSON-RPC over TCP 帧解析.
///
/// 流程:
///   - `start(on:)` 后向 Bonjour 注册 `_tapgo-pair._tcp` service
///   - 接收 iOS 端 `PairingLink` (NWBrowser) 的 NWConnection
///   - 解析 JSON-RPC 帧 (MobileRemoteLink 协议层)
///   - 收到 `hello` → 调用 `onId(deviceId)` 回调 + 推 ack
///   - 收到 `request/*` → 路由到 `RequestHandler`
@MainActor
final class PairingLinkListener {

    typealias RequestHandler = @MainActor (_ method: String, _ params: MobileRemoteLink.Params) -> MobileRemoteLink.Params

    private let serviceType: String
    private let preferredPort: UInt16
    private let onId: (String) -> Void
    private let onRequest: RequestHandler?

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var inboundBuffers: [ObjectIdentifier: Data] = [:]
    private let queue: DispatchQueue

    init(serviceType: String = MobileRemoteLink.bonjourServiceType,
         port: UInt16,
         onId: @escaping (String) -> Void,
         onRequest: RequestHandler? = nil,
         queue: DispatchQueue? = nil) {
        self.serviceType = serviceType
        self.preferredPort = port
        self.onId = onId
        self.onRequest = onRequest
        self.queue = queue ?? DispatchQueue(label: "tapgo.pairing-link", qos: .userInitiated)
    }

    deinit { listener?.cancel() }

    func start(on queue: DispatchQueue) {
        guard listener == nil else { return }
        do {
            let tcp = NWParameters.tcp
            tcp.allowLocalEndpointReuse = true
            tcp.includePeerToPeer = true
            let nwListener = try NWListener(using: tcp)
            nwListener.service = NWListener.Service(type: serviceType)
            nwListener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: queue)
                Task { @MainActor in self?.accept(connection) }
            }
            nwListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.handleListenerState(state) }
            }
            nwListener.start(queue: queue)
            listener = nwListener
        } catch {
            NSLog("PairingLinkListener start failed: \(error)")
        }
    }

    func stop() {
        for c in connections.values { c.cancel() }
        connections.removeAll(); inboundBuffers.removeAll()
        listener?.cancel(); listener = nil
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        inboundBuffers[id] = Data()
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handleConnectionState(connection: connection, state: state) }
        }
        receive(on: connection)
    }

    private func handleConnectionState(connection: NWConnection, state: NWConnection.State) {
        let id = ObjectIdentifier(connection)
        switch state {
        case .cancelled, .failed: connections.removeValue(forKey: id); inboundBuffers.removeValue(forKey: id)
        default: break
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        if case .failed(let err) = state {
            NSLog("PairingLinkListener listener failed: \(err)")
            listener = nil
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let data = data, !data.isEmpty {
                    self.append(data, to: connection)
                    self.drainFrames(on: connection)
                }
                if let error = error {
                    NSLog("PairingLinkListener recv error: \(error)")
                    connection.cancel(); return
                }
                if !isComplete { self.receive(on: connection) }
            }
        }
    }

    private func append(_ data: Data, to connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        var buf = inboundBuffers[id] ?? Data()
        buf.append(data); inboundBuffers[id] = buf
    }

    private func drainFrames(on connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        guard var buf = inboundBuffers[id] else { return }
        while let nl = buf.firstIndex(of: 0x0A) {
            let line = buf.subdata(in: 0..<nl)
            buf.removeSubrange(0...nl)
            guard !line.isEmpty else { continue }
            if let frame = try? MobileRemoteLink.decode(line) {
                handleFrame(frame, on: connection)
            } else {
                NSLog("PairingLinkListener decode error")
            }
        }
        inboundBuffers[id] = buf
    }

    private func handleFrame(_ frame: MobileRemoteLink.Frame, on connection: NWConnection) {
        if frame.isRequest { handleRequest(frame, on: connection); return }
        if frame.isPush { handlePush(frame, on: connection); return }
    }

    private func handlePush(_ frame: MobileRemoteLink.Frame, on connection: NWConnection) {
        guard frame.method == MobileRemoteLink.Method.hello else { return }
        let id = frame.params?["deviceId"]?.stringValue ?? ""
        onId(id)
        let ack = MobileRemoteLink.makePush(method: "ack", params: MobileRemoteLink.Params())
        send(frame: ack, on: connection)
    }

    private func handleRequest(_ frame: MobileRemoteLink.Frame, on connection: NWConnection) {
        guard let id = frame.id, let method = frame.method else { return }
        if let onRequest = onRequest {
            let result = onRequest(method, frame.params ?? MobileRemoteLink.Params())
            send(frame: MobileRemoteLink.makeResult(id: id, result: result), on: connection)
        } else {
            let err = MobileRemoteLink.makeError(id: id, code: -1, message: "no handler for \(method)")
            send(frame: err, on: connection)
        }
    }

    private func send(frame: MobileRemoteLink.Frame, on connection: NWConnection) {
        guard let data = try? MobileRemoteLink.encode(frame) else { return }
        var line = data; line.append(0x0A)
        connection.send(content: line, completion: .contentProcessed { _ in })
    }
}
