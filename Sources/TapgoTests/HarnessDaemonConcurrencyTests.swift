import Foundation
import Darwin

// MARK: - v0.5.319 TapgoHarness 多客户端并发回归
//
// 背景：v0.5.72–v0.5.318 的 daemon 是「单客户端串行」——同一时刻只服务
// 一条连接，第二条连接只能在 listen backlog 里排队，直到第一条会话结束
// 才被 accept。App 每个线程 / 每个 turn 都会新建一条连接，于是「一个会话
// 正在跑」时，另一个会话的 `initialize` 永远拿不到响应，30 秒后命中
// `Harness RPC 超时：initialize`，用户看到「处理未完成 / 任务未完成，可重试」，
// 严重时整个 App 看起来不可用。
//
// 本测试用真实 TapgoHarness 二进制 + 一个假 codex（把每行请求回一条 JSON）
// 覆盖这个回归：
//   1. 建 A 连接并保持空闲（不发任何请求）
//   2. 建 B 连接发送 initialize，必须在数秒内拿到响应（修复前必超时）
//   3. A 保持不动，再建 C 连接，同样要立刻拿到响应
//
// 假 codex 替代真 codex app-server：这里验证的是「daemon 的 accept 循环
// 是否被单条会话阻塞」，与模型侧无关。

/// Unix Domain Socket 路径上限 104 字节，用短路径。
private func daemonProbeSocketPath() -> String {
    "/tmp/tapgo-daemon-\(UUID().uuidString.prefix(8)).sock"
}

/// 与测试可执行文件同目录（swift build 产物目录）下的 TapgoHarness。
private func locateHarnessBinary() -> String? {
    let exec = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let candidate = exec.deletingLastPathComponent()
        .appendingPathComponent("TapgoHarness").path
    if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
    // `swift run` 有时从 .build/debug 符号链接启动，退回解析后的目录再找一次。
    if let real = try? FileManager.default.destinationOfSymbolicLink(atPath: CommandLine.arguments[0]) {
        let alt = URL(fileURLWithPath: real).deletingLastPathComponent()
            .appendingPathComponent("TapgoHarness").path
        if FileManager.default.isExecutableFile(atPath: alt) { return alt }
    }
    return nil
}

/// 假 codex：忽略命令行参数，每读到一行就回一条 JSON-RPC 响应。
private func writeFakeCodex(at url: URL) throws {
    let script = """
    #!/bin/sh
    while IFS= read -r _line; do
      printf '{"jsonrpc":"2.0","id":1,"result":{"echo":true}}\\n'
    done
    """
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

private func connectUnixSocket(_ path: String, receiveTimeout: Int = 6) -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return -1 }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
        close(fd)
        return -1
    }
    withUnsafeMutablePointer(to: &addr.sun_path) { p in
        p.withMemoryRebound(to: CChar.self, capacity: bytes.count + 1) { dst in
            for (i, b) in bytes.enumerated() { dst[i] = CChar(b) }
            dst[bytes.count] = 0
        }
    }
    let connected = withUnsafePointer(to: &addr) { p in
        p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else {
        close(fd)
        return -1
    }
    var tv = timeval(tv_sec: receiveTimeout, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    return fd
}

private func sendAll(_ fd: Int32, _ text: String) -> Bool {
    let data = Data(text.utf8)
    return data.withUnsafeBytes { raw -> Bool in
        guard let base = raw.baseAddress else { return false }
        var remaining = data.count
        var offset = 0
        while remaining > 0 {
            let n = send(fd, base.advanced(by: offset), remaining, 0)
            if n <= 0 {
                if errno == EINTR { continue }
                return false
            }
            offset += n
            remaining -= n
        }
        return true
    }
}

/// 读一行（换行结尾）响应；超时 / EOF 返回 nil。
private func readResponseLine(_ fd: Int32) -> String? {
    var buffer = Data()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = recv(fd, &chunk, chunk.count, 0)
        if n > 0 {
            buffer.append(contentsOf: chunk[0..<n])
            if let newline = buffer.firstIndex(of: 0x0A) {
                return String(data: buffer[buffer.startIndex..<newline], encoding: .utf8)
            }
        } else if n == 0 {
            return buffer.isEmpty ? nil : String(data: buffer, encoding: .utf8)
        } else {
            if errno == EINTR { continue }
            return nil // EAGAIN（超时）或其它错误
        }
    }
}

