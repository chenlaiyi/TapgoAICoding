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
//   5. 客户端断开 → codex 退出 → 该会话线程结束，accept 循环继续
//   6. 进程生命周期由 launchd 管理，daemon 自身不主动 exit
//
// v0.5.319 并发修复（本文件）：v0.5.72–v0.5.318 是单客户端串行——daemon
// 在会话内阻塞，第二个连接只能在 listen backlog 里排队，直到第一个会话
// 结束才被 accept。App 侧每个线程/turn 都会新建一条连接，于是「一个会话
// 正在跑」时，另一个会话的 `initialize` 永远得不到响应，30 秒后命中
// `Harness RPC 超时：initialize`，用户看到的就是「处理未完成 / 任务未完成，
// 可重试」，严重时整个 App 看起来不可用。现在每条连接一个独立线程 +
// 独立 codex app-server，互不阻塞（活跃会话数写进 stderr 日志便于诊断）。
//
// 安全：socket 文件 0o600，无 token 鉴权，仅本机用户可连。

import Foundation
import Darwin

func stderrLog(_ message: String) {
    FileHandle.standardError.write(Data("[tapgo-harness] \(message)\n".utf8))
}

// 客户端可能在任何时刻断开；向已关闭的 socket 写入会触发 SIGPIPE，
// 默认动作是直接杀死进程——多客户端后这种半关闭更常见，必须忽略，
// 让 send() 返回 EPIPE，由会话自行收尾。
signal(SIGPIPE, SIG_IGN)

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

/// 活跃会话计数，仅用于日志（多线程访问，加锁）。
final class SessionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    func begin() -> Int {
        lock.lock(); defer { lock.unlock() }
        active += 1
        return active
    }
    func end() -> Int {
        lock.lock(); defer { lock.unlock() }
        active -= 1
        return active
    }
}
let sessions = SessionCounter()

// spawn codex app-server
// 注意：proc 必须在每次客户端连接时重新创建（每个客户端连接都是独立的
// codex app-server 会话；codex 设计上要求每个 stdio 连接独立 handshake）
func spawnCodex() throws -> (Process, Pipe, Pipe, Pipe) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: codexPath)
    proc.arguments = ["app-server", "--listen", "stdio://"]
    var env = ProcessInfo.processInfo.environment
    // npm 版 codex 是 `#!/usr/bin/env node` 脚本；App 传来的 PATH 若缺
    // Homebrew bin，这里补一份，保证 GUI/launchd 场景也能解析 node
    // （v0.5.109 修）。
    let pathPrefix = ["/opt/homebrew/bin", "/usr/local/bin",
                      "\(NSHomeDirectory())/.local/bin"]
    let existing = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    env["PATH"] = (pathPrefix + [existing]).joined(separator: ":")
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

/// 把一个 fd 上的 codex stdout 全量写进客户端 socket。
/// 返回 false 表示客户端已不可写（对端关闭/出错），调用方应尽快收尾。
func pumpStdoutToClient(_ clientFD: Int32, _ handle: FileHandle) -> Bool {
    while true {
        let data = handle.availableData
        if data.isEmpty {
            // codex stdout EOF = codex 退出；半关写方向，让客户端读到 EOF。
            shutdown(clientFD, SHUT_WR)
            return false
        }
        let ok = data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var remaining = data.count
            var offset = 0
            while remaining > 0 {
                let n = send(clientFD, base.advanced(by: offset), remaining, 0)
                if n <= 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += n
                remaining -= n
            }
            return true
        }
        if !ok { return false }
    }
}

/// 服务一条客户端连接：独立 codex app-server + 双向桥接。
/// 在专属线程上运行，绝不阻塞 accept 循环（v0.5.319）。
func serveClient(_ clientFD: Int32) {
    let active = sessions.begin()
    stderrLog("client connected fd=\(clientFD) (active sessions=\(active))")

    let (proc, stdinPipe, stdoutPipe, stderrPipe): (Process, Pipe, Pipe, Pipe)
    do {
        (proc, stdinPipe, stdoutPipe, stderrPipe) = try spawnCodex()
    } catch {
        stderrLog("failed to spawn codex: \(error.localizedDescription)")
        close(clientFD)
        stderrLog("client session ended (active sessions=\(sessions.end()))")
        return
    }

    let stdinWriter = stdinPipe.fileHandleForWriting
    let stdoutReader = stdoutPipe.fileHandleForReading
    let stderrReader = stderrPipe.fileHandleForReading

    // codex stderr 直接透传到我们 stderr，方便诊断
    let stderrThread = Thread {
        while true {
            let data = stderrReader.availableData
            if data.isEmpty { break }
            FileHandle.standardError.write(data)
        }
    }
    stderrThread.name = "tapgo.harness.codex-stderr"
    stderrThread.start()

    // codex stdout → 客户端 socket
    let stdoutThread = Thread {
        _ = pumpStdoutToClient(clientFD, stdoutReader)
    }
    stdoutThread.name = "tapgo.harness.codex-stdout"
    stdoutThread.start()

    // 客户端 socket → codex stdin（本线程；读到 EOF 即会话结束）
    var buf = [UInt8](repeating: 0, count: 8192)
    while true {
        let n = read(clientFD, &buf, buf.count)
        if n > 0 {
            do {
                try stdinWriter.write(contentsOf: Data(bytes: buf, count: n))
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

    // 给 codex 最多 2 秒自然退出（read 关闭 stdin 后应该立即退出）
    let softDeadline = Date().addingTimeInterval(2.0)
    while proc.isRunning, Date() < softDeadline {
        Thread.sleep(forTimeInterval: 0.02)
    }
    if proc.isRunning {
        stderrLog("codex didn't exit after stdin close; terminating")
        proc.terminate()
        let hardDeadline = Date().addingTimeInterval(1.0)
        while proc.isRunning, Date() < hardDeadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    // 强制关掉 socket 半连接；stdout 泵会在下一次 send 失败后自行退出
    shutdown(clientFD, SHUT_RDWR)
    close(clientFD)
    stderrLog("client session ended (active sessions=\(sessions.end()))")
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
guard listen(listenFD, 32) == 0 else {
    stderrLog("listen() failed: \(String(cString: strerror(errno)))")
    close(listenFD)
    exit(1)
}
chmod(socketPath, 0o600)
stderrLog("listening on \(socketPath)")

// Accept 循环：每条连接起一个独立线程（v0.5.319 起支持多客户端并发）。
// 客户端断开 → 该会话关闭自己的 codex → 线程结束，accept 立即继续。
// daemon 自身不退出，由 launchd 管理生命周期。
while true {
    let clientFD = accept(listenFD, nil, nil)
    if clientFD < 0 {
        if errno == EINTR { continue }
        stderrLog("accept() failed: \(String(cString: strerror(errno)))")
        // accept 失败但不退出 daemon；下一次 accept 可能成功
        continue
    }
    // codex 子进程不该继承客户端 fd（Foundation 的 Process 默认即
    // CLOEXEC，这里再显式兜一层，避免客户端断开后读端仍被持有）。
    _ = fcntl(clientFD, F_SETFD, FD_CLOEXEC)
    let thread = Thread { serveClient(clientFD) }
    thread.name = "tapgo.harness.client-\(clientFD)"
    thread.start()
}
