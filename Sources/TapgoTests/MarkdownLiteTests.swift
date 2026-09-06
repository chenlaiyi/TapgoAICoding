// TapgoTests/MarkdownLiteTests.swift
import Foundation
import TapgoCore

@MainActor
func runMarkdownLiteFencedCode(_ t: TestRunner) {
    let msg = """
    下面是示例:
    ```swift
    let x = 1
    print(x)
    ```
    结束。
    """
    let segs = MarkdownLite.parse(msg)
    t.expectEqual(segs.count, 3, "fenced: text + code + text")

    t.expectEqual(segs[0], .text("下面是示例:"), "fenced: leading text")
    if case .codeFence(let code, let lang) = segs[1] {
        t.expectEqual(lang, "swift", "fenced: language")
        t.expectEqual(code, "let x = 1\nprint(x)", "fenced: code body")
    } else {
        t.expect(false, "fenced: seg[1] is codeFence")
    }
    t.expectEqual(segs[2], .text("结束。"), "fenced: trailing text")
}

@MainActor
func runMarkdownLiteInlineAndBold(_ t: TestRunner) {
    let segs = MarkdownLite.parseInline("run `ls -la` then **rebuild**")
    t.expectEqual(segs.count, 4, "inline: 4 segments")
    t.expectEqual(segs[0], .text("run "), "inline: leading text")
    t.expectEqual(segs[1], .inline("ls -la"), "inline: inline code")
    t.expectEqual(segs[2], .text(" then "), "inline: middle text")
    t.expectEqual(segs[3], .bold("rebuild"), "inline: bold")
}

@MainActor
func runMarkdownLitePassthrough(_ t: TestRunner) {
    // Plain text with a language-less fence and backticks that never close.
    let plain = "no markdown at all"
    t.expectEqual(MarkdownLite.parse(plain), [.text("no markdown at all")], "passthrough: plain text")

    let openFence = "```\ncode without close"
    let segs = MarkdownLite.parse(openFence)
    t.expectEqual(segs, [.codeFence("code without close", lang: nil)], "passthrough: unclosed fence still a block")
}

@MainActor
func runMarkdownLiteEmpty(_ t: TestRunner) {
    t.expectEqual(MarkdownLite.parse(""), [], "empty: no segments")
    // Whitespace-only content is preserved as a single text run (no fence).
    let ws = MarkdownLite.parse("   \n\n")
    t.expect(ws.count == 1 && ws[0] == .text("   \n\n"), "whitespace: single text run, got \(ws)")
}

@MainActor
func runMarkdownLiteLists(_ t: TestRunner) {
    let bullet = """
    - first
    - **second** item
    - third
    """
    let segs = MarkdownLite.parse(bullet)
    t.expectEqual(segs.count, 1, "bullet: single list block")
    guard case .bulletList(let items, let depths) = segs[0] else {
        t.expect(false, "bullet: seg[0] is bulletList"); return
    }
    t.expectEqual(items.count, 3, "bullet: 3 items")
    t.expectEqual(items[0], [.text("first")], "bullet: item 0")
    t.expectEqual(items[1], [.bold("second"), .text(" item")], "bullet: item 1 inline bold")
    t.expectEqual(items[2], [.text("third")], "bullet: item 2")
    t.expectEqual(depths, [0, 0, 0], "bullet: depths all 0 at column 0")

    let ordered = """
    1. alpha
    2. beta
    """
    let segs2 = MarkdownLite.parse(ordered)
    t.expectEqual(segs2.count, 1, "ordered: single list block")
    guard case .numberedList(let items2, let depths2) = segs2[0] else {
        t.expect(false, "ordered: seg[0] is numberedList"); return
    }
    t.expectEqual(items2.count, 2, "ordered: 2 items")
    t.expectEqual(items2[0], [.text("alpha")], "ordered: item 0")
    t.expectEqual(depths2, [0, 0], "ordered: depths all 0 at column 0")

    // Text, then list, then text.
    let mixed = "intro\n- a\n- b\noutro"
    let segs3 = MarkdownLite.parse(mixed)
    t.expectEqual(segs3.count, 3, "mixed: text + list + text")
    guard case .bulletList = segs3[1] else {
        t.expect(false, "mixed: middle is bulletList"); return
    }
}

