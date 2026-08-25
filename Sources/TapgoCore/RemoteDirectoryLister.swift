import Foundation

/// Reads the immediate sub-directories of a path on a remote host
/// over SSH. Used by the "add remote project" sheet to show a
/// Codex-style file browser.
///
/// Hard rules (mirrored from `RemoteCommandBuilder`):
///   1. SSH argv is built via `RemoteCommandBuilder.buildListDirArgv`,
///      which validates the path, host, and user before they ever
///      reach the shell.
///   2. The remote command is `cd <path> && ls -1Ap`; we only keep
///      lines that end in `/` (directories) and drop `.` / `..`.
///   3. If `ls` exits non-zero (path does not exist, permission
///      denied, or SSH itself fails) we surface a typed error to
///      the SwiftUI layer so the sheet can show a clear message
///      instead of dumping stderr into the chat.
public actor RemoteDirectoryLister {

    public struct Entry: Hashable, Identifiable, Sendable {
        public let id: String
        public init(name: String) { self.id = name }
    }

    public enum ListError: LocalizedError, Equatable {
        case sshNotFound
        case remoteNotDirectory(String)
        case permissionDenied(String)
        case sshFailed(String)
        case noOutput

        public var errorDescription: String? {
            switch self {
            case .sshNotFound:
                return "找不到 ssh 可执行文件"
            case .remoteNotDirectory(let path):
                return "远程路径不存在或不是目录:\(path)"
            case .permissionDenied(let detail):
                return "远程拒绝访问:\(detail)"
            case .sshFailed(let detail):
                return "SSH 失败:\(detail)"
            case .noOutput:
                return "远程目录为空或无响应"
            }
        }
    }

    public init() {}

    /// List immediate sub-directories of `path` on `host`. Returns
    /// the directory names (without trailing slash) sorted
    /// case-insensitively. Hidden directories are included so the
    /// user can land on a `.config` or `.ssh`-adjacent project.
    public func listDirectories(
        sshPath: String,
        host: RemoteHost,
        path: String
    ) async throws -> [Entry] {
        let argv = try RemoteCommandBuilder.buildListDirArgv(
            sshPath: sshPath, host: host, remotePath: path
        )
        let result = try await run(argv: argv)
        if result.exitCode != 0 {
            // Classify the failure using stderr (and stdout as
            // a fallback) so the UI can show a useful message.
            // We deliberately do NOT collapse stderr into stdout
            // for the success path; the upstream lister leaves
            // them separate so we can tell apart "remote bash
            // printed something to stderr but succeeded" from
            // "remote bash failed".
            let detail = (result.stderr.isEmpty
                          ? result.stdout : result.stderr)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = detail.lowercased()
            if lower.contains("permission denied")
                || lower.contains("operation not permitted") {
                throw ListError.permissionDenied(detail)
            }
            if lower.contains("no such file")
                || lower.contains("not found")
                || lower.contains("does not exist") {
                throw ListError.remoteNotDirectory(detail)
            }
            if lower.contains("not a directory") {
                throw ListError.remoteNotDirectory(detail)
            }
            if lower.contains("no output") || detail.isEmpty {
                throw ListError.noOutput
            }
            throw ListError.sshFailed(detail)
        }
        let names = result.stdout
            .components(separatedBy: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, trimmed.hasSuffix("/") else { return nil }
                let name = String(trimmed.dropLast())
                guard name != ".", name != ".." else { return nil }
                return name
            }
        if names.isEmpty {
            // `ls` succeeded (exit 0) but produced no directory
            // entries — treat that as a real answer, not an error,
            // so the sheet can show "empty directory".
            return []
        }
        return names
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map(Entry.init(name:))
    }

    /// Internal SSH result. The remote `ls -1Ap` writes its output
    /// to stdout; stderr is captured separately so we can inspect
    /// it without it contaminating the directory list.
    private struct SshRunResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    private func run(argv: [String]) async throws -> SshRunResult {
        guard !argv.isEmpty else { throw ListError.sshFailed("empty argv") }
        return try await withCheckedThrowingContinuation { cont in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: argv[0])
            process.arguments = Array(argv.dropFirst())
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            // Don't inherit stdin — that would let a future caller
            // accidentally swallow the key-injection path used by
            // the harness. The directory lister has no use for it.
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                cont.resume(throwing: ListError.sshFailed(error.localizedDescription))
                return
            }
            // Read stdout/stderr concurrently to avoid deadlocking
            // on a chatty SSH server that fills the 64KB pipe
            // buffer before we attach the second reader.
            let outQ = DispatchQueue(label: "tapgo.ls.stdout")
            let errQ = DispatchQueue(label: "tapgo.ls.stderr")
            var outData = Data()
            var errData = Data()
            let group = DispatchGroup()
            group.enter()
            outQ.async {
                outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            group.enter()
            errQ.async {
                errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            process.waitUntilExit()
            group.wait()
            cont.resume(returning: SshRunResult(
                stdout: String(data: outData, encoding: .utf8) ?? "",
                stderr: String(data: errData, encoding: .utf8) ?? "",
                exitCode: process.terminationStatus
            ))
        }
    }
}
