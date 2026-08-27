import Foundation
@testable import TapgoCore

// MARK: - DiffParser: empty / trivial inputs

@MainActor
func runDiffParserEmpty(_ t: TestRunner) {
    t.section("DiffParser: empty input returns no files")
    let parsed = DiffParser.parse("")
    t.expectEqual(parsed.count, 0, "empty string → []")
}

@MainActor
func runDiffParserWhitespaceOnly(_ t: TestRunner) {
    t.section("DiffParser: whitespace-only input returns no files")
    let parsed = DiffParser.parse("   \n\n\t\n")
    t.expectEqual(parsed.count, 0, "whitespace only → []")
}

// MARK: - DiffParser: single-file unified diff

@MainActor
func runDiffParserSingleFileBasic(_ t: TestRunner) {
    t.section("DiffParser: single-file diff parses file + hunk + lines")
    let raw = """
    --- a/Sources/Foo.swift
    +++ b/Sources/Foo.swift
    @@ -1,3 +1,4 @@
     line one
    -line two removed
    +line two added
    +line three added
     line four
    """
    let files = DiffParser.parse(raw)
    t.expectEqual(files.count, 1, "one file parsed")
    guard let f = files.first else { return }
    t.expectEqual(f.oldPath, "Sources/Foo.swift", "oldPath")
    t.expectEqual(f.newPath, "Sources/Foo.swift", "newPath")
    t.expectEqual(f.isBinary, false, "not binary")
    t.expectEqual(f.hunks.count, 1, "one hunk")
    guard let hunk = f.hunks.first else { return }
    t.expectEqual(hunk.lines.count, 5, "5 lines in hunk")
    t.expectEqual(hunk.lines[0].kind, DiffLine.Kind.context, "first line is context")
    t.expectEqual(hunk.lines[0].content, "line one", "context content")
    t.expectEqual(hunk.lines[0].oldLineNumber, 1, "context old# = 1")
    t.expectEqual(hunk.lines[0].newLineNumber, 1, "context new# = 1")
    t.expectEqual(hunk.lines[1].kind, DiffLine.Kind.remove, "second line is remove")
    t.expectEqual(hunk.lines[1].oldLineNumber, 2, "remove old# = 2")
    t.expectEqual(hunk.lines[1].newLineNumber, nil, "remove has no new#")
    t.expectEqual(hunk.lines[2].kind, DiffLine.Kind.add, "third line is add")
    t.expectEqual(hunk.lines[2].oldLineNumber, nil, "add has no old#")
    t.expectEqual(hunk.lines[2].newLineNumber, 2, "add new# = 2")
    t.expectEqual(hunk.lines[3].kind, DiffLine.Kind.add, "fourth line is add")
    t.expectEqual(hunk.lines[3].newLineNumber, 3, "second add new# = 3")
    t.expectEqual(hunk.lines[4].kind, DiffLine.Kind.context, "fifth line is context")
    t.expectEqual(hunk.lines[4].oldLineNumber, 3, "context old# = 3")
    t.expectEqual(hunk.lines[4].newLineNumber, 4, "context new# = 4")
}

@MainActor
func runDiffParserStats(_ t: TestRunner) {
    t.section("DiffParser: total additions + removals computed")
    let raw = """
    --- a/x
    +++ b/x
    @@ -1,2 +1,2 @@
    -old1
    +new1
     keep
    """
    let f = DiffParser.parse(raw).first!
    t.expectEqual(f.totalAdditions, 1, "+1")
    t.expectEqual(f.totalRemovals, 1, "-1")
    t.expectEqual(f.statsLabel, "+1 −1", "statsLabel")
}

// MARK: - DiffParser: hunk header variants

@MainActor
func runDiffParserSingleLineHunk(_ t: TestRunner) {
    t.section("DiffParser: comma-less hunk header defaults count to 1")
    let raw = """
    --- a/f
    +++ b/f
    @@ -1 +1 @@
     only line
    """
    let f = DiffParser.parse(raw).first!
    t.expectEqual(f.hunks.count, 1, "one hunk")
    t.expectEqual(f.hunks[0].oldCount, 1, "oldCount defaults to 1")
    t.expectEqual(f.hunks[0].newCount, 1, "newCount defaults to 1")
    t.expectEqual(f.hunks[0].oldStart, 1, "oldStart")
    t.expectEqual(f.hunks[0].newStart, 1, "newStart")
}

