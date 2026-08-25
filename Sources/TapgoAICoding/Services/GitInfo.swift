import Foundation

/// Read-only git helpers for surfacing the project's branch in the
/// environment panel. Runs the real `git` binary detached from the UI; the
/// caller decides when to invoke it (so it never blocks a render).
enum GitInfo {
    /// Current branch name for a working tree, or nil when the path isn't a
    /// git repo or `git` isn't available.
    static func branch(at path: String) -> String? {
        runGit(path, ["rev-parse", "--abbrev-ref", "HEAD"])
    }

    /// Number of changed files (modified / added / deleted / untracked), or
    /// nil when the path isn't a git repo. Mirrors Codex's "变更" count.
    static func changesCount(at path: String) -> Int? {
        guard let body = runGit(path, ["status", "--porcelain"]) else { return nil }
        let count = body.split(whereSeparator: \.isNewline).count
        return count
    }

    /// `remote.origin.url`, or nil when the repo has no origin.
    static func remoteURL(at path: String) -> String? {
        runGit(path, ["config", "--get", "remote.origin.url"])
    }

    /// Run `git -C <path> <args>`, returning trimmed stdout on success (exit
    /// 0), else nil.
    private static func runGit(_ path: String, _ args: [String]) -> String? {
        guard !path.isEmpty else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", path] + args
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let s = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (s?.isEmpty == false) ? s : nil
        } catch {
            return nil
        }
    }
}

