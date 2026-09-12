import SwiftUI

/// v0.5.254: Codex 代码块的轻量语法着色。
///
/// Codex 实机的 fenced code block 会对关键字/字符串/注释/数字着色；
/// Tapgo 此前是纯文本(warning: 与 Codex 差异明显)。这里实现一个
/// 正则驱动的分段器:按 注释 → 字符串 → 关键字/类型 → 数字 的优先级
/// 扫描,已被高优先规则占用的区间不再被低优先规则覆盖,避免
/// "字符串里的关键字也被染色"这类错配。
///
/// 刻意保持"够用就好":不做完整词法分析,不引入第三方依赖;
/// 语言只区分常见家族(类 C / Shell / Python 等)的关键字表。
enum CodeSyntaxHighlighter {

    private struct Rule {
        let regex: NSRegularExpression
        let color: Color
    }

    /// 返回着色后的 `Text`(调用方负责字体与行距)。
    static func highlighted(_ code: String, language: String?) -> Text {
        guard !code.isEmpty else { return Text("") }
        let rules = rules(for: language)
        guard !rules.isEmpty else { return Text(code) }

        let ns = code as NSString
        let full = NSRange(location: 0, length: ns.length)
        var claims: [(range: NSRange, color: Color)] = []

        for rule in rules {
            rule.regex.enumerateMatches(in: code, options: [], range: full) { match, _, _ in
                guard let match else { return }
                let r = match.range
                guard r.length > 0 else { return }
                // 高优先规则已覆盖 → 跳过
                for existing in claims where NSIntersectionRange(existing.range, r).length > 0 {
                    return
                }
                claims.append((r, rule.color))
            }
        }

        guard !claims.isEmpty else { return Text(code) }
        claims.sort { $0.range.location < $1.range.location }

        var output = Text("")
        var cursor = 0
        for claim in claims {
            if claim.range.location > cursor {
                let plain = ns.substring(with: NSRange(location: cursor, length: claim.range.location - cursor))
                output = output + Text(plain)
            }
            let colored = ns.substring(with: claim.range)
            output = output + Text(colored).foregroundColor(claim.color)
            cursor = claim.range.location + claim.range.length
        }
        if cursor < ns.length {
            output = output + Text(ns.substring(from: cursor))
        }
        return output
    }

    // MARK: - 规则

    private static func rules(for language: String?) -> [Rule] {
        let lang = (language ?? "").lowercased()
        var rules: [Rule] = []

        // 1) 注释(最高优先,避免注释里的引号被当成字符串起始)
        let lineCommentPattern: String
        if ["sh", "bash", "zsh", "shell", "yaml", "yml", "python", "py", "ruby", "rb", "toml", "ini", "conf", "dockerfile"].contains(lang) {
            lineCommentPattern = "#[^\\n]*"
        } else if ["html", "xml", "md", "markdown"].contains(lang) {
            lineCommentPattern = "<!--[\\s\\S]*?-->"
        } else {
            lineCommentPattern = "//[^\\n]*"
        }
        if let r = regex(lineCommentPattern) { rules.append(Rule(regex: r, color: DSHTheme.syntaxComment)) }
        if let r = regex("/\\*[\\s\\S]*?\\*/") { rules.append(Rule(regex: r, color: DSHTheme.syntaxComment)) }

        // 2) 字符串(单/双引号 + 反引号),允许转义
        if let r = regex("\"(?:\\\\.|[^\"\\\\\\n])*\"") { rules.append(Rule(regex: r, color: DSHTheme.syntaxString)) }
        if let r = regex("'(?:\\\\.|[^'\\\\\\n])*'") { rules.append(Rule(regex: r, color: DSHTheme.syntaxString)) }

        // 3) 关键字
        let keywords = keywordSet(for: lang)
        if !keywords.isEmpty {
            let pattern = "\\b(" + keywords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + ")\\b"
            if let r = regex(pattern) { rules.append(Rule(regex: r, color: DSHTheme.syntaxKeyword)) }
        }

        // 4) 数字(含 16 进制 / 小数)
        if let r = regex("\\b(0[xX][0-9a-fA-F]+|\\d+(?:\\.\\d+)?)\\b") {
            rules.append(Rule(regex: r, color: DSHTheme.syntaxNumber))
        }

        return rules
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [])
    }

    private static func keywordSet(for lang: String) -> [String] {
        switch lang {
        case "swift":
            return ["actor", "as", "associatedtype", "async", "await", "break", "case", "catch", "class",
                    "continue", "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough",
                    "false", "fileprivate", "for", "func", "guard", "if", "import", "in", "init", "inout",
                    "internal", "is", "let", "nil", "open", "operator", "private", "protocol", "public",
                    "repeat", "return", "self", "static", "struct", "subscript", "super", "switch", "throw",
                    "throws", "true", "try", "typealias", "var", "where", "while", "some", "any", "weak",
                    "unowned", "lazy", "mutating", "nonmutating", "convenience", "required", "override"]
        case "python", "py":
            return ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del",
                    "elif", "else", "except", "False", "finally", "for", "from", "global", "if", "import",
                    "in", "is", "lambda", "None", "nonlocal", "not", "or", "pass", "raise", "return",
                    "True", "try", "while", "with", "yield", "self"]
        case "javascript", "js", "typescript", "ts", "jsx", "tsx":
            return ["async", "await", "break", "case", "catch", "class", "const", "continue", "debugger",
                    "default", "delete", "do", "else", "export", "extends", "false", "finally", "for",
                    "function", "if", "import", "in", "instanceof", "let", "new", "null", "return",
                    "super", "switch", "this", "throw", "true", "try", "typeof", "undefined", "var",
                    "void", "while", "yield", "interface", "type", "enum", "implements", "public",
                    "private", "protected", "readonly", "as", "from"]
        case "sh", "bash", "zsh", "shell":
            return ["if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case",
                    "esac", "function", "return", "export", "local", "readonly", "declare", "in", "set",
                    "unset", "echo", "cd", "source", "exit", "trap", "shift"]
        case "json":
            return ["true", "false", "null"]
        case "sql":
            return ["select", "from", "where", "insert", "into", "values", "update", "set", "delete",
                    "create", "table", "drop", "alter", "join", "left", "right", "inner", "outer",
                    "on", "group", "by", "order", "having", "limit", "offset", "as", "and", "or", "not",
                    "null", "distinct", "count", "sum", "avg", "min", "max"]
        case "go", "golang":
            return ["break", "case", "chan", "const", "continue", "default", "defer", "else",
                    "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map",
                    "package", "range", "return", "select", "struct", "switch", "type", "var", "nil",
                    "true", "false"]
        case "rust", "rs":
            return ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum",
                    "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod",
                    "move", "mut", "pub", "ref", "return", "self", "static", "struct", "super", "trait",
                    "true", "type", "unsafe", "use", "where", "while"]
        case "yaml", "yml", "toml", "ini", "conf", "dockerfile", "makefile", "make":
            return ["true", "false", "null", "on", "off", "yes", "no"]
        default:
            return []
        }
    }
}
