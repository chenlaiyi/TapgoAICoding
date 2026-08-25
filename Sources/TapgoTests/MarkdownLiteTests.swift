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
    guard case .bulletList(let items) = segs[0] else {
        t.expect(false, "bullet: seg[0] is bulletList"); return
    }
    t.expectEqual(items.count, 3, "bullet: 3 items")
    t.expectEqual(items[0], [.text("first")], "bullet: item 0")
    t.expectEqual(items[1], [.bold("second"), .text(" item")], "bullet: item 1 inline bold")
    t.expectEqual(items[2], [.text("third")], "bullet: item 2")

    let ordered = """
    1. alpha
    2. beta
    """
    let segs2 = MarkdownLite.parse(ordered)
    t.expectEqual(segs2.count, 1, "ordered: single list block")
    guard case .numberedList(let items2) = segs2[0] else {
        t.expect(false, "ordered: seg[0] is numberedList"); return
    }
    t.expectEqual(items2.count, 2, "ordered: 2 items")
    t.expectEqual(items2[0], [.text("alpha")], "ordered: item 0")

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
