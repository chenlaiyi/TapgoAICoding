// TapgoHarness — stdio↔Unix socket bridge for codex app-server.
//
// PoC for v0.5.72 (harness 解耦)：把 harness 子进程抽成独立 daemon，
// 让 App 退出后 harness 还能继续跑，App 重启后重新连上即可继续工作。
//
// Lifecycle:
//   1. CLI args: <socket-path> <codex-path> <codex-home>
//   2. OPENAI_API_KEY 从环境变量读（由 launchd plist 或启动脚本注入）
//   3. spawn `codex app-server --listen stdio://`
//   4. bind+listen Unix Domain Socket，等客户端连
//   5. 客户端连上后，socket <-> codex stdio 双向字节转发
//   6. 任一端 EOF：优雅关另一端，等 codex 退出，清理 socket 文件
//
// PoC 限制：单客户端，无 token 鉴权，靠文件系统权限保护（0o600）。

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

// codex stderr 直接透传到我们 stderr，方便诊断
stderrPipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    if !data.isEmpty { FileHandle.standardError.write(data) }
}

do {
    try proc.run()
} catch {
    stderrLog("failed to spawn codex: \(error.localizedDescription)")
    exit(1)
}
stderrLog("codex app-server pid=\(proc.processIdentifier), CODEX_HOME=\(codexHomePath)")

// Unix Domain Socket listen
let listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
guard listenFD >= 0 else {
    stderrLog("socket() failed: \(String(cString: strerror(errno)))")
    proc.terminate()
    exit(1)
}

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(socketPath.utf8)
guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
    stderrLog("socket path too long (\(pathBytes.count) bytes): \(socketPath)")
    close(listenFD)
    proc.terminate()
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
    proc.terminate()
    exit(1)
}
guard listen(listenFD, 1) == 0 else {
    stderrLog("listen() failed: \(String(cString: strerror(errno)))")
    close(listenFD)
    proc.terminate()
    exit(1)
}
chmod(socketPath, 0o600)
stderrLog("listening on \(socketPath)")

// 接受一个客户端（PoC 简化，后续可扩展为多客户端）
let clientFD = accept(listenFD, nil, nil)
guard clientFD >= 0 else {
    stderrLog("accept() failed: \(String(cString: strerror(errno)))")
    close(listenFD)
    proc.terminate()
    exit(1)
}
stderrLog("client connected fd=\(clientFD)")

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

// 等 codex 退出
proc.waitUntilExit()
stderrLog("codex exited status=\(proc.terminationStatus)")

// 清理
shutdown(clientFD, SHUT_RDWR)
close(clientFD)
close(listenFD)
try? FileManager.default.removeItem(at: socketURL)
stderrLog("shutdown complete")
