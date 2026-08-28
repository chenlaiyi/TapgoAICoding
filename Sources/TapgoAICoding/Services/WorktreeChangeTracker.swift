import Foundation

/// Captures the dirty paths that existed before a turn, then reports only
/// paths introduced by that turn. This keeps the progress chip honest in a
/// shared dirty worktree and supplies stats when Harness has no apply_patch
/// tool (and therefore emits no turn/diff/updated snapshot).
struct WorktreeChangeBaseline: Sendable {
    let repositoryRoot: URL
    let ignoredPaths: Set<String>
}

struct WorktreeChangeStats: Equatable, Sendable {
    let files: Int
    let additions: Int
    let deletions: Int

    var rendered: String {
        "files=\(files)\nadditions=\(additions)\ndeletions=\(deletions)"
    }
}

enum WorktreeChangeTracker {
    static func captureBaseline(cwd: URL) -> WorktreeChangeBaseline? {
        guard let rootData = runGit(["rev-parse", "--show-toplevel"], cwd: cwd),
              let rootPath = String(data: rootData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !rootPath.isEmpty else { return nil }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        return WorktreeChangeBaseline(
            repositoryRoot: root,
            ignoredPaths: changedPaths(cwd: root)
        )
    }

    static func collect(since baseline: WorktreeChangeBaseline) -> WorktreeChangeStats? {
        let root = baseline.repositoryRoot
        guard let numstatData = runGit(["diff", "--numstat", "HEAD", "--"], cwd: root),
              let untrackedData = runGit(
                ["ls-files", "--others", "--exclude-standard", "-z"],
                cwd: root
              ) else { return nil }

        var paths: Set<String> = []
        var additions = 0
        var deletions = 0
        let numstat = String(decoding: numstatData, as: UTF8.self)
        for line in numstat.split(whereSeparator: \.isNewline) {
            let columns = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard columns.count == 3 else { continue }
            let path = String(columns[2])
            guard !baseline.ignoredPaths.contains(path) else { continue }
            paths.insert(path)
            additions += Int(columns[0]) ?? 0
            deletions += Int(columns[1]) ?? 0
        }

        for path in nulSeparatedPaths(untrackedData)
            where !baseline.ignoredPaths.contains(path) {
            paths.insert(path)
            let url = root.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
            let newlineCount = data.reduce(into: 0) { count, byte in
                if byte == 0x0A { count += 1 }
            }
            additions += newlineCount + (data.last == 0x0A ? 0 : 1)
        }

        return WorktreeChangeStats(
            files: paths.count,
            additions: additions,
            deletions: deletions
        )
    }

    private static func changedPaths(cwd: URL) -> Set<String> {
        var result: Set<String> = []
        if let data = runGit(["diff", "--name-only", "-z", "HEAD", "--"], cwd: cwd) {
            result.formUnion(nulSeparatedPaths(data))
        }
        if let data = runGit(["ls-files", "--others", "--exclude-standard", "-z"], cwd: cwd) {
            result.formUnion(nulSeparatedPaths(data))
        }
        return result
    }

    private static func nulSeparatedPaths(_ data: Data) -> [String] {
        String(decoding: data, as: UTF8.self)
            .split(separator: "\0")
            .map(String.init)
    }

    private static func runGit(_ arguments: [String], cwd: URL) -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return output.fileHandleForReading.readDataToEndOfFile()
        } catch {
            return nil
        }
    }
}
