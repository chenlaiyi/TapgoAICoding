// HarnessDaemonLauncher — App 内的 daemon 自启动逻辑（v0.5.72 harness 解耦）。
//
// 行为：
//   1. 检查 socket 文件是否存在
//   2. 不存在则尝试启动 daemon（spawn Process 跑 TapgoHarness）
//   3. 短暂轮询等 socket 文件出现
//   4. 成功返回 true；失败返回 false（让上层降级到 LocalHarnessTransport）
//
// 路径解析优先级：
//   - $TAPGO_HARNESS_DAEMON_BIN 环境变量（开发期覆盖）
//   - ~/.tapgo-aicoding/bin/TapgoHarness（install 脚本安装位置）
//   - <App>/Contents/Resources/TapgoHarness（未来打包后位置，PoC 暂未实现）

import Foundation

public enum HarnessDaemonLauncher {
    /// 默认 socket 路径（与 SessionStore.daemonSocketPath 一致）。
    public static let socketPath: String = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("Tapgo AICoding")
            .appendingPathComponent("run")
            .appendingPathComponent("harness.sock")
            .path
    }()

    /// daemon 二进制路径（dev override > install dir > App Resources）。
    public static let daemonBinaryPath: String = {
        if let override = ProcessInfo.processInfo.environment["TAPGO_HARNESS_DAEMON_BIN"],
           !override.isEmpty {
            return override
        }
        let home = NSHomeDirectory()
        let installed = "\(home)/.tapgo-aicoding/bin/TapgoHarness"
        if FileManager.default.isExecutableFile(atPath: installed) {
            return installed
        }
        // App bundle 内的 daemon（未来打包后位置）
        if let bundlePath = Bundle.main.path(forResource: "TapgoHarness", ofType: nil) {
            return bundlePath
        }
        return installed
    }()

    /// 确保 daemon 在跑：socket 在就直接返回；不在则尝试启动并等待。
    /// - Returns: daemon 是否就绪（socket 文件可连）
    public static func ensureDaemonRunning(codexHome: URL, apiKey: String) -> Bool {
        if FileManager.default.fileExists(atPath: socketPath) {
            return true
        }
        let binPath = daemonBinaryPath
        guard FileManager.default.isExecutableFile(atPath: binPath) else {
            return false
        }
        guard spawnDaemon(binaryPath: binPath, codexHome: codexHome, apiKey: apiKey) else {
            return false
        }
        return waitForSocket(at: socketPath, timeoutSeconds: 3.0)
    }

    private static func spawnDaemon(binaryPath: String, codexHome: URL, apiKey: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = [
            socketPath,
            "/opt/homebrew/bin/codex",
            codexHome.path,
        ]
        var env = ProcessInfo.processInfo.environment
        env["OPENAI_API_KEY"] = apiKey
        env["TERM"] = "xterm-256color"
        if env["LANG"] == nil { env["LANG"] = "C.UTF-8" }
        proc.environment = env
        // daemon 自己管日志，这里把 stdio 重定向到 /dev/null（避免 App 持有 daemon 的 stdio）
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            return true
        } catch {
            return false
        }
        // 注：proc 不保留引用，进程由 launchd 或独立生命周期管；App 不应等它退出
    }

    /// 阻塞轮询 socket 文件出现。PoC 阶段简化用主线程 sleep，最多 timeoutSeconds 秒。
    private static func waitForSocket(at path: String, timeoutSeconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
            usleep(100_000)
        }
        return false
    }
}