@MainActor
func runHarnessDaemonServesConcurrentClients(_ t: TestRunner) {
    t.section("TapgoHarness daemon: 并发客户端都能拿到 initialize 响应")

    guard let harnessBinary = locateHarnessBinary() else {
        t.expect(false, "找到 TapgoHarness 产物（先跑 swift build）")
        return
    }

    let workDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tapgo-daemon-test-\(UUID().uuidString)")
    let socketPath = daemonProbeSocketPath()
    let codexHome = workDir.appendingPathComponent("codex-home")
    let fakeCodex = workDir.appendingPathComponent("fake-codex")
    try? FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    do {
        try writeFakeCodex(at: fakeCodex)
    } catch {
        t.expect(false, "写入假 codex 脚本: \(error.localizedDescription)")
        return
    }

    defer {
        try? FileManager.default.removeItem(atPath: socketPath)
        try? FileManager.default.removeItem(at: workDir)
    }

    // 启动真实 daemon（假 codex + 临时 socket）
    let daemon = Process()
    daemon.executableURL = URL(fileURLWithPath: harnessBinary)
    daemon.arguments = [socketPath, fakeCodex.path, codexHome.path]
    var env = ProcessInfo.processInfo.environment
    env["OPENAI_API_KEY"] = "test-key"
    daemon.environment = env
    daemon.standardOutput = FileHandle.nullDevice
    daemon.standardError = FileHandle.nullDevice
    do {
        try daemon.run()
    } catch {
        t.expect(false, "启动 TapgoHarness: \(error.localizedDescription)")
        return
    }
    defer {
        if daemon.isRunning { daemon.terminate() }
        let deadline = Date().addingTimeInterval(2.0)
        while daemon.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
    }

    // 等 socket 出现（最多 5 秒）
    var ready = false
    let socketDeadline = Date().addingTimeInterval(5.0)
    while Date() < socketDeadline {
        if FileManager.default.fileExists(atPath: socketPath) { ready = true; break }
        Thread.sleep(forTimeInterval: 0.05)
    }
    t.expect(ready, "daemon 在 5 秒内建好 socket")

    // A：空闲长连接（模拟已经占用会话的另一个线程 / turn）
    let clientA = connectUnixSocket(socketPath)
    t.expect(clientA >= 0, "客户端 A 能连上 daemon")

    // B：第二条连接必须立刻拿到 initialize 响应（修复前会被 A 阻塞到超时）
    let start = Date()
    let clientB = connectUnixSocket(socketPath)
    t.expect(clientB >= 0, "客户端 B 能连上 daemon（A 仍在连接中）")
    if clientB >= 0 {
        let sent = sendAll(clientB, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}\n")
        t.expect(sent, "客户端 B 发出 initialize")
        let line = readResponseLine(clientB)
        let elapsed = Date().timeIntervalSince(start)
        t.expect(line?.contains("\"echo\":true") == true,
                 "客户端 B 在 A 占线时也拿到了 initialize 响应（实际: \(line ?? "超时/EOF")）")
        t.expect(elapsed < 5.0, "客户端 B 响应耗时 < 5s（实际 \(String(format: "%.2f", elapsed))s）")
        close(clientB)
    }

    // C：A 依然占线，第三条连接同样要立刻被服务
    let clientC = connectUnixSocket(socketPath)
    t.expect(clientC >= 0, "客户端 C 能连上 daemon")
    if clientC >= 0 {
        _ = sendAll(clientC, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}\n")
        let line = readResponseLine(clientC)
        t.expect(line?.contains("\"echo\":true") == true,
                 "客户端 C 在 A 占线时也拿到了 initialize 响应（实际: \(line ?? "超时/EOF")）")
        close(clientC)
    }

    if clientA >= 0 { close(clientA) }
}
