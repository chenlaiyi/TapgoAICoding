import Foundation
import Darwin

/// A byte-stream transport to a `codex app-server`.
///
/// The transport is responsible for the OS-level plumbing:
///   - spawning the underlying process (local Process or remote
///     `ssh` subprocess)
///   - feeding the API key (only the remote transport needs it) as
///     the first line of stdin
///   - reading newline-delimited JSON frames from stdout
///   - writing newline-delimited JSON frames to stdin
///   - detecting EOF / process exit
///
/// Higher-level JSON-RPC correlation (id ↔ pending request,
/// dispatching notifications to the onEvent callback) lives in
/// `CodexHarnessClient` which wraps a `HarnessTransport`.
///
/// **Threading**: every method is main-actor isolated. The transport
/// is responsible for its own internal queues; it must not block the
/// main thread on long I/O.
@MainActor
public protocol HarnessTransport: AnyObject {
    /// True when the underlying process is alive and the JSON-RPC
    /// handshake can proceed.
    var isRunning: Bool { get }

    /// Invoked for every JSON-RPC **notification** (no `id`).
    /// JSON-RPC **responses** (with `id`) are NOT routed here —
    /// those are delivered to the awaiting `request(...)` caller.
    var onNotification: ((JSONValue) -> Void)? { get set }

    /// Invoked once when the underlying process exits or the
    /// transport otherwise loses its connection. The argument is
    /// the exit code (0 = normal, non-zero = abnormal, -1 if the
    /// process was never started).
    var onClose: ((Int32) -> Void)? { get set }

    /// Start the underlying process. Throws if the process can't be
    /// spawned or the initial setup fails.
    func start() throws

    /// Stop the underlying process. Safe to call multiple times.
    func stop()

    /// Write a single newline-delimited JSON frame to the
    /// transport's stdin. Throws if the process is gone.
    func send(frame: JSONValue) throws
}

public extension HarnessTransport {
    /// Terminate and asynchronously wait for the OS process to be gone. Both
    /// concrete transports escalate a stuck SIGTERM to SIGKILL after 2 seconds,
    /// so this cannot leave two app-server processes overlapping indefinitely.
    func stopAndWait() async {
        stop()
        while isRunning {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }
}

// MARK: - Local transport

/// Local `Process`-backed transport. Spawns `codex app-server
/// --listen stdio://` directly on the Mac. The API key is set as
/// `OPENAI_API_KEY` in the process env so the harness can read it
/// from its own environment.
public final class LocalHarnessTransport: HarnessTransport {
    public let harnessPath: String
    public let codexHome: URL
    public let apiKey: String

    public var onNotification: ((JSONValue) -> Void)?
    public var onClose: ((Int32) -> Void)?

    /// Test-only: collected frames for inspection by integration
    /// tests. The production path (CodexHarnessClient) uses
    /// `onNotification` directly.
    public private(set) var collectedFrames: [JSONValue] = []
    /// Test-only: pending response callbacks by request id.
    fileprivate var pendingResponses: [Int: (JSONValue) -> Void] = [:]

    private var process: Process?
    private var stdin: FileHandle?
    private let stdoutBuffer = LineBuffer()
    private var stderrBuffer = Data()

    public init(harnessPath: String, codexHome: URL, apiKey: String) {
        self.harnessPath = harnessPath
        self.codexHome = codexHome
        self.apiKey = apiKey
    }

    public func registerPending(id: Int, callback: @escaping (JSONValue) -> Void) {
        pendingResponses[id] = callback
    }
    nonisolated public func cancelPending(id: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.pendingResponses.removeValue(forKey: id)
        }
    }

    public var isRunning: Bool {
        process?.isRunning ?? false
    }

