import Foundation

// MARK: - Diff Model
//
// Structured representation of a unified-format text diff. The goal is
// not to be a fully spec-compliant GNU diff parser — just enough to
// drive a useful review UI: line numbers, per-line kind, and stable
// keys that survive re-renders.

/// One line inside a hunk. `oldLineNumber` / `newLineNumber` are `nil`
/// when the line does not exist on that side (i.e. an added line has
/// no old number, a removed line has no new number).
public struct DiffLine: Hashable, Codable, Sendable {
    public enum Kind: String, Hashable, Codable, Sendable {
        case context   // leading space
        case add        // leading '+'
        case remove     // leading '-'
        case noNewLine  // "\ No newline at end of file"
    }
    public let kind: Kind
    public let content: String
    public let oldLineNumber: Int?
    public let newLineNumber: Int?

    public init(kind: Kind, content: String, oldLineNumber: Int?, newLineNumber: Int?) {
        self.kind = kind
        self.content = content
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
    }

    /// Stable identity used by SwiftUI ForEach / review-comment keying.
    /// The pair `(kind, content, oldLine, newLine)` uniquely identifies
    /// a line within a single parse; reviewers can pin comments to it.
    public var stableKey: String {
        "\(kind.rawValue):\(oldLineNumber ?? -1):\(newLineNumber ?? -1):\(content)"
    }
}

/// A `@@ -a,b +c,d @@` hunk. Header text is kept verbatim so the UI
/// can show "8 lines changed" the same way `git diff` does.
public struct DiffHunk: Hashable, Codable, Sendable {
    public let header: String
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let lines: [DiffLine]

    public init(header: String, oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, lines: [DiffLine]) {
        self.header = header
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
    }
}

/// One file inside a (possibly multi-file) diff text. `oldPath` and
/// `newPath` may be `/dev/null` (treated as a real file with no content)
/// which corresponds to a brand-new or fully-deleted file.
public struct DiffFile: Hashable, Codable, Sendable {
    public let oldPath: String
    public let newPath: String
    public let hunks: [DiffHunk]
    public let isBinary: Bool

    public init(oldPath: String, newPath: String, hunks: [DiffHunk], isBinary: Bool) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.hunks = hunks
        self.isBinary = isBinary
    }

    /// "best" path to display in the UI: prefer `newPath`, fall back to
    /// `oldPath` for pure deletions.
    public var displayPath: String {
        newPath == "/dev/null" ? oldPath : newPath
    }

    /// True when `newPath == /dev/null` (file was deleted).
    public var isDeleted: Bool { newPath == "/dev/null" }

    /// True when `oldPath == /dev/null` (file was created).
    public var isCreated: Bool { oldPath == "/dev/null" }

    /// Flat list of all lines across every hunk — convenient for
    /// review-comment line-number indexing.
    public var allLines: [DiffLine] { hunks.flatMap(\.lines) }

    public var totalAdditions: Int {
        hunks.flatMap(\.lines).lazy.filter { $0.kind == .add }.count
    }
    public var totalRemovals: Int {
        hunks.flatMap(\.lines).lazy.filter { $0.kind == .remove }.count
    }
}

// MARK: - Parser

/// Mutable scratch state for the hunk currently being accumulated.
/// Kept private to the file because it never escapes the parser.
private struct HunkScratch {
    var header: String
    var oldStart: Int
    var oldCount: Int
    var newStart: Int
    var newCount: Int
    var lines: [DiffLine]
    var oldLineNo: Int
    var newLineNo: Int
}