@MainActor
func runMarkdownLiteLinks(_ t: TestRunner) {
    // Markdown link [title](url).
    let md = MarkdownLite.parseInline("see [docs](https://example.com/a) now")
    t.expectEqual(md.count, 3, "link: 3 segments")
    t.expectEqual(md[0], .text("see "), "link: lead")
    t.expectEqual(md[1], .link(title: "docs", url: "https://example.com/a"), "link: title+url")
    t.expectEqual(md[2], .text(" now"), "link: tail")

    // Bare autolink.
    let bare = MarkdownLite.parseInline("go to https://example.com/x?q=1 now")
    t.expectEqual(bare.count, 3, "bare: 3 segments")
    if case .link(let title, let url) = bare[1] {
        t.expectEqual(title, "https://example.com/x?q=1", "bare: title==url")
        t.expectEqual(url, "https://example.com/x?q=1", "bare: url")
    } else {
        t.expect(false, "bare: seg[1] is link")
    }
    t.expectEqual(bare[2], .text(" now"), "bare: trailing text")

    // No URL → plain text passthrough.
    t.expectEqual(MarkdownLite.parseInline("no url here"), [.text("no url here")], "link: no url passthrough")
}

@MainActor
func runMarkdownLiteQuoteRule(_ t: TestRunner) {
    // Blockquote.
    let q = MarkdownLite.parse("> note one\n> **note** two")
    t.expectEqual(q.count, 1, "quote: single block")
    guard case .blockquote(let segs) = q[0] else {
        t.expect(false, "quote: seg[0] is blockquote"); return
    }
    t.expectEqual(segs, [.text("note one\n"), .bold("note"), .text(" two")], "quote: inline parsed")

    // Horizontal rule between text.
    let hr = MarkdownLite.parse("above\n---\nbelow")
    t.expectEqual(hr, [.text("above"), .horizontalRule, .text("below")], "rule: text + hr + text")
}

@MainActor
func runMarkdownLiteTables(_ t: TestRunner) {
    let md = """
    | Name | Age |
    |------|-----|
    | Alice | 30 |
    | Bob | 25 |
    """
    let segs = MarkdownLite.parse(md)
    t.expectEqual(segs.count, 1, "table: single block")
    guard case .table(let headers, let rows) = segs[0] else {
        t.expect(false, "table: seg[0] is table"); return
    }
    t.expectEqual(headers, ["Name", "Age"], "table: headers")
    t.expectEqual(rows, [["Alice", "30"], ["Bob", "25"]], "table: rows")

    // A lone pipe line is not a table → passthrough text.
    let lone = MarkdownLite.parse("just a | pipe")
    t.expectEqual(lone, [.text("just a | pipe")], "table: non-table pipe passthrough")
}

@MainActor
func runMarkdownLiteTaskList(_ t: TestRunner) {
    let md = """
    - [x] done thing
    - [ ] **todo** thing
    """
    let segs = MarkdownLite.parse(md)
    t.expectEqual(segs.count, 1, "task: single block")
    guard case .taskList(let items) = segs[0] else {
        t.expect(false, "task: seg[0] is taskList"); return
    }
    t.expectEqual(items.count, 2, "task: 2 items")
    t.expectEqual(items[0].checked, true, "task: item 0 checked")
    t.expectEqual(items[0].content, [.text("done thing")], "task: item 0 content")
    t.expectEqual(items[1].checked, false, "task: item 1 unchecked")
    t.expectEqual(items[1].content, [.bold("todo"), .text(" thing")], "task: item 1 bold")
}

@MainActor
func runMarkdownLiteImages(_ t: TestRunner) {
    let segs = MarkdownLite.parseInline("见 ![截图](https://example.com/a.png) 结尾")
    t.expectEqual(segs.count, 3, "image: 3 segments")
    t.expectEqual(segs[0], .text("见 "), "image: lead")
    t.expectEqual(segs[1], .image(alt: "截图", url: "https://example.com/a.png"), "image: alt+url")
    t.expectEqual(segs[2], .text(" 结尾"), "image: tail")

    // Malformed image → passthrough text.
    t.expectEqual(MarkdownLite.parseInline("hello ![x"), [.text("hello ![x")], "image: malformed passthrough")
}

@MainActor
func runMarkdownLiteHeadings(_ t: TestRunner) {
    let h = MarkdownLite.parse("# Title\n## Sub\n### **Bold**")
    t.expectEqual(h.count, 3, "heading: 3 headings")
    t.expectEqual(h[0], .heading(level: 1, content: [.text("Title")]), "heading: h1")
    t.expectEqual(h[1], .heading(level: 2, content: [.text("Sub")]), "heading: h2")
    t.expectEqual(h[2], .heading(level: 3, content: [.bold("Bold")]), "heading: h3 inline bold")

    // "#notheading" (no space) → text passthrough.
    t.expectEqual(MarkdownLite.parse("#notheading"), [.text("#notheading")], "heading: no-space passthrough")
}