    public func start() throws {
        guard process == nil else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: harnessPath)
        proc.arguments = ["app-server", "--listen", "stdio://"]
        var env = ProcessInfo.processInfo.environment
        env["CODEX_HOME"] = codexHome.path
        env["OPENAI_API_KEY"] = apiKey
        env["TERM"] = "xterm-256color"
        if env["LANG"] == nil { env["LANG"] = "C.UTF-8" }
        proc.environment = env

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        proc.standardInput = inputPipe
        proc.standardOutput = outputPipe
        proc.standardError = errorPipe
        stdin = inputPipe.fileHandleForWriting

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                // EOF on stdout — the child process closed its write
                // end. Surface it as a transport close so the
                // supervisor can re-attach via the same path the
                // socket transport does, instead of waiting on
                // `proc.terminationHandler` (which is unreliable
                // once the process is already gone).
                handle.readabilityHandler = nil
                Task { @MainActor in self.handleClose(code: -1) }
                return
            }
            Task { @MainActor in self.consumeStdout(data) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                handle.readabilityHandler = nil
                Task { @MainActor in self.handleClose(code: -1) }
                return
            }
            Task { @MainActor in self.consumeStderr(data) }
        }
        proc.terminationHandler = { [weak self] p in
            let code = p.terminationStatus
            Task { @MainActor in self?.handleClose(code: code) }
        }

        do {
            try proc.run()
        } catch {
            stdin = nil
            throw error
        }
        process = proc
    }

    public func stop() {
        stdin = nil
        guard let proc = process, proc.isRunning else {
            process = nil
            return
        }
        proc.terminate()
        let pid = proc.processIdentifier
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard self?.process === proc, proc.isRunning else { return }
            Darwin.kill(pid, SIGKILL)
        }
    }

    public func send(frame: JSONValue) throws {
        guard let stdin else {
            throw HarnessTransportError.notRunning
        }
        var data = try JSONEncoder().encode(frame)
        data.append(0x0A)
        try stdin.write(contentsOf: data)
    }

    private func consumeStdout(_ chunk: Data) {
        stdoutBuffer.append(chunk)
        while let line = stdoutBuffer.popLine() {
            guard !line.isEmpty,
                  let bytes = String(line).data(using: .utf8),
                  let value = try? JSONDecoder().decode(JSONValue.self, from: bytes)
            else {
                // Not JSON — log for debugging the JSON-RPC path.
                print("[transport] non-JSON line: \(String(line).prefix(200))")
                continue
            }
            if value.objectValue == nil { continue }
            collectedFrames.append(value)
            if let id = value.objectValue?["id"]?.intOrBoolAsInt,
               let cb = pendingResponses.removeValue(forKey: id) {
                if let err = value.objectValue?["error"]?.objectValue {
                    let msg = err["message"]?.stringValue ?? "unknown"
                    print("[transport] rpc error id=\(id): \(msg)")
                    cb(.null)
                } else {
                    cb(value.objectValue?["result"] ?? .null)
                }
            } else {
                onNotification?(value)
            }
        }
    }

    private func consumeStderr(_ chunk: Data) {
        stderrBuffer.append(chunk)
        while let nlIdx = stderrBuffer.firstIndex(of: 0x0A) {
            let line = stderrBuffer.subdata(in: 0..<nlIdx)
            stderrBuffer.removeSubrange(0..<nlIdx + 1)
            if let s = String(data: line, encoding: .utf8),
               !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("[harness-stderr] \(s)")
            }
        }
    }

    private func handleClose(code: Int32) {
        process = nil
        stdin = nil
        onClose?(code)
    }
}

// MARK: - Weak reference box (used to safely bridge Thread bodies)

/// A weak reference box. `Thread` blocks can't capture
/// `weak self` in a Swift closure, so we box it.
private final class WeakBox<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

// MARK: - Line buffer (used by all transports)

/// Newline-delimited line buffer. Same semantics as the legacy
/// `LineBuffer` in the main target; kept here so the transport can
/// be unit-tested without pulling in main-target types.
public final class LineBuffer {
    private var data = Data()
    public init() {}
    public var isEmpty: Bool { data.isEmpty }
    public func append(_ chunk: Data) { data.append(chunk) }
    public func popLine() -> String? {
        guard let nl = data.firstIndex(of: 0x0A) else { return nil }
        let lineData = data.subdata(in: 0..<nl)
        data.removeSubrange(0..<nl + 1)
        return String(data: lineData, encoding: .utf8)
    }
    public func clear() { data.removeAll(keepingCapacity: true) }
}

// MARK: - Remote SSH transport

/// SSH-tunneled transport. Spawns an `ssh` subprocess that runs a
/// `bash` wrapper on the remote host. The wrapper:
///
///   1. reads the **first line of stdin** as the API key
///   2. `export OPENAI_API_KEY="$KEY"`
///   3. `exec env CODEX_HOME=... codex app-server --listen stdio://`
///
/// The API key is therefore delivered as SSH subprocess stdin
/// (lifetime == SSH subprocess lifetime), never written to the
/// remote disk, command line, or log files.
public final class RemoteSSHHarnessTransport: HarnessTransport {
    public let sshPath: String
    public let host: RemoteHost
    public let remoteCodexHome: String
    /// Code path on the remote host, e.g. "codex" or "/opt/homebrew/bin/codex".
    public let codexPathOnRemote: String
    public let apiKey: String

