// TapgoHarness — stdio↔Unix socket bridge for codex app-server.
//
// PoC for v0.5.72 (harness 解耦)：把 harness 子进程抽成独立 daemon，
// 让 App 退出后 harness 还能继续跑，App 重启后重新连上即可继续工作。
//
// Lifecycle:
//   1. CLI args: <socket-path> <codex-path> <codex-home>
//   2. OPENAI_API_KEY 从环境变量读（由 launchd plist 或启动脚本注入）
//   3. bind+listen Unix Domain Socket，循环接受客户端
//   4. 接受到客户端连接后，spawn `codex app-server --listen stdio://`，
//      在客户端 fd 与 codex stdio 之间双向桥接
//   5. 客户端断开 → codex 退出 → 回到 accept() 等下一个客户端
//   6. 进程生命周期由 launchd 管理，daemon 自身不主动 exit
//
// PoC 限制：单客户端串行（同一时刻只服务一个客户端；新客户端在 listen
// 队列里排队），无 token 鉴权，靠文件系统权限保护（0o600）。

import Foundation
import Darwin

func stderrLog(_ message: String) {
    FileHandle.standardError.write(Data("[tapgo-harness] \(message)\n".utf8))
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 3 else {
    stderrLog("usage: TapgoHarness <socket-path> <codex-path> <codex-home>")
    exit(2)
}
let socketPath = args[0]
let codexPath = args[1]
let codexHomePath = args[2]
guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
    stderrLog("OPENAI_API_KEY env var is required")
    exit(2)
}

// 确保 socket 父目录存在
let socketURL = URL(fileURLWithPath: socketPath)
try? FileManager.default.createDirectory(
    at: socketURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
// 清理残留 socket 文件（上次崩溃可能留下）
try? FileManager.default.removeItem(at: socketURL)

// spawn codex app-server
// 注意：proc 必须在每次客户端连接时重新创建（每个客户端连接都是独立的
// codex app-server 会话；codex 设计上要求每个 stdio 连接独立 handshake）
func spawnCodex() throws -> (Process, Pipe, Pipe, Pipe) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: codexPath)
    proc.arguments = ["app-server", "--listen", "stdio://"]
    var env = ProcessInfo.processInfo.environment
    env["CODEX_HOME"] = codexHomePath
    env["OPENAI_API_KEY"] = apiKey
    env["TERM"] = "xterm-256color"
    if env["LANG"] == nil { env["LANG"] = "C.UTF-8" }
    proc.environment = env

    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    proc.standardInput = stdinPipe
    proc.standardOutput = stdoutPipe
    proc.standardError = stderrPipe
    try proc.run()
    stderrLog("codex app-server pid=\(proc.processIdentifier), CODEX_HOME=\(codexHomePath)")
    return (proc, stdinPipe, stdoutPipe, stderrPipe)
}

// Unix Domain Socket listen
let listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
guard listenFD >= 0 else {
    stderrLog("socket() failed: \(String(cString: strerror(errno)))")
    exit(1)
}

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(socketPath.utf8)
guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
    stderrLog("socket path too long (\(pathBytes.count) bytes): \(socketPath)")
    close(listenFD)
    exit(1)
}
withUnsafeMutablePointer(to: &addr.sun_path) { pathDest in
    pathDest.withMemoryRebound(to: CChar.self, capacity: pathBytes.count + 1) { rebound in
        for (i, b) in pathBytes.enumerated() { rebound[i] = CChar(b) }
        rebound[pathBytes.count] = 0
    }
}
let bindResult = withUnsafePointer(to: &addr) { ptr in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
        bind(listenFD, saPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard bindResult == 0 else {
    stderrLog("bind() failed: \(String(cString: strerror(errno)))")
    close(listenFD)
    exit(1)
}
guard listen(listenFD, 8) == 0 else {
    stderrLog("listen() failed: \(String(cString: strerror(errno)))")
    close(listenFD)
    exit(1)
}
chmod(socketPath, 0o600)
stderrLog("listening on \(socketPath)")

// 接受客户端循环：每次客户端断开就关掉 codex，回到 accept 等下一个连接。
// daemon 自身不退出，由 launchd 管理生命周期。
while true {
    let clientFD = accept(listenFD, nil, nil)
    if clientFD < 0 {
        if errno == EINTR { continue }
        stderrLog("accept() failed: \(String(cString: strerror(errno)))")
        // accept 失败但不退出 daemon；下一次 accept 可能成功
        continue
    }
    stderrLog("client connected fd=\(clientFD)")

    let (proc, stdinPipe, stdoutPipe, stderrPipe): (Process, Pipe, Pipe, Pipe)
    do {
        (proc, stdinPipe, stdoutPipe, stderrPipe) = try spawnCodex()
    } catch {
        stderrLog("failed to spawn codex: \(error.localizedDescription)")
        close(clientFD)
        continue
    }

    // codex stderr 直接透传到我们 stderr，方便诊断
    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if !data.isEmpty { FileHandle.standardError.write(data) }
    }

    let bridgeDone = DispatchSemaphore(value: 0)

    // codex 退出时通知我们，避免 waitUntilExit 阻塞
    let procExited = DispatchSemaphore(value: 0)
    proc.terminationHandler = { p in
        stderrLog("codex app-server exited status=\(p.terminationStatus)")
        procExited.signal()
    }

    // socket -> codex stdin（后台线程）
    let stdinWriter = stdinPipe.fileHandleForWriting
    let bridgeQueue = DispatchQueue(label: "tapgo.harness.bridge", qos: .userInitiated)
    bridgeQueue.async {
        var buf = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = read(clientFD, &buf, buf.count)
            if n > 0 {
                let data = Data(bytes: buf, count: n)
                do {
                    try stdinWriter.write(contentsOf: data)
                } catch {
                    // codex stdin 已关（进程退出），停止读
                    stderrLog("stdin write failed, codex likely exited: \(error.localizedDescription)")
                    break
                }
            } else if n == 0 {
                stderrLog("socket EOF (client disconnected)")
                break
            } else {
                if errno == EINTR { continue }
                stderrLog("read() failed: \(String(cString: strerror(errno)))")
                break
            }
        }
        try? stdinWriter.close()
        bridgeDone.signal()
    }

    // codex stdout -> socket
    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if data.isEmpty {
            // codex stdout EOF = codex 退出
            handle.readabilityHandler = nil
            shutdown(clientFD, SHUT_WR)
            return
        }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var remaining = data.count
            var offset = 0
            while remaining > 0 {
                let n = send(clientFD, base.advanced(by: offset), remaining, 0)
                if n <= 0 {
                    if errno == EINTR { continue }
                    handle.readabilityHandler = nil
                    return
                }
                offset += n
                remaining -= n
            }
        }
    }

    // 等客户端 EOF → 关闭 stdin → 等 codex 退出 → 清理 fd
    bridgeDone.wait()
    stderrPipe.fileHandleForReading.readabilityHandler = nil
    stdoutPipe.fileHandleForReading.readabilityHandler = nil
    // 给 codex 最多 2 秒自然退出（read 关闭 stdin 后应该立即退出）
    let procResult = procExited.wait(timeout: .now() + 2.0)
    if procResult == .timedOut {
        stderrLog("codex didn't exit after stdin close; terminating")
        if proc.isRunning { proc.terminate() }
        procExited.wait()
    }
    // 强制关掉 socket 半连接
    shutdown(clientFD, SHUT_RDWR)
    close(clientFD)
    stderrLog("client session ended; returning to accept()")
}