@MainActor
func runMarkdownLiteStrikethrough(_ t: TestRunner) {
    let segs = MarkdownLite.parseInline("struck ~~this~~ done")
    t.expectEqual(segs.count, 3, "strike: 3 segments")
    t.expectEqual(segs[0], .text("struck "), "strike: lead")
    t.expectEqual(segs[1], .strikethrough("this"), "strike: inner")
    t.expectEqual(segs[2], .text(" done"), "strike: tail")
}


@MainActor
func runMarkdownLiteNestedLists(_ t: TestRunner) {
    // 2-space indent per level。常见 markdown 都用 2 空格或 4 空格，
    // listDepth 把每 2 空格算一级，2 空格作者得到 [0,1,2]，4 空格作者也得到 [0,1,2]。
    let nested = """
    - top
      - mid
        - deep
      - mid again
    """
    let segs = MarkdownLite.parse(nested)
    t.expectEqual(segs.count, 1, "nested: single block")
    guard case .bulletList(let items, let depths) = segs[0] else {
        t.expect(false, "nested: seg[0] is bulletList"); return
    }
    t.expectEqual(items.count, 4, "nested: 4 items")
    t.expectEqual(depths, [0, 1, 2, 1], "nested: depths follow 2-space indent")

    // 4-space 缩进也算同一档深度
    let fourSpace = "- a\n    - b\n        - c"
    let segs2 = MarkdownLite.parse(fourSpace)
    guard case .bulletList(_, let d2) = segs2[0] else {
        t.expect(false, "4-space nested: bulletList"); return
    }
    t.expectEqual(d2, [0, 1, 2], "4-space nested: depths match")

    // 编号列表嵌套也要带 depths
    let numNested = "1. x\n   1. y\n      1. z"
    let segs3 = MarkdownLite.parse(numNested)
    guard case .numberedList(_, let d3) = segs3[0] else {
        t.expect(false, "num nested: numberedList"); return
    }
    t.expectEqual(d3, [0, 1, 2], "numbered nested: depths follow 3-space indent floor")
}

@MainActor
func runMarkdownLiteFileReference(_ t: TestRunner) {
    // `path/to/file.ext:line` 形式
    let colon = MarkdownLite.parseInline("see Sources/Foo.swift:42 here")
    t.expectEqual(colon.count, 3, "fileRef colon: 3 segments")
    t.expectEqual(colon[0], .text("see "), "fileRef colon: lead")
    t.expectEqual(colon[1], .fileReference(path: "Sources/Foo.swift", line: 42),
                 "fileRef colon: path+line")
    t.expectEqual(colon[2], .text(" here"), "fileRef colon: tail")

    // `path/to/file.ext (line N)` 形式
    let paren = MarkdownLite.parseInline("看 Withdrawal.php (line 19) 这行")
    t.expectEqual(paren.count, 3, "fileRef paren: 3 segments")
    t.expectEqual(paren[1], .fileReference(path: "Withdrawal.php", line: 19),
                 "fileRef paren: path+line")

    // 深路径也认
    let deep = MarkdownLite.parseInline("a/very/deep/path/to/file.rs:123 ok")
    t.expectEqual(deep.count, 3, "fileRef deep: 3 segments")
    t.expectEqual(deep[1], .fileReference(path: "a/very/deep/path/to/file.rs", line: 123),
                 "fileRef deep: path+line")

    // 单个文件没有扩展名 → 不识别，避免误伤普通数字
    t.expectEqual(
        MarkdownLite.parseInline("just 42 here"),
        [.text("just 42 here")],
        "fileRef: bare number stays text"
    )

    // 路径不带行号 → 不识别，避免吞掉 URL / 正常文本
    t.expectEqual(
        MarkdownLite.parseInline("see https://example.com/foo/bar.html end"),
        [.text("see "),
         .link(title: "https://example.com/foo/bar.html", url: "https://example.com/foo/bar.html"),
         .text(" end")],
        "fileRef: bare URL stays autolink, not fileReference"
    )

    // 同一段里有多个 fileReference
    let multi = MarkdownLite.parseInline("Sources/A.swift:1 and Sources/B.swift:2 done")
    var hits = 0
    for s in multi { if case .fileReference = s { hits += 1 } }
    t.expectEqual(hits, 2, "fileRef: 2 references in same line")
}