public enum DiffParser {
    /// Parse one or more unified-diff blobs. Returns an empty array for
    /// blank or whitespace-only input.
    public static func parse(_ text: String) -> [DiffFile] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        return parseLines(lines)
    }

    /// Overload that parses a sequence of lines directly. Exposed for
    /// tests so we can feed tricky inputs without trailing-newline games.
    public static func parseLines<S: Sequence>(_ lines: S) -> [DiffFile] where S.Element == String {
        var iter = lines.makeIterator()
        var currentOldPath: String? = nil
        var currentNewPath: String? = nil
        var scratch: HunkScratch? = nil
        var hunks: [DiffHunk] = []
        var result: [DiffFile] = []

        func flushHunk() {
            guard let s = scratch else { return }
            hunks.append(DiffHunk(
                header: s.header,
                oldStart: s.oldStart, oldCount: s.oldCount,
                newStart: s.newStart, newCount: s.newCount,
                lines: s.lines))
            scratch = nil
        }
        func flushFile() {
            flushHunk()
            // Emit the file as long as we know both paths, even if no
            // hunks parsed successfully (e.g. all hunks had malformed
            // headers). The UI still wants to display the file row.
            if let old = currentOldPath, let new = currentNewPath {
                result.append(DiffFile(oldPath: old, newPath: new, hunks: hunks, isBinary: false))
            }
            currentOldPath = nil
            currentNewPath = nil
            hunks = []
        }

        while let line = iter.next() {
            // Git header for a new file: "diff --git a/foo b/foo".
            // Many codex / git-format-patch outputs include this; we use
            // it as a sentinel. We ONLY flush the previous file when
            // the git header represents a TRANSITION (we already have
            // paths set) — if we are starting fresh, the git header
            // just seeds the paths and we wait for --- / +++ to confirm.
            if line.hasPrefix("diff --git ") {
                let haveInProgressFile = currentOldPath != nil
                    && currentNewPath != nil
                    && (scratch != nil || !hunks.isEmpty)
                if haveInProgressFile { flushFile() }
                let parts = line.split(separator: " ")
                if parts.count >= 4 {
                    let a = String(parts[2]).hasPrefix("a/") ? String(parts[2].dropFirst(2)) : String(parts[2])
                    let b = String(parts[3]).hasPrefix("b/") ? String(parts[3].dropFirst(2)) : String(parts[3])
                    currentOldPath = a
                    currentNewPath = b
                }
                continue
            }

            // Standard unified diff file headers.
            if line.hasPrefix("--- ") {
                // Only flush if we have a fully-bound previous file
                // (paths known AND at least one hunk started). This
                // way the --- line that confirms a file already seeded
                // by `diff --git` does NOT trigger a spurious flush.
                let haveInProgressFile = currentOldPath != nil
                    && currentNewPath != nil
                    && (scratch != nil || !hunks.isEmpty)
                if haveInProgressFile { flushFile() }
                currentOldPath = stripPrefix(line, prefix: "--- ")
                if currentNewPath == nil { currentNewPath = currentOldPath }
                continue
            }
            if line.hasPrefix("+++ ") {
                currentNewPath = stripPrefix(line, prefix: "+++ ")
                continue
            }

            // Binary file markers: "Binary files ... differ".
            if line.hasPrefix("Binary files ") {
                flushFile()
                let oldPath = extractBinaryPath(line, side: "a")
                let newPath = extractBinaryPath(line, side: "b")
                result.append(DiffFile(oldPath: oldPath, newPath: newPath, hunks: [], isBinary: true))
                currentOldPath = nil
                currentNewPath = nil
                continue
            }

            // Hunk header.
            if line.hasPrefix("@@") {
                flushHunk()
                guard currentOldPath != nil, currentNewPath != nil,
                      let parsed = parseHunkHeader(line) else {
                    // Malformed header (or no surrounding file) — skip
                    // until next file boundary so we don't strand later
                    // hunks.
                    continue
                }
                scratch = HunkScratch(
                    header: line,
                    oldStart: parsed.oldStart, oldCount: parsed.oldCount,
                    newStart: parsed.newStart, newCount: parsed.newCount,
                    lines: [],
                    oldLineNo: parsed.oldStart, newLineNo: parsed.newStart)
                continue
            }

            // Line content (must be inside a hunk and a file).
            guard var s = scratch, currentOldPath != nil, currentNewPath != nil else { continue }

            if line.hasPrefix("+") {
                s.lines.append(DiffLine(kind: .add, content: String(line.dropFirst()),
                                        oldLineNumber: nil, newLineNumber: s.newLineNo))
                s.newLineNo += 1
                scratch = s
            } else if line.hasPrefix("-") {
                s.lines.append(DiffLine(kind: .remove, content: String(line.dropFirst()),
                                        oldLineNumber: s.oldLineNo, newLineNumber: nil))
                s.oldLineNo += 1
                scratch = s
            } else if line.hasPrefix(" ") {
                s.lines.append(DiffLine(kind: .context, content: String(line.dropFirst()),
                                        oldLineNumber: s.oldLineNo, newLineNumber: s.newLineNo))
                s.oldLineNo += 1
                s.newLineNo += 1
                scratch = s
            } else if line.hasPrefix("\\") {
                s.lines.append(DiffLine(kind: .noNewLine, content: line,
                                        oldLineNumber: nil, newLineNumber: nil))
                // "\ No newline at end of file" does not advance either side.
                scratch = s
            }
            // Anything else (blank between files, headers we don't care
            // about like "index abc..def 100644") is skipped silently.
        }

        flushFile()
        return result
    }

    // MARK: - Helpers

    private static func stripPrefix(_ line: String, prefix: String) -> String {
        var s = String(line.dropFirst(prefix.count))
        // Strip trailing CR (we already normalised CRLF → LF but be safe).
        while s.hasSuffix("\r") { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespaces)
        // Git prefixes file headers with "a/" / "b/". For non-git
        // diffs the line is just the bare path. Strip the cosmetic
        // "a/" / "b/" so reviewers always see the real path.
        if s.hasPrefix("a/") { s = String(s.dropFirst(2)) }
        else if s.hasPrefix("b/") { s = String(s.dropFirst(2)) }
        // "/dev/null" is special and must pass through unchanged.
        return s
    }

    /// Parse `@@ -oldStart,oldCount +newStart,newCount @@ optional heading`.
    /// Both start and count are optional in the spec; we default to 1
    /// for an omitted count (a single-line hunk).
    public static func parseHunkHeader(_ line: String) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int)? {
        // Strip the leading "@@" and the trailing "@@" (heading).
        guard line.hasPrefix("@@") else { return nil }
        let body = String(line.dropFirst(2))
        guard let trailing = body.range(of: "@@") else { return nil }
        let middle = String(body[body.startIndex..<trailing.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let parts = middle.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let oldPart = String(parts[0])  // "-a,b" or "-a"
        let newPart = String(parts[1])  // "+c,d" or "+c"
        guard let oldTuple = parseRange(oldPart, prefix: "-"),
              let newTuple = parseRange(newPart, prefix: "+") else { return nil }
        return (oldTuple.0, oldTuple.1, newTuple.0, newTuple.1)
    }

    /// Parse "-a,b" / "+c,d" or the comma-less form "-a" / "+c".
    private static func parseRange(_ s: String, prefix: String) -> (Int, Int)? {
        guard s.hasPrefix(prefix) else { return nil }
        let body = String(s.dropFirst(prefix.count))
        if let comma = body.firstIndex(of: ",") {
            let startStr = String(body[..<comma])
            let countStr = String(body[body.index(after: comma)...])
            guard let start = Int(startStr), let count = Int(countStr) else { return nil }
            return (start, count)
        }
        guard let start = Int(body) else { return nil }
        return (start, 1)
    }

    /// Extract one side of "Binary files a/foo and b/bar differ".
    /// Returns the path with the leading `a/` or `b/` stripped.
    private static func extractBinaryPath(_ line: String, side: String) -> String {
        // line ~ "Binary files a/path and b/path differ"
        let parts = line.split(separator: " ")
        let token = parts.first(where: { $0.hasPrefix("\(side)/") }) ?? "\(side)/"
        return String(token.dropFirst(side.count + 1))
    }
}

// MARK: - Convenience: pretty stats

public extension DiffFile {
    /// " +12 -3 " style summary used by FileChangeView badges.
    var statsLabel: String {
        "+\(totalAdditions) −\(totalRemovals)"
    }
}
