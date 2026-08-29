import Foundation
import TapgoCore

/// 公网中继隧道 (v0.5.17): 常驻 `ssh -N -R` 反向隧道, 把服务器上
/// `127.0.0.1:<serverForwardPort>` 转发回本机 `127.0.0.1:<localPort>` 的
/// 手机远程控制 HTTP 服务, nginx 再把 `https://pay.itapgo.com/remote/<machine>/`
/// 压到该端口。三台 Mac 各占一个服务器端口, 互不冲突。
///
/// 监督策略: 进程意外退出 (断网/服务器重启) 后 3s 自动重连; 连续快速失败
/// 超过阈值转入 `failed` 并降频到 15s 重试 (典型原因: 服务器端口被别的
/// 机器占了, 或免密失效)。UI 只读 `state`。
@MainActor
final class PhoneRelayTunnel: ObservableObject {

    enum State: Equatable {
        case idle
        case connecting
        case connected
        /// 持续失败, `String` 是最后一次 ssh 的 stderr 摘要。
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    let preset: PhoneRemote.RelayPreset
    /// 本地服务端口由控制器在 init 末尾注入 (避免初始化顺序问题)。
    var localPortProvider: @MainActor () -> Int = { PhoneRemote.defaultPort }
    private var process: Process?
    private var restartTask: Task<Void, Never>?
    private var stderrTail: String = ""
    private var consecutiveFastFailures = 0
    private var spawnTime: Date?
    private var wantRunning = false

    static let fastFailureThreshold = 3
    static let normalRestartDelay: TimeInterval = 3
    static let failedRestartDelay: TimeInterval = 15
    /// 进程存活超过该时长即视为隧道已建立 (ssh -N 成功后无输出)。
    static let connectedAfter: TimeInterval = 2

    init?(preset: PhoneRemote.RelayPreset?, localPortProvider: @escaping @MainActor () -> Int = { PhoneRemote.defaultPort }) {
        guard let preset else { return nil }
        self.preset = preset
        self.localPortProvider = localPortProvider
    }

    var publicLinkString: String {
        PhoneRemote.relayLinkURL(preset: preset, token: "")?.absoluteString ?? ""
    }

    func start() {
        guard !wantRunning else { return }
        wantRunning = true
        consecutiveFastFailures = 0
        spawn()
    }

    func stop() {
        wantRunning = false
        restartTask?.cancel()
        restartTask = nil
        process?.terminate()
        process = nil
        state = .idle
    }

    private func spawn() {
        guard wantRunning, process == nil else { return }
        state = consecutiveFastFailures >= Self.fastFailureThreshold ? .failed(stderrTail) : .connecting
        cleanupStaleTunnel()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = PhoneRemote.tunnelArguments(serverForwardPort: preset.serverForwardPort,
                                                  localPort: localPortProvider())
        // stderr 常驻管道, 记录最后几行用于诊断 (BatchMode 下失败原因都在这)。
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = Pipe()
        stderrTail = ""
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            let line = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self.appendStderr(line) }
        }
        p.terminationHandler = { [weak self] process in
            Task { @MainActor in self?.handleExit(status: process.terminationStatus) }
        }
        do {
            try p.run()
        } catch {
            stderrTail = "ssh 启动失败: \(error.localizedDescription)"
            consecutiveFastFailures += 1
            scheduleRestart(delay: Self.failedRestartDelay)
            return
        }
        process = p
        spawnTime = Date()
        // 存活超过 connectedAfter 即认为隧道已建立 (ExitOnForwardFailure 保证
        // 端口冲突会在启动早期退出)。
        let checkTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.connectedAfter * 1_000_000_000))
            guard let self, !Task.isCancelled, self.process === p else { return }
            if p.isRunning {
                self.state = .connected
                self.consecutiveFastFailures = 0
            }
        }
        _ = checkTask
    }

    private func appendStderr(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stderrTail = String(trimmed.suffix(300))
    }

    private func handleExit(status: Int32) {
        process = nil
        spawnTime = nil
        guard wantRunning else {
            state = .idle
            return
        }
        // 端口被本机残留隧道占用 (App 上次被强杀, ssh 子进程变孤儿):
        // spawn 前的清理已能接手端口, 快速重试且不累计为持续失败。
        if stderrTail.contains("remote port forwarding failed") {
            consecutiveFastFailures = 0
            scheduleRestart(delay: Self.normalRestartDelay)
            return
        }
        // 其他失败 (免密失效/断网) 计数, 连续过快失败则降频重连。
        consecutiveFastFailures += 1
        if consecutiveFastFailures >= Self.fastFailureThreshold {
            state = .failed(stderrTail.isEmpty ? "ssh 退出 (\(status))" : stderrTail)
            scheduleRestart(delay: Self.failedRestartDelay)
        } else {
            state = .connecting
            scheduleRestart(delay: Self.normalRestartDelay)
        }
    }

    /// 清理隧道残留: (1) 本机孤儿 ssh 进程; (2) 服务器上本机端口的僵尸
    /// 转发监听 (半开连接, sshd 未察觉客户端已死)。完成后下一次 bind 即可
    /// 成功。特征串/端口都唯一对应本机, 不会影响其它机器或用户的 ssh。
    private func cleanupStaleTunnel() {
        runTool("/usr/bin/pkill",
                ["-f", PhoneRemote.tunnelProcessPattern(
                    serverForwardPort: preset.serverForwardPort,
                    localPort: localPortProvider())])
        runTool("/usr/bin/ssh",
                PhoneRemote.remoteCleanupArguments(serverForwardPort: preset.serverForwardPort))
    }

    /// 同步执行一个清理工具, 忽略一切失败 (清理是尽力而为)。
    private func runTool(_ path: String, _ arguments: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = arguments
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            // 清理失败静默降级: 端口仍被占时走 "remote port forwarding
            // failed" 快速重试路径。
        }
    }

    private func scheduleRestart(delay: TimeInterval) {
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled, self.wantRunning else { return }
            self.spawn()
        }
    }
}
