import Foundation

/// Safe-by-construction remote command builder.
///
/// Hard rules:
///   1. The remote command is **always** `cd <remotePath> && <command>`.
///   2. `remotePath` is validated against an allow-list regex before
///      it is used; this stops a malicious prompt or a stale project
///      record from chaining `cd /etc && rm -rf` or similar.
///   3. The `command` portion is *not* shell-escaped — it is passed
///      to `bash -lc '<command>'` exactly as the model produced it,
///      but only after we wrap it in a single-quoted argument that
///      escapes embedded single quotes. That keeps the inner command
///      syntactically intact while preventing injection from `&&`/`;`/
///      / backticks at the *outer* shell level.
///   4. We never interpolate the SSH target / port / user / identity
///      into a shell string. They are always passed as argv
///      entries, so the user's `~/.ssh/config` and keychain
///      continue to work normally.
public enum RemoteCommandBuilder {
    public static let maxPathLength = 4096
    public static let maxCommandLength = 64_000
    /// Conservative allow-list: only printable ASCII, no shell
    /// metacharacters that could escape the outer single quotes,
    /// no NUL, no CR/LF.
    ///
    /// v0.5.100: `_` now allowed in host / user / alias. RFC 1123
    /// permits underscores in hostnames and many operators ship
    /// boxes / accounts with them (e.g. `mac-mini_jk`,
    /// `john_doe`). Previously this regex silently rejected every
    /// such hostname, which made the "Add Remote Host" sheet
    /// impossible to submit on the most common real-world
    /// setups.
    static let safePathRegex = try! NSRegularExpression(
        pattern: "^[A-Za-z0-9_./~+@%:-]+$"
    )
    static let safeAliasRegex = try! NSRegularExpression(
        pattern: "^[A-Za-z0-9_.\\-]+$"
    )
    static let safeHostRegex = try! NSRegularExpression(
        pattern: "^[A-Za-z0-9._:_-]+$"
    )
    static let safeUserRegex = try! NSRegularExpression(
        pattern: "^[A-Za-z0-9._-]+$"
    )

    public static func validatePath(_ p: String) -> String? {
        let trimmed = p.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maxPathLength,
              !trimmed.contains("\0"),
              !trimmed.contains("\n"),
              !trimmed.contains("\r") else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard safePathRegex.firstMatch(in: trimmed, options: [], range: range) != nil else { return nil }
        return trimmed
    }
    public static func validateHost(_ h: String) -> String? {
        let trimmed = h.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 255,
              safeHostRegex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil else { return nil }
        return trimmed
    }
    public static func validateUser(_ u: String) -> String? {
        let trimmed = u.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 64,
              safeUserRegex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil else { return nil }
        return trimmed
    }
    /// Alias is shown in the UI / used as a directory mirror key.
    /// v0.5.100: surfaced as a public validator so the Add Host
    /// sheet can give the user a precise error message instead
    /// of a generic "主机不合法".
    public static func validateAlias(_ a: String) -> String? {
        let trimmed = a.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 64,
              safeAliasRegex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil else { return nil }
        return trimmed
    }
    /// A model command is *more* permissive than a path/host/user
    /// because it has to express real shell pipelines. The only
    /// hard rejects are NUL, CR, and LF (which would split the
    /// outer single-quoted argument), and length.
    public static func validateCommand(_ c: String) -> String? {
        let trimmed = c.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= maxCommandLength,
              !trimmed.contains("\0"),
              !trimmed.contains("\n"),
              !trimmed.contains("\r") else { return nil }
        return trimmed
    }

    public enum BuildError: LocalizedError, Equatable {
        case invalidPath
        case invalidHost
        case invalidUser
        case invalidCommand
        case commandTooLong
        case sshNotFound
        public var errorDescription: String? {
            switch self {
            case .invalidPath: return "远程路径不合法"
            case .invalidHost: return "远程主机不合法"
            case .invalidUser: return "远程用户不合法"
            case .invalidCommand: return "命令不合法"
            case .commandTooLong: return "命令过长"
            case .sshNotFound: return "找不到 ssh"
            }
        }
    }