@MainActor
func runDiffParserHunkWithHeading(_ t: TestRunner) {
    t.section("DiffParser: trailing heading after hunk header is preserved")
    let raw = """
    --- a/f
    +++ b/f
    @@ -10,5 +10,6 @@ func foo() {
     ctx
    +add
    """
    let f = DiffParser.parse(raw).first!
    let h = f.hunks[0]
    t.expectEqual(h.oldStart, 10, "oldStart 10")
    t.expectEqual(h.newStart, 10, "newStart 10")
    t.expect(h.header.contains("func foo()"), "heading preserved in header")
}

// MARK: - DiffParser: create / delete

@MainActor
func runDiffParserCreate(_ t: TestRunner) {
    t.section("DiffParser: brand-new file has /dev/null old path")
    let raw = """
    --- /dev/null
    +++ b/BrandNew.swift
    @@ -0,0 +1,2 @@
    +hello
    +world
    """
    let f = DiffParser.parse(raw).first!
    t.expectEqual(f.oldPath, "/dev/null", "old = /dev/null")
    t.expectEqual(f.newPath, "BrandNew.swift", "new path")
    t.expect(f.isCreated, "isCreated flag")
    t.expect(!f.isDeleted, "not deleted")
    t.expectEqual(f.totalAdditions, 2, "2 added lines, no removes")
    t.expectEqual(f.totalRemovals, 0, "0 removes")
    t.expectEqual(f.displayPath, "BrandNew.swift", "displayPath uses newPath")
}

@MainActor
func runDiffParserDelete(_ t: TestRunner) {
    t.section("DiffParser: deleted file has /dev/null new path")
    let raw = """
    --- a/Old.swift
    +++ /dev/null
    @@ -1,2 +0,0 @@
    -bye
    -bye2
    """
    let f = DiffParser.parse(raw).first!
    t.expectEqual(f.oldPath, "Old.swift", "old path")
    t.expectEqual(f.newPath, "/dev/null", "new = /dev/null")
    t.expect(f.isDeleted, "isDeleted flag")
    t.expectEqual(f.displayPath, "Old.swift", "displayPath falls back to oldPath")
    t.expectEqual(f.totalRemovals, 2, "2 removes")
}

// MARK: - DiffParser: multi-file

@MainActor
func runDiffParserMultiFile(_ t: TestRunner) {
    t.section("DiffParser: multi-file diff splits into one DiffFile each")
    let raw = """
    --- a/one.txt
    +++ b/one.txt
    @@ -1 +1 @@
    -a
    +A
    --- a/two.txt
    +++ b/two.txt
    @@ -1 +1 @@
    -b
    +B
    """
    let files = DiffParser.parse(raw)
    t.expectEqual(files.count, 2, "two files")
    t.expectEqual(files[0].newPath, "one.txt", "first file")
    t.expectEqual(files[1].newPath, "two.txt", "second file")
    t.expectEqual(files[0].totalAdditions, 1, "first +1")
    t.expectEqual(files[1].totalAdditions, 1, "second +1")
}

@MainActor
func runDiffParserGitHeader(_ t: TestRunner) {
    t.section("DiffParser: git-style 'diff --git' header pre-seeds paths")
    let raw = """
    diff --git a/foo.txt b/foo.txt
    index 1234..5678 100644
    --- a/foo.txt
    +++ b/foo.txt
    @@ -1 +1 @@
    -x
    +y
    """
    let files = DiffParser.parse(raw)
    t.expectEqual(files.count, 1, "one file")
    t.expectEqual(files[0].newPath, "foo.txt", "path recovered from git header")
}

// MARK: - DiffParser: edge cases

@MainActor
func runDiffParserCRLFNormalisation(_ t: TestRunner) {
    t.section("DiffParser: CRLF input is normalised to LF before parsing")
    let raw = "--- a/f\r\n+++ b/f\r\n@@ -1 +1 @@\r\n-x\r\n+y\r\n"
    let f = DiffParser.parse(raw).first!
    // 2 real diff lines (-x and +y) — the important thing is that
    // none of them carry a stray CR after CRLF normalisation.
    t.expectEqual(f.allLines.count, 2, "2 diff lines (-x +y)")
    for line in f.hunks.flatMap(\.lines) {
        t.expect(!line.content.contains("\r"), "no CR leaked into content: \(line.content.debugDescription)")
    }
}

