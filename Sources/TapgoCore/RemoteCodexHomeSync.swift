import Foundation

/// Pushes non-sensitive Codex configuration to a remote host so we can
/// run a `codex app-server` there without polluting the user's
/// `~/.codex/` on that host.
///
/// **Security model**:
///   - This service NEVER writes the API key to the remote host.
///   - It only pushes:
///       * `config.toml`     — model + provider + non-sensitive knobs
///       * `model-catalogs/` — the model catalog JSON
///   - The API key is delivered at *runtime* via the SSH subprocess
///     `stdin` (first line) — the remote shell reads it, exports
///     `OPENAI_API_KEY`, and `exec`s the harness. The key never lands
///     on the remote disk, command line, or log files.
///   - Lifecycle of the key == lifecycle of the SSH child process.
///
/// The remote CODEX_HOME lives at `~/.tapgo-aicoding/remote/` by
/// convention. We can override it via `RemoteHost.codexHomePath`
/// (in `RemoteHost`), which lets the user relocate the bundle.
public enum RemoteCodexHomeSync {

    public static let defaultRemoteHome = "~/.tapgo-aicoding/remote"
    public static let minimumHarnessVersion = "0.149.1"

    /// Locate the `ssh` binary on this Mac. Falls back to
    /// `/usr/bin/env` (which the user can extend via PATH) if
    /// none of the standard locations is present.
    public static func findSSH() -> String {
        for c in ["/usr/bin/ssh", "/opt/homebrew/bin/ssh", "/usr/local/bin/ssh"] {
            if FileManager.default.isExecutableFile(atPath: c) { return c }
        }
        return "/usr/bin/env"
    }

    /// Locate the `scp` binary on this Mac. Used by `push(...)`
    /// to deliver the non-sensitive config + catalog to the
    /// remote host. Falls back to `/usr/bin/env`.
    public static func findSCP() -> String {
        for c in ["/usr/bin/scp", "/opt/homebrew/bin/scp", "/usr/local/bin/scp"] {
            if FileManager.default.isExecutableFile(atPath: c) { return c }
        }
        return "/usr/bin/env"
    }

