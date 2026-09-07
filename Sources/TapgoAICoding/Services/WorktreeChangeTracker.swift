import Foundation

/// Captures the dirty paths that existed before a turn, then reports only
/// paths introduced by that turn. This keeps the progress chip honest in a
/// shared dirty worktree and supplies stats when Harness has no apply_patch
/// tool (and therefore emits no turn/diff/updated snapshot).
struct WorktreeChangeBaseline: Sendable {
    let repositoryRoot: URL
    let ignoredPaths: Set<String>
}

struct WorktreeFileStat: Equatable, Sendable {
    let path: String
    let additions: Int
    let deletions: Int
}

struct WorktreeChangeStats: Equatable, Sendable {
    let files: Int
    let additions: Int
    let deletions: Int
    /// 本 turn 触及的文件明细（相对仓库根）。git 兜底生成 FileChange 卡用。
    let perFile: [WorktreeFileStat]

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

        var perFile: [WorktreeFileStat] = []
        var additions = 0
        var deletions = 0
        let numstat = String(decoding: numstatData, as: UTF8.self)
        for line in numstat.split(whereSeparator: \.isNewline) {
            let columns = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard columns.count == 3 else { continue }
            let path = String(columns[2])
            guard !baseline.ignoredPaths.contains(path) else { continue }
            let added = Int(columns[0]) ?? 0
            let removed = Int(columns[1]) ?? 0
            perFile.append(WorktreeFileStat(path: path, additions: added, deletions: removed))
            additions += added
            deletions += removed
        }

        for path in nulSeparatedPaths(untrackedData)
            where !baseline.ignoredPaths.contains(path) {
            let url = root.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
            let newlineCount = data.reduce(into: 0) { count, byte in
                if byte == 0x0A { count += 1 }
            }
            let added = newlineCount + (data.last == 0x0A ? 0 : 1)
            perFile.append(WorktreeFileStat(path: path, additions: added, deletions: 0))
            additions += added
        }

        guard !perFile.isEmpty else { return nil }
        return WorktreeChangeStats(
            files: perFile.count,
            additions: additions,
            deletions: deletions,
            perFile: perFile.sorted { $0.path < $1.path }
        )
    }

    /// 为每个本 turn 触及的文件生成 diff 供 FileChange 卡审核：
    /// - untracked 新文件：合成 `--- /dev/null +++ path` 的全 + 行 diff；
    /// - 已跟踪修改：直接取真 git diff（`git diff HEAD -- path`），行数与
    ///   numstat 一致。此前对 tracked 修改也套用"全 +"合成，hunk 头声称
    ///   0 旧行、行内容却与删除行矛盾，split 渲染对齐时布局越界崩溃。
    static func untrackedDiff(root: URL, path: String, additions: Int, isUntracked: Bool) -> String {
        if isUntracked {
            guard additions <= 2000, additions > 0 else { return "" }
            let url = root.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .utf8) else { return "" }
            let body = content
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "+" + $0 }
                .joined(separator: "\n")
            return "--- /dev/null\n+++ \(path)\n@@ -0,0 +1,\(additions) @@\n" + body
        }
        return runGit(["diff", "HEAD", "--", path], cwd: root)
            .map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// 本 turn 之前就存在的脏路径集合（baseline.ignoredPaths）以外的 untracked
    /// 文件才算纯新增。
    static func untrackedPaths(root: URL) -> Set<String> {
        guard let data = runGit(["ls-files", "--others", "--exclude-standard", "-z"], cwd: root) else {
            return []
        }
        return Set(nulSeparatedPaths(data))
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