@MainActor
func runDiffParserMalformedHeaderIsSkipped(_ t: TestRunner) {
    t.section("DiffParser: malformed @@ header is skipped, not crashed on")
    let raw = """
    --- a/f
    +++ b/f
    @@ not a header
     line a
    +add
    """
    // Malformed header means the parser keeps the file (paths are
    // known) but emits no hunks — so the file IS in the result with
    // an empty hunk list, not dropped from the result entirely.
    let files = DiffParser.parse(raw)
    t.expectEqual(files.count, 1, "file with malformed header is still emitted (no hunks)")
    if let f = files.first {
        t.expectEqual(f.hunks.count, 0, "zero hunks because header was malformed")
        t.expectEqual(f.oldPath, "f", "oldPath recovered from ---")
        t.expectEqual(f.newPath, "f", "newPath recovered from +++")
    }
}

@MainActor
func runDiffParserStableKey(_ t: TestRunner) {
    t.section("DiffParser: DiffLine.stableKey is unique per line")
    let raw = """
    --- a/f
    +++ b/f
    @@ -1,2 +1,3 @@
     same
    -gone
    +added1
    +added2
    """
    let lines = DiffParser.parse(raw).first!.allLines
    let keys = Set(lines.map(\.stableKey))
    t.expectEqual(keys.count, lines.count, "every line has a unique stableKey")
    t.expect(lines[0].stableKey.contains("context"), "first line tagged context")
}

@MainActor
func runDiffParserBinaryMarker(_ t: TestRunner) {
    t.section("DiffParser: binary marker produces a DiffFile with isBinary=true")
    let raw = "Binary files a/img.png and b/img.png differ"
    let f = DiffParser.parse(raw).first!
    t.expect(f.isBinary, "isBinary true")
    t.expectEqual(f.hunks.count, 0, "no hunks for binary diff")
}

@MainActor
func runDiffParserAllLinesOrder(_ t: TestRunner) {
    t.section("DiffParser: allLines preserves hunk + line order")
    let raw = """
    --- a/f
    +++ b/f
    @@ -1 +1 @@
     one
    @@ -10 +10 @@
     ten
    """
    let all = DiffParser.parse(raw).first!.allLines
    t.expectEqual(all.count, 2, "2 lines total")
    t.expectEqual(all[0].content, "one", "first hunk line first")
    t.expectEqual(all[1].content, "ten", "second hunk line second")
}

@MainActor
func runDiffParserNoNewlineAtEOF(_ t: TestRunner) {
    t.section("DiffParser: '\\ No newline' marker is preserved")
    let raw = """
    --- a/f
    +++ b/f
    @@ -1 +1 @@
    -x
    \\ No newline at end of file
    """
    let f = DiffParser.parse(raw).first!
    let last = f.allLines.last!
    t.expectEqual(last.kind, .noNewLine, "kind = noNewLine")
    t.expectEqual(last.newLineNumber, nil, "noNewLine does not carry line numbers")
}

@MainActor
func runDiffParserHunkHeaderParserDirectly(_ t: TestRunner) {
    t.section("DiffParser.parseHunkHeader: returns numeric fields")
    let parsed = DiffParser.parseHunkHeader("@@ -1,3 +2,4 @@")
    if let h = parsed {
        t.expectEqual(h.oldStart, 1, "oldStart 1")
        t.expectEqual(h.oldCount, 3, "oldCount 3")
        t.expectEqual(h.newStart, 2, "newStart 2")
        t.expectEqual(h.newCount, 4, "newCount 4")
    } else {
        t.expect(false, "parseHunkHeader(@@ -1,3 +2,4 @@) should succeed")
        return
    }

    t.expectNil(DiffParser.parseHunkHeader("not a header"), "garbage returns nil")
    if let noComma = DiffParser.parseHunkHeader("@@ -5 +5 @@") {
        t.expectEqual(noComma.oldCount, 1, "no comma → oldCount defaults to 1")
    } else {
        t.expect(false, "parseHunkHeader(@@ -5 +5 @@) should succeed")
    }
}
