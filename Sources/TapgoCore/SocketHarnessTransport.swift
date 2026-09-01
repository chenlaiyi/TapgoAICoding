// SocketHarnessTransport — 连接 TapgoHarness daemon 的 Unix Domain Socket。
//
// PoC for v0.5.72 (harness 解耦)：
// - TapgoHarness daemon 持有 codex app-server 子进程并暴露 Unix socket
// - App 端用本 transport 代替 LocalHarnessTransport，不再持有 codex 进程
// - App 退出时 socket 断开，daemon 继续跑 codex；App 重启后重连即可继续
//
// 接口与 LocalHarnessTransport 完全一致；构造多一个 socketPath。
// PoC 限制：单连接（daemon 端 accept 队列 1），无鉴权（靠 0o600 文件权限）。

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
    private let stdoutBuffer = LineBuffer()

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

        // readability handler 在独立线程跑，转回 MainActor 处理
        let handle = FileHandle(fileDescriptor: s, closeOnDealloc: false)
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard let self = self else { return }
            Task { @MainActor in
                if data.isEmpty {
                    h.readabilityHandler = nil
                    self.handleClose(code: -1)
                } else {
                    self.consumeStdout(data)
                }
            }
        }
    }

    public func stop() {
        guard fd >= 0 else { return }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        handle.readabilityHandler = nil
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

    // 与 LocalHarnessTransport.consumeStdout 等价。复制以避免访问 private。
    private func consumeStdout(_ chunk: Data) {
        stdoutBuffer.append(chunk)
        while let line = stdoutBuffer.popLine() {
            guard !line.isEmpty,
                  let bytes = String(line).data(using: .utf8),
                  let value = try? JSONDecoder().decode(JSONValue.self, from: bytes)
            else {
                print("[socket-transport] non-JSON line: \(String(line).prefix(200))")
                continue
            }
            if value.objectValue == nil { continue }
            collectedFrames.append(value)
            if let id = value.objectValue?["id"]?.intOrBoolAsInt,
               let cb = pendingResponses.removeValue(forKey: id) {
                if let err = value.objectValue?["error"]?.objectValue {
                    let msg = err["message"]?.stringValue ?? "unknown"
                    print("[socket-transport] rpc error id=\(id): \(msg)")
                    cb(.null)
                } else {
                    cb(value.objectValue?["result"] ?? .null)
                }
            } else {
                onNotification?(value)
            }
        }
    }

    private func handleClose(code: Int32) {
        fd = -1
        onClose?(code)
    }
}