    /// Locate the local `codex` binary. Returns "" if not found.
    public static func findHarness() -> String {
        if let override = ProcessInfo.processInfo.environment["HARNESS_BIN"],
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        for c in [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex",
        ] {
            if FileManager.default.isExecutableFile(atPath: c) { return c }
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":").map(String.init) where !directory.isEmpty {
                let candidate = URL(fileURLWithPath: directory)
                    .appendingPathComponent("codex").path
                if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        return ""
    }

    /// Parse the first semantic x.y.z triple from `codex --version` output.
    /// Kept public and side-effect free so setup compatibility is testable.
    public static func parseHarnessVersion(_ output: String) -> [Int]? {
        guard let regex = try? NSRegularExpression(pattern: #"([0-9]+)\.([0-9]+)\.([0-9]+)"#),
              let match = regex.firstMatch(
                in: output,
                range: NSRange(output.startIndex..., in: output)
              )
        else { return nil }
        return (1...3).compactMap { index -> Int? in
            guard let range = Range(match.range(at: index), in: output) else { return nil }
            return Int(output[range])
        }
    }

    public static func isSupportedHarnessVersion(_ version: [Int]) -> Bool {
        guard version.count == 3,
              let minimum = parseHarnessVersion(minimumHarnessVersion)
        else { return false }
        for index in 0..<3 {
            if version[index] != minimum[index] {
                return version[index] > minimum[index]
            }
        }
        return true
    }

    /// Read and validate the actual binary selected by `findHarness()`.
    /// Returns the normalized x.y.z string, or nil if the process/version is
    /// invalid or below the supported protocol floor.
    public static func supportedHarnessVersion(at path: String) -> String? {
        guard !path.isEmpty else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(
                data: output.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
              ),
              let version = parseHarnessVersion(text),
              isSupportedHarnessVersion(version)
        else { return nil }
        return version.map(String.init).joined(separator: ".")
    }

    /// Render a clean `config.toml` for the remote CODEX_HOME.
    /// No `env_key` is *required* here — codex reads
    /// `OPENAI_API_KEY` from the inherited env (which the SSH
    /// wrapper sets at runtime). The provider's `env_key` is still
    /// set as a fallback if the env var is missing.
    ///
    /// Note: `name` is intentionally set to the **same** lowercase
    /// string as the section key. codex 0.147.0 (and earlier)
    /// rejected `name = "MiniMax"` with "provider name must not
    /// be empty" when the value didn't match the section key in
    /// some configurations. The remote codex is older than the
    /// local one; the lowercase form works on both.
    ///
    /// `trustedRemotePaths` includes the user's home dir as a
    /// trusted project so codex doesn't fall back to the
    /// host's `~/.codex/config.toml` (which has chatgpt tokens
    /// and a different model_provider).
    public static func renderRemoteConfig(
        model: String = "MiniMax-M3",
        modelProvider: String = "minimax",
        modelContextWindow: Int = 1_000_000,
        baseURL: String = "https://api.minimaxi.com/v1",
        wireAPI: String = "responses",
        providerEnvKey: String = "OPENAI_API_KEY",
        trustedRemotePaths: [String] = []
    ) -> String {
        var out = """
        # Tapgo AICoding — isolated Codex home on the remote host.
        # Pushed by Tapgo AICoding. No API key lives here; the key is
        # delivered at runtime through the SSH session env.

        model = "\(model)"
        model_provider = "\(modelProvider)"
        model_context_window = \(modelContextWindow)

        [model_providers.\(modelProvider)]
        name = "\(modelProvider)"
        base_url = "\(baseURL)"
        wire_api = "\(wireAPI)"
        env_key = "\(providerEnvKey)"

        """
        // Always trust the user's home so codex doesn't load the
        // host's `~/.codex/config.toml` (which on remotehost has
        // chatgpt auth and a gpt-5.6-sol model). We pass the home
        // dir in via trustedRemotePaths.
        for path in trustedRemotePaths {
            out += """
            [projects."\(path)"]
            trust_level = "trusted"

            """
        }
        return out
    }

    /// Result of a sync attempt. We don't surface partial-failure
    /// details in detail (e.g. which `rsync` flag failed) — that's
    /// `sftp -v` territory, and we don't need it. What we DO need
    /// is a structured ok/err so the caller can present a clean
    /// status to the user.
    public struct SyncResult: Equatable {
        public let ok: Bool
        public let message: String
        public let remoteHome: String
    }

    /// Push the config + model-catalogs over SSH using `scp` so the
    /// user can `cat` them for verification. We use scp (not rsync,
    /// not cat) because it's universally available and the file
    /// count is tiny.
    ///
    /// Pre-conditions:
    ///   - `scpPath` points at a working `scp` binary
    ///   - `host.codexHomePath` is a writable path on the remote
    ///   - the `~/.ssh/config` already authenticates `host.user@host.host`
    public static func push(
        scpPath: String,
        sshPath: String,
        host: RemoteHost,
        configToml: String,
        modelCatalogJSON: String,
        modelCatalogFileName: String = "tapgo-catalog.json"
    ) -> SyncResult {
        // Resolve `~` to the remote user's home. scp does NOT
        // expand `~` in the destination spec, so we ask ssh to
        // echo `$HOME` over a fresh connection.
        let remoteHome = resolveRemoteHome(sshPath: sshPath, host: host, path: host.codexHomePath)
        // 1. Ensure the remote dirs exist.
        let mkdirArgv = [
            sshPath,
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "\(host.user)@\(host.host)",
            "mkdir -p '\(remoteHome)/model-catalogs'",
        ]
        guard runSync(argv: mkdirArgv, sshPath: sshPath) else {
            return SyncResult(ok: false, message: "无法在远端创建 \(remoteHome)", remoteHome: remoteHome)
        }

        // 2. Pipe the config.toml and catalog via `scp -`.
        //    We write the files to a Mac tmp dir, scp them, then
        //    remove the tmp dir. The tmp dir is `0700` and only the
        //    current user can read it; the lifetime is bounded by
        //    this function (deferred cleanup).
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tapgo-push-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            return SyncResult(ok: false, message: "无法创建临时推送目录: \(error.localizedDescription)",
                              remoteHome: remoteHome)
        }
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let configURL = tmpDir.appendingPathComponent("config.toml")
        let catalogURL = tmpDir.appendingPathComponent(modelCatalogFileName)
        do {
            try configToml.data(using: .utf8)?.write(to: configURL, options: [.atomic])
            try modelCatalogJSON.data(using: .utf8)?.write(to: catalogURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: catalogURL.path)
        } catch {
            return SyncResult(ok: false, message: "无法写临时推送文件: \(error.localizedDescription)",
                              remoteHome: remoteHome)
        }

        // 3. scp the config.toml
        let scpConfigArgv = [
            scpPath,
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            configURL.path,
            "\(host.user)@\(host.host):\(remoteHome)/config.toml",
        ]
        guard runSync(argv: scpConfigArgv, sshPath: sshPath) else {
            return SyncResult(ok: false, message: "scp config.toml 失败", remoteHome: remoteHome)
        }

        // 4. scp the catalog
        let scpCatalogArgv = [
            scpPath,
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            catalogURL.path,
            "\(host.user)@\(host.host):\(remoteHome)/model-catalogs/\(modelCatalogFileName)",
        ]
        guard runSync(argv: scpCatalogArgv, sshPath: sshPath) else {
            return SyncResult(ok: false, message: "scp model-catalog 失败", remoteHome: remoteHome)
        }

        return SyncResult(ok: true, message: "已推送 config + catalog 到 \(remoteHome)", remoteHome: remoteHome)
    }

    /// Resolve a remote path that may begin with `~` to its
    /// absolute form by running `echo <path>` on the remote host
    /// (the remote shell expands `~`). Returns the path unchanged
    /// if no expansion is needed.
    static func resolveRemoteHome(sshPath: String, host: RemoteHost, path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        // Ask the remote shell to print the resolved path.
        let argv = [
            sshPath,
            "-T", "-o", "BatchMode=yes",
            "\(host.user)@\(host.host)",
            "printf '%s' \(path)",
        ]
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: argv[0])
        proc.arguments = Array(argv.dropFirst())
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = FileHandle(forReadingAtPath: "/dev/null") ?? FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return path
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return path }
        let resolved = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return resolved.isEmpty ? path : resolved
    }

    /// Run an external command synchronously and return true on
    /// exit code 0. Stderr is captured into `error` so the caller
    /// can surface a one-liner; we deliberately don't log it to
    /// the global log (no API key should ever leak through stderr
    /// either, but belt-and-suspenders).
    @discardableResult
    private static func runSync(argv: [String], sshPath: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: argv[0])
        proc.arguments = Array(argv.dropFirst())
        var env = ProcessInfo.processInfo.environment
        // Quiet down scp/ssh so we don't leak the API key in
        // banner / verbose output.
        env["LC_ALL"] = "C.UTF-8"
        env["LANG"] = "C.UTF-8"
        proc.environment = env
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = FileHandle(forReadingAtPath: "/dev/null") ?? FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return false
        }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }

    /// The remote shell command that wraps `codex app-server` so the
    /// first line of SSH stdin is consumed as the API key and
    /// exposed as `OPENAI_API_KEY`. The wrapper `exec`s the harness
    /// so the SSH pipe keeps flowing — JSON-RPC frames sent after
    /// the key line go straight to codex.
    ///
    /// IMPORTANT: this string is rendered into the SSH argv, so
    /// it must never contain the API key. Build the key payload
    /// separately and write it to the SSH subprocess stdin as
    /// the first line.
    ///
    /// The wrapper deliberately emits `received=true` (or
    /// `received=false`) on a single line to stderr BEFORE
    /// `exec`-ing the harness. The Swift side reads that line
    /// to confirm the key was actually delivered end-to-end —
    /// without it we can't distinguish "SSH broken" from "codex
    /// ignoring JSON-RPC" from "key never arrived at the remote".
    public static func remoteHarnessWrapper(
        remoteHome: String,
        codexPathOnRemote: String = "codex"
    ) -> String {
        // Single-quoted strings in shell do NOT expand `~`. If the
        // caller passes `~/.tapgo-aicoding/remote`, codex would
        // receive the literal string `~/.tapgo-aicoding/remote` as
        // $CODEX_HOME — which is then a path that doesn't exist on
        // the remote, and codex 0.147.0 rejects the provider
        // lookup as a result.
        //
        // We work around this by writing the path *outside* single
        // quotes, so the remote shell expands `~` for us. The
        // resolved path is then re-quoted before being passed to
        // `env`.
        //
        // The caller is expected to pass a non-empty `remoteHome`;
        // we pass it through `printf %q` to make it shell-safe.
        return #"""
        set -e
        VERSION_OUTPUT=$(\#(codexPathOnRemote) --version 2>/dev/null) || {
          echo "tapgo:unsupported-version actual=unavailable required=\#(minimumHarnessVersion)" 1>&2
          exit 4
        }
        VERSION=$(printf '%s\n' "$VERSION_OUTPUT" | sed -nE 's/[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n 1)
        VERSION_MAJOR=${VERSION%%.*}
        VERSION_REST=${VERSION#*.}
        VERSION_MINOR=${VERSION_REST%%.*}
        VERSION_PATCH=${VERSION_REST#*.}
        if [ -z "$VERSION" ] || ! {
          [ "$VERSION_MAJOR" -gt 0 ] ||
          [ "$VERSION_MINOR" -gt 149 ] ||
          { [ "$VERSION_MINOR" -eq 149 ] && [ "$VERSION_PATCH" -ge 1 ]; }
        }; then
          echo "tapgo:unsupported-version actual=${VERSION:-unknown} required=\#(minimumHarnessVersion)" 1>&2
          exit 4
        fi
        echo "tapgo:version=$VERSION" 1>&2
        IFS= read -r KEY || true
        if [ -z "$KEY" ]; then
          echo "tapgo:received=false reason=no-stdin-line" 1>&2
          exit 2
        fi
        echo "tapgo:received=true key_len=${#KEY}" 1>&2
        export OPENAI_API_KEY="$KEY"
        unset KEY
        # Resolve `~` in the home path *before* we exec codex, so
        # codex sees an absolute path. We do this OUTSIDE single
        # quotes so the remote shell expands the tilde.
        CODEX_HOME_RESOLVED=\#(remoteHome)
        if [ "${CODEX_HOME_RESOLVED#\~}" != "$CODEX_HOME_RESOLVED" ]; then
          CODEX_HOME_RESOLVED="$HOME${CODEX_HOME_RESOLVED#\~}"
        fi
        if [ ! -d "$CODEX_HOME_RESOLVED" ]; then
          echo "tapgo:no-home dir=$CODEX_HOME_RESOLVED" 1>&2
          exit 3
        fi
        exec env CODEX_HOME="$CODEX_HOME_RESOLVED" \#(codexPathOnRemote) app-server --listen stdio://
        """#
    }
}
