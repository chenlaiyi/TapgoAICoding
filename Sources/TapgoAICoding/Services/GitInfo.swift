import Foundation

struct GitChangeSummary: Equatable, Sendable {
    let files: Int
    let additions: Int
    let deletions: Int
}

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

    /// Current worktree line statistics for the adaptive environment card.
    /// Includes tracked changes and untracked text files, matching the green
    /// `+` / red `-` language used by Codex's environment summary.
    static func changeSummary(at path: String) -> GitChangeSummary? {
        guard let trackedData = runGitData(path, ["diff", "--numstat", "HEAD", "--"]),
              let untrackedData = runGitData(path, ["ls-files", "--others", "--exclude-standard", "-z"])
        else { return nil }

        var paths: Set<String> = []
        var additions = 0
        var deletions = 0
        let tracked = String(decoding: trackedData, as: UTF8.self)
        for line in tracked.split(whereSeparator: \.isNewline) {
            let columns = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard columns.count == 3 else { continue }
            paths.insert(String(columns[2]))
            additions += Int(columns[0]) ?? 0
            deletions += Int(columns[1]) ?? 0
        }

        let untrackedPaths = String(decoding: untrackedData, as: UTF8.self)
            .split(separator: "\0")
            .map(String.init)
        for relativePath in untrackedPaths {
            paths.insert(relativePath)
            let url = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent(relativePath)
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
            let newlineCount = data.reduce(into: 0) { count, byte in
                if byte == 0x0A { count += 1 }
            }
            additions += newlineCount + (data.last == 0x0A ? 0 : 1)
        }

        return GitChangeSummary(files: paths.count, additions: additions, deletions: deletions)
    }

    /// Run `git -C <path> <args>`, returning trimmed stdout on success (exit
    /// 0), else nil.
    private static func runGit(_ path: String, _ args: [String]) -> String? {
        guard let data = runGitData(path, args) else { return nil }
        let s = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }

    private static func runGitData(_ path: String, _ args: [String]) -> Data? {
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
            return out.fileHandleForReading.readDataToEndOfFile()
        } catch {
            return nil
        }
    }
}
