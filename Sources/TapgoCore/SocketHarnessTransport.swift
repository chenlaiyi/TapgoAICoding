// SocketHarnessTransport — 连接 TapgoHarness daemon 的 Unix Domain Socket。
//
// v0.5.72 起把 harness 子进程抽成独立 daemon；App 端用本 transport 通过
// Unix socket 与 daemon 通信。daemon 持有 codex app-server 子进程并做 stdio
// ↔ socket 双向桥接。App 退出时 socket 断开，daemon 仍持有 codex。
//
// 实现注意（v0.5.74）：v0.5.73 用的 `FileHandle.readabilityHandler` 在 macOS
// 27 上对 Unix domain socket 偶尔把可读事件回调成 `Data.isEmpty`，
// 触发到 EOF 路径、关掉 fd 并让 supervisor 重启 + 客户端 30 秒 watchdog 命中。
// 这里换成 `DispatchSource.makeReadSource`，它对 Unix socket 只在「真的可读」
// 或「真的 EOF/hangup」时触发，EOF 由 `recv` 返回 0 显式判断。
//
// 接口与 LocalHarnessTransport 完全一致；构造多一个 socketPath。
// 单连接（daemon 端 listen backlog = 8，无鉴权，靠 0o600 文件权限）。

import Foundation
import Darwin

public final class SocketHarnessTransport: HarnessTransport {
    public let socketPath: String
    /// 保留字段，与 LocalHarnessTransport 对齐（实际由 daemon 端使用）。
    public let codexHome: URL
    /// 保留字段（实际由 daemon 端从环境读）。
    public let apiKey: String

    public var onNotification: ((JSONValue) -> Void)?
    public var onClose: ((Int32) -> Void)?

    /// Test-only：缓存所有收到的帧，给集成测试检视。
    public private(set) var collectedFrames: [JSONValue] = []
    /// Test-only / 内部 RPC 关联：pending 响应的回调。
    public var pendingResponses: [Int: (JSONValue) -> Void] = [:]

    private var fd: Int32 = -1
    /// DispatchSource for read events on `fd`。Start 时 resume，stop / EOF 时 cancel。
    private var readSource: DispatchSourceRead?
    /// Read source 跑在哪个串行 queue 上。
    private let readQueue = DispatchQueue(label: "tapgo.harness.socket.read", qos: .userInitiated)
    private let stdoutBuffer = LineBuffer()
    /// dispatch hop 到 MainActor 处理 onNotification / onClose / pendingResponses。
    /// SocketHarnessTransport 自身不在 MainActor 上，但 CodexHarnessClient 是
    /// @MainActor，二者交互需要切到 MainActor。
    private let mainActorQueue = DispatchQueue.main

    public init(socketPath: String, codexHome: URL, apiKey: String) {
        self.socketPath = socketPath
        self.codexHome = codexHome
        self.apiKey = apiKey
    }

    public var isRunning: Bool { fd >= 0 }