    public var onNotification: ((JSONValue) -> Void)?
    public var onClose: ((Int32) -> Void)?

    /// Set to true once the API key has been written to stdin. The
    /// remote wrapper reads exactly one line; we must write it as
    /// the first thing, before any JSON-RPC frame.
    public private(set) var keySent = false
    /// True when the remote wrapper's `tapgo:received=true key_len=…`
    /// line is observed on the merged stderr+stdout stream. The
    /// integration test asserts this so a hang on the read side
    /// can be distinguished from a real "the model didn't call
    /// any tool" silence.
    public private(set) var keyReceivedConfirmed = false

    /// Test-only: collected frames for inspection. The transport
    /// does not normally expose this — it's set up in `start()`
    /// so the integration test can verify the harness's final
    /// `aggregatedOutput` etc.
    public private(set) var collectedFrames: [JSONValue] = []
    /// Test-only: pending response callbacks by request id. The
    /// transport's read thread fires the callback when a response
    /// with a matching id is observed.
    fileprivate var pendingResponses: [Int: (JSONValue) -> Void] = [:]

    private var process: Process?
    private var stdin: FileHandle?
    private let stdoutBuffer = LineBuffer()
    private var stderrBuffer = Data()
    /// Dedicated read thread: we read the SSH subprocess's
    /// combined stderr+stdout on a background thread instead of
    /// relying on `readabilityHandler`. The latter can silently
    /// stop firing if the run loop isn't pumped (which we hit
    /// once inside a `withTaskGroup`-style helper).
    private var readThread: Foundation.Thread?

    public func registerPending(id: Int, callback: @escaping (JSONValue) -> Void) {
        pendingResponses[id] = callback
    }
    nonisolated public func cancelPending(id: Int) {
        // We need this to be safe to call from any thread (the
        // timeout task runs on a global executor). The transport
        // is a reference type; the dict mutation isn't strictly
        // thread-safe, but in practice the timeout and the response
        // race against a single id and Swift's reference semantics
        // give us enough safety for an integration test.
        let mirror = Mirror(reflecting: self)
        _ = mirror
        // Mutate via an unsafe escape hatch (only used by tests).
        // In production code we never call this from another thread.
        DispatchQueue.main.async { [weak self] in
            self?.pendingResponses.removeValue(forKey: id)
        }
    }

    public init(
        sshPath: String,
        host: RemoteHost,
        remoteCodexHome: String,
        codexPathOnRemote: String = "codex",
        apiKey: String
    ) {
        self.sshPath = sshPath
        self.host = host
        self.remoteCodexHome = remoteCodexHome
        self.codexPathOnRemote = codexPathOnRemote
        self.apiKey = apiKey
    }

    public var isRunning: Bool {
        process?.isRunning ?? false
    }

    public func start() throws {
        guard process == nil else { return }
        let wrapper = RemoteCodexHomeSync.remoteHarnessWrapper(
            remoteHome: remoteCodexHome,
            codexPathOnRemote: codexPathOnRemote
        )
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: sshPath)
        // The argv is FIXED: no key in the command line.
        // -T = no TTY, -o BatchMode=yes = no password prompt,
        // ConnectTimeout=8 = fail fast.
        // Then the remote command is the wrapper string verbatim.
        proc.arguments = [
            "-T",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "\(host.user)@\(host.host)",
            wrapper,
        ]
        var env = ProcessInfo.processInfo.environment
        // The Mac's own `ssh` runs in batch mode; force UTF-8 to
        // avoid locale issues when the JSON-RPC frames cross the
        // SSH transport.
        env["LC_ALL"] = "C.UTF-8"
        env["LANG"] = "C.UTF-8"
        proc.environment = env

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        // Merge stderr into stdout. codex writes its startup banner
        // to stderr; with -T on the remote side, that banner is
        // delivered over the SSH stderr channel. If we keep the
        // two streams separate, a banner that happens to NOT end
        // in '\n' (some codex versions) can leave the stdout
        // pipe blocked. Combining them is what the official
        // `codex app-server` test harness does.
        proc.standardInput = inputPipe
        proc.standardOutput = outputPipe
        proc.standardError = outputPipe
        stdin = inputPipe.fileHandleForWriting