    /// Build an argv that runs `command` inside `remotePath` over SSH.
    /// The `command` argument is the raw model command — we wrap it
    /// in single quotes so the remote bash can execute it verbatim.
    /// Even a hostile model cannot escape the outer single quotes
    /// because we escape embedded single quotes as `'\''`.
    public static func buildSshArgv(
        sshPath: String,
        host: RemoteHost,
        remotePath: String,
        modelCommand: String
    ) throws -> [String] {
        guard let safeRemote = validatePath(remotePath) else { throw BuildError.invalidPath }
        guard let safeHost = validateHost(host.host) else { throw BuildError.invalidHost }
        guard let safeUser = validateUser(host.user) else { throw BuildError.invalidUser }
        guard let safeCommand = validateCommand(modelCommand) else {
            if modelCommand.count > maxCommandLength {
                throw BuildError.commandTooLong
            }
            throw BuildError.invalidCommand
        }
        guard FileManager.default.isExecutableFile(atPath: sshPath) else { throw BuildError.sshNotFound }

        // The outer shell on the remote host gets the joined string:
        //   cd <safeRemote> && bash -lc '<escaped>'
        // `<escaped>` collapses newlines so the outer parser doesn't
        // get confused (a hostile model emitting `rm\n-rf` would
        // otherwise become two separate outer lines). Note that
        // validateCommand has already rejected embedded CR/LF, so
        // this collapsing is just a belt-and-suspenders cleanup.
        let inner = safeCommand
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: " ")
        let escaped = inner
            .replacingOccurrences(of: "'", with: "'\\''")
        let remoteCommand = "cd \(safeRemote) && bash -lc '\(escaped)'"

        var args: [String] = [sshPath]
        if host.port != 22 {
            args += ["-p", String(host.port)]
        }
        if let id = host.identityHint, !id.isEmpty, id != "default" {
            // identity path: only allow typical ssh key filenames
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            if FileManager.default.fileExists(atPath: trimmed) {
                args += ["-i", trimmed]
            }
        }
        args += [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "-o", "StrictHostKeyChecking=accept-new",
            "\(safeUser)@\(safeHost)",
            remoteCommand,
        ]
        return args
    }

    /// Build argv for the "test connection" probe — pwd + uname.
    public static func buildProbeArgv(
        sshPath: String,
        host: RemoteHost
    ) throws -> [String] {
        guard let safeHost = validateHost(host.host) else { throw BuildError.invalidHost }
        guard let safeUser = validateUser(host.user) else { throw BuildError.invalidUser }
        guard FileManager.default.isExecutableFile(atPath: sshPath) else { throw BuildError.sshNotFound }

        var args: [String] = [sshPath]
        if host.port != 22 {
            args += ["-p", String(host.port)]
        }
        if let id = host.identityHint, !id.isEmpty, id != "default" {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            if FileManager.default.fileExists(atPath: trimmed) {
                args += ["-i", trimmed]
            }
        }
        args += [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "-o", "StrictHostKeyChecking=accept-new",
            "\(safeUser)@\(safeHost)",
            "pwd; uname -a",
        ]
        return args
    }

    /// Build argv for "list the immediate sub-directories of `remotePath`".
    ///
    /// The remote command is `cd <remotePath> && ls -1Ap`. `ls -p`
    /// appends `/` to directory names, which is the only signal we
    /// need to filter out regular files in Swift. We deliberately
    /// do NOT pass the path to `ls` as a positional argument because
    /// a host that exposes a hostile `ls` wrapper could still
    /// interpret options inside it; instead we `cd` first and then
    /// run `ls` with no argument so it always means "list current
    /// directory".
    ///
    /// We do NOT append `2>/dev/null` to the cd; the lister
    /// inspects stderr to classify failures (e.g. "no such file"
    /// vs "permission denied" vs "not a directory"). The Swift
    /// process already captures stderr on a separate pipe so a
    /// noisy `cd:` line never appears in the user's chat.
    ///
    /// `-A` (capital) so hidden directories like `.config` are
    /// visible — useful for landing on a config repo. `.` and
    /// `..` are always filtered client-side.
    public static func buildListDirArgv(
        sshPath: String,
        host: RemoteHost,
        remotePath: String
    ) throws -> [String] {
        guard let safeRemote = validatePath(remotePath) else { throw BuildError.invalidPath }
        guard let safeHost = validateHost(host.host) else { throw BuildError.invalidHost }
        guard let safeUser = validateUser(host.user) else { throw BuildError.invalidUser }
        guard FileManager.default.isExecutableFile(atPath: sshPath) else { throw BuildError.sshNotFound }

        let remoteCommand = "cd \(safeRemote) && ls -1Ap"

        var args: [String] = [sshPath]
        if host.port != 22 {
            args += ["-p", String(host.port)]
        }
        if let id = host.identityHint, !id.isEmpty, id != "default" {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            if FileManager.default.fileExists(atPath: trimmed) {
                args += ["-i", trimmed]
            }
        }
        args += [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "-o", "StrictHostKeyChecking=accept-new",
            "\(safeUser)@\(safeHost)",
            remoteCommand,
        ]
        return args
    }
}