    public func start() throws {
        guard fd < 0 else { return }
        // socket 文件不存在 = daemon 没启动，让上层降级到 LocalHarnessTransport
        guard FileManager.default.fileExists(atPath: socketPath) else {
            throw HarnessTransportError.notRunning
        }
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else {
            throw HarnessTransportError.notRunning
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(s)
            throw HarnessTransportError.notRunning
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { pathDest in
            pathDest.withMemoryRebound(to: CChar.self, capacity: pathBytes.count + 1) { rebound in
                for (i, b) in pathBytes.enumerated() { rebound[i] = CChar(b) }
                rebound[pathBytes.count] = 0
            }
        }
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                Darwin.connect(s, saPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connectResult != 0 {
            close(s)
            throw HarnessTransportError.notRunning
        }
        fd = s

        // DispatchSourceRead 在 readQueue 串行调度；handler 内只做 sync read
        // 然后 hop 到 MainActor 上更新 transport 状态。
        let source = DispatchSource.makeReadSource(fileDescriptor: s, queue: readQueue)
        source.setEventHandler { [weak self] in
            self?.drainSocket()
        }
        source.setCancelHandler { [weak self] in
            // fd 在 stop() 里负责关闭；这里只清 readSource 引用，避免泄漏。
            _ = self
        }
        source.resume()
        readSource = source
    }

    public func stop() {
        readSource?.cancel()
        readSource = nil
        guard fd >= 0 else { return }
        shutdown(fd, SHUT_RDWR)
        close(fd)
        fd = -1
    }

    public func send(frame: JSONValue) throws {
        guard fd >= 0 else {
            throw HarnessTransportError.notRunning
        }
        var data = try JSONEncoder().encode(frame)
        data.append(0x0A)
        // 同步写循环，处理 EINTR 和部分写入
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else {
                throw HarnessTransportError.notRunning
            }
            var remaining = data.count
            var offset = 0
            while remaining > 0 {
                let n = Darwin.send(fd, base.advanced(by: offset), remaining, 0)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw HarnessTransportError.notRunning
                }
                offset += n
                remaining -= n
            }
        }
    }

    // MARK: - Read path

    /// DispatchSource handler：阻塞 read 直到 EAGAIN，EOF / hangup 时退出。
    /// 完全同步，避免 FileHandle.readabilityHandler 把可读事件当成 EOF 的 bug。
    private func drainSocket() {
        guard fd >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
                Darwin.recv(fd, ptr.baseAddress!, ptr.count, 0)
            }
            if n > 0 {
                let chunk = Data(bytes: buffer, count: n)
                consumeStdout(chunk)
            } else if n == 0 {
                // 真正的 EOF：对端干净关闭。
                handleClose(code: 0)
                return
            } else {
                let err = errno
                if err == EINTR { continue }
                if err == EAGAIN || err == EWOULDBLOCK {
                    // 没数据可读，等下一次 DispatchSource 事件。
                    return
                }
                // 其他错误当作异常关闭。
                handleClose(code: Int32(err))
                return
            }
        }
    }

    // consumeStdout 与 LocalHarnessTransport 同形；切到 MainActor 以保证
    // pendingResponses / onNotification / onClose 在 MainActor 上被读。
    private func consumeStdout(_ chunk: Data) {
        mainActorQueue.async { [weak self] in
            guard let self = self else { return }
            self.stdoutBuffer.append(chunk)
            while let line = self.stdoutBuffer.popLine() {
                guard !line.isEmpty,
                      let bytes = String(line).data(using: .utf8),
                      let value = try? JSONDecoder().decode(JSONValue.self, from: bytes)
                else {
                    print("[socket-transport] non-JSON line: \(String(line).prefix(200))")
                    continue
                }
                if value.objectValue == nil { continue }
                self.collectedFrames.append(value)
                if let id = value.objectValue?["id"]?.intOrBoolAsInt,
                   let cb = self.pendingResponses.removeValue(forKey: id) {
                    if let err = value.objectValue?["error"]?.objectValue {
                        let msg = err["message"]?.stringValue ?? "unknown"
                        print("[socket-transport] rpc error id=\(id): \(msg)")
                        cb(.null)
                    } else {
                        cb(value.objectValue?["result"] ?? .null)
                    }
                } else {
                    self.onNotification?(value)
                }
            }
        }
    }

    private func handleClose(code: Int32) {
        let closeCode = code
        mainActorQueue.async { [weak self] in
            guard let self = self else { return }
            if self.fd >= 0 {
                self.fd = -1
            }
            // 不在这里 cancel readSource；让 DispatchSource 自然 cancel（系统会在 fd 关闭后触发 cancel handler）。
            // 但要确保 cancel handler 不会重复 close。
            self.readSource?.cancel()
            self.readSource = nil
            self.onClose?(closeCode)
        }
    }
}