        // Dedicated read thread. The Swift `readabilityHandler`
        // path depends on the main run loop being pumped; once
        // we drive the test from a `withTaskGroup` it can
        // silently stop firing. A background thread that does
        // blocking reads is bulletproof for a JSON-RPC stream
        // where the producer is on the network and may buffer.
        let readHandle = outputPipe.fileHandleForReading
        let weakSelf = WeakBox(self)
        // Use a detached POSIX-level read loop. We can't easily
        // use Foundation.Thread because of name collisions with
        // our TapgoCore.Thread model, and the closure-based init
        // doesn't expose `start()` reliably across Swift versions.
        let detached = DispatchQueue(label: "tapgo-remote-read", qos: .userInitiated)
        detached.async { [weak self] in
            while true {
                let chunk = readHandle.availableData
                if chunk.isEmpty { break }
                let payload = chunk
                let target = self ?? weakSelf.value
                DispatchQueue.main.async {
                    target?.consumeStdout(payload)
                }
            }
        }

        proc.terminationHandler = { [weak self] p in
            let code = p.terminationStatus
            DispatchQueue.main.async { [weak self] in
                self?.handleClose(code: code)
            }
        }

        do {
            try proc.run()
        } catch {
            stdin = nil
            throw error
        }
        process = proc

        // CRITICAL: the first write to stdin MUST be the API key
        // (followed by exactly one '\n'). The remote wrapper's
        // `IFS= read -r KEY` consumes exactly one line, then execs
        // the harness which inherits the rest of stdin.
        guard let stdin else { return }
        var firstLine = Data(apiKey.utf8)
        firstLine.append(0x0A)
        try stdin.write(contentsOf: firstLine)
        keySent = true
    }

    public func stop() {
        stdin = nil
        guard let proc = process, proc.isRunning else {
            process = nil
            return
        }
        proc.terminate()
        let pid = proc.processIdentifier
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard self?.process === proc, proc.isRunning else { return }
            Darwin.kill(pid, SIGKILL)
        }
    }

    public func send(frame: JSONValue) throws {
        guard let stdin else {
            throw HarnessTransportError.notRunning
        }
        // Sanity: if we somehow got here without writing the key
        // (e.g. start() was retried after a failure), bail out.
        guard keySent else {
            throw HarnessTransportError.keyNotDelivered
        }
        var data = try JSONEncoder().encode(frame)
        data.append(0x0A)
        try stdin.write(contentsOf: data)
    }

    private func consumeStdout(_ chunk: Data) {
        stdoutBuffer.append(chunk)
        while let line = stdoutBuffer.popLine() {
            if line.hasPrefix("tapgo:received=") {
                let v = String(line).replacingOccurrences(of: "tapgo:received=", with: "")
                if v.hasPrefix("true") {
                    keyReceivedConfirmed = true
                } else {
                    print("[transport] key-rejected: \(line)")
                }
                continue
            }
            // Log every line so the integration test can see the
            // wrapper's `env | grep …` output and codex's banner.
            if !line.isEmpty {
                print("[transport] line: \(line.prefix(300))")
            }
            guard !line.isEmpty,
                  let bytes = String(line).data(using: .utf8),
                  let value = try? JSONDecoder().decode(JSONValue.self, from: bytes)
            else { continue }
            if value.objectValue == nil { continue }
            collectedFrames.append(value)
            if let id = value.objectValue?["id"]?.intOrBoolAsInt,
               let cb = pendingResponses.removeValue(forKey: id) {
                if let err = value.objectValue?["error"]?.objectValue {
                    let msg = err["message"]?.stringValue ?? "unknown"
                    print("[transport] rpc error id=\(id): \(msg)")
                    cb(.null)
                } else {
                    cb(value.objectValue?["result"] ?? .null)
                }
            } else {
                onNotification?(value)
            }
        }
    }

    private func consumeStderr(_ chunk: Data) {
        stderrBuffer.append(chunk)
        while let nlIdx = stderrBuffer.firstIndex(of: 0x0A) {
            let line = stderrBuffer.subdata(in: 0..<nlIdx)
            stderrBuffer.removeSubrange(0..<nlIdx + 1)
            if let s = String(data: line, encoding: .utf8),
               !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Sanitize: never log the API key. (We never write
                // the key to stderr, but defense in depth.)
                let sanitized = s.replacingOccurrences(of: apiKey, with: "<API_KEY>")
                print("[remote-harness-stderr] \(sanitized)")
            }
        }
    }

    private func handleClose(code: Int32) {
        process = nil
        stdin = nil
        onClose?(code)
    }
}

public enum HarnessTransportError: LocalizedError {
    case notRunning
    case keyNotDelivered
    public var errorDescription: String? {
        switch self {
        case .notRunning: return "Harness 传输未运行"
        case .keyNotDelivered: return "API key 未投递到远端 harness"
        }
    }
}
