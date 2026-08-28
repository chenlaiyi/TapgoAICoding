import Foundation

/// A compact, user-facing slice of a turn. The raw `Turn.items` remain
/// untouched for persistence, search, export and diagnostics; only chat
/// rendering consumes these blocks.
public enum TurnPresentationBlock: Identifiable, Hashable {
    case item(TurnItem)
    case activity(TurnActivityRollup)
    case fileBatch([FileChange])

    public var id: String {
        switch self {
        case .item(let item):
            return "item-" + item.id
        case .activity(let activity):
            return activity.id
        case .fileBatch(let files):
            return "batch-" + (files.first?.id ?? "file")
        }
    }
}

/// Consecutive internal activity between two user-relevant messages. While a
/// turn is running the latest event replaces the row in place; once the
/// segment closes, its semantic categories remain as one quiet summary row.
public struct TurnActivityRollup: Identifiable, Hashable {
    public let id: String
    public var latest: TurnItem
    public fileprivate(set) var isTail: Bool
    fileprivate var facts: [TurnActivityFact]

    fileprivate init(firstItem: TurnItem) {
        id = "activity-" + firstItem.id
        latest = firstItem
        isTail = true
        facts = [TurnPresentation.semantic(for: firstItem).fact]
    }

    fileprivate mutating func append(_ item: TurnItem) {
        latest = item
        let fact = TurnPresentation.semantic(for: item).fact
        if let index = facts.firstIndex(where: { $0.key == fact.key }) {
            facts[index] = fact
        } else {
            facts.append(fact)
        }
    }
}

public struct TurnActivityDisplay: Hashable {
    public enum Kind: Hashable {
        case reasoning, search, read, edit, command, tool, compaction
    }

    public let kind: Kind
    public let text: String
    public let systemImage: String?
    public let isRunning: Bool
    public let isFailure: Bool

    fileprivate init(
        kind: Kind,
        text: String,
        systemImage: String?,
        isRunning: Bool,
        isFailure: Bool = false
    ) {
        self.kind = kind
        self.text = text
        self.systemImage = systemImage
        self.isRunning = isRunning
        self.isFailure = isFailure
    }
}

fileprivate struct TurnActivityFact: Hashable {
    let key: String
    let kind: TurnActivityDisplay.Kind
    let completedText: String
    let continuationText: String
    let systemImage: String?
    let isFailure: Bool
}

fileprivate struct TurnActivitySemantic {
    let display: TurnActivityDisplay
    let fact: TurnActivityFact
}

public enum TurnPresentation {
    /// Collapse repetitive reasoning/command/tool events until the next
    /// visible milestone. File edits, approvals, errors and real messages
    /// remain explicit boundaries and retain their original order.
    public static func compactBlocks(_ items: [TurnItem]) -> [TurnPresentationBlock] {
        var blocks: [TurnPresentationBlock] = []
        var activity: TurnActivityRollup?
        var files: [FileChange] = []

        func flushActivity(isTail: Bool = false) {
            if var activity {
                activity.isTail = isTail
                blocks.append(.activity(activity))
            }
            activity = nil
        }

        func flushFiles() {
            if !files.isEmpty {
                blocks.append(.fileBatch(files))
            }
            files = []
        }

        for item in items where !item.isAppGeneratedProgress
            && !item.isPlanSnapshot
            && !item.isTurnDiffSnapshot
            && !item.isWorktreeStatsSnapshot {
            switch item {
            case .reasoning, .reasoningSummary, .commandExecution, .toolCall:
                flushFiles()
                if activity == nil {
                    activity = TurnActivityRollup(firstItem: item)
                } else {
                    activity?.append(item)
                }

            case .fileChange(let file):
                flushActivity()
                files.append(file)

            default:
                flushActivity()
                flushFiles()
                blocks.append(.item(item))
            }
        }

        flushActivity(isTail: true)
        flushFiles()
        return blocks
    }

    /// Convert raw internal events into the quiet, semantic activity wording
    /// used by Codex. Shell details and tool arguments stay in the model for
    /// diagnostics but are not exposed in the normal chat transcript.
    public static func activityDisplay(for item: TurnItem) -> TurnActivityDisplay {
        semantic(for: item).display
    }

    /// Running tails show the current action. Closed segments and completed
    /// turns show one durable, categorized summary assembled from the segment
    /// without exposing shell commands, paths or tool arguments.
    public static func activityDisplay(
        for activity: TurnActivityRollup,
        turnIsRunning: Bool
    ) -> TurnActivityDisplay {
        if turnIsRunning && activity.isTail {
            return activityDisplay(for: activity.latest)
        }

        if let failure = activity.facts.last(where: \.isFailure) {
            return .init(
                kind: failure.kind,
                text: failure.completedText,
                systemImage: "exclamationmark.triangle",
                isRunning: false,
                isFailure: true
            )
        }

        let meaningful = activity.facts.filter { $0.kind != .reasoning }
        let facts = meaningful.isEmpty ? activity.facts : meaningful
        guard let last = facts.last else {
            return .init(kind: .reasoning, text: "已完成思考", systemImage: nil, isRunning: false)
        }
        return .init(
            kind: last.kind,
            text: completedSummary(facts),
            systemImage: facts.count == 1 ? last.systemImage : summaryIcon(for: facts),
            isRunning: false
        )
    }

    fileprivate static func semantic(for item: TurnItem) -> TurnActivitySemantic {
        switch item {
        case .reasoning(_, let text), .reasoningSummary(_, let text):
            return semantic(
                key: "reasoning",
                kind: .reasoning,
                activeText: reasoningSnippet(text),
                completedText: "已完成思考",
                continuationText: "完成了思考",
                icon: nil,
                running: true,
                failed: false
            )

        case .commandExecution(let execution):
            return commandSemantic(execution)

        case .toolCall(let call):
            return toolSemantic(call)

        case .fileChange(let change):
            let active = change.status == .pending || change.status == .awaitingApproval
            let failed = change.status == .failed || change.status == .denied
            return semantic(
                key: "edit",
                kind: .edit,
                activeText: "正在编辑文件",
                completedText: failed ? "编辑文件失败" : "已编辑文件",
                continuationText: failed ? "编辑文件失败" : "编辑了文件",
                icon: "pencil",
                running: active,
                failed: failed
            )

        default:
            return semantic(
                key: "tool",
                kind: .tool,
                activeText: "正在处理",
                completedText: "已完成处理",
                continuationText: "完成了处理",
                icon: "wrench",
                running: true,
                failed: false
            )
        }
    }

    private static func commandSemantic(_ execution: CommandExecution) -> TurnActivitySemantic {
        let command = execution.command.lowercased()
        let running = execution.status == .pending || execution.status == .running || execution.status == .awaitingApproval
        let failed = execution.status == .failed || execution.status == .denied

        let kind: TurnActivityDisplay.Kind
        let key: String
        let activeText: String
        let finishedText: String
        let continuationText: String
        let icon: String

        if let skill = skillName(in: execution.command) {
            kind = .tool; key = "skill:" + skill.lowercased()
            activeText = "正在读取 \(skill) 技能"
            finishedText = "已读取 \(skill) 技能"
            continuationText = "读取了 \(skill) 技能"
            icon = "wrench"
        } else if command.contains("swift test") || command.contains("tapgotests") || command.contains("xctest") {
            kind = .command; key = "test"; activeText = "正在运行测试"; finishedText = "运行了测试"; continuationText = "运行了测试"; icon = "terminal"
        } else if command.contains("swift build") || command.contains("xcodebuild") || command.contains("build-app") {
            kind = .command; key = "build"; activeText = "正在构建 App"; finishedText = "构建了 App"; continuationText = "构建了 App"; icon = "terminal"
        } else if containsCommand(command, names: ["rg", "grep", "find", "fd"]) {
            kind = .search; key = "search"; activeText = "正在搜索文件"; finishedText = "已搜索文件"; continuationText = "搜索了文件"; icon = "magnifyingglass"
        } else if containsCommand(command, names: ["cat", "head", "tail", "less", "wc"]) || command.contains("sed -n") {
            kind = .read; key = "read"; activeText = "正在读取文件"; finishedText = "已读取文件"; continuationText = "读取了文件"; icon = "book"
        } else if command.contains("apply_patch") || command.contains("sed -i") || command.contains("perl -pi") {
            kind = .edit; key = "edit"; activeText = "正在编辑文件"; finishedText = "已编辑文件"; continuationText = "编辑了文件"; icon = "pencil"
        } else {
            kind = .command; key = "command"; activeText = "正在运行命令"; finishedText = "运行了命令"; continuationText = "运行了命令"; icon = "terminal"
        }

        return semantic(
            key: key,
            kind: kind,
            activeText: activeText,
            completedText: failed ? "命令运行失败" : finishedText,
            continuationText: failed ? "命令运行失败" : continuationText,
            icon: icon,
            running: running,
            failed: failed
        )
    }

    private static func toolSemantic(_ call: ToolCall) -> TurnActivitySemantic {
        let name = call.name.lowercased()
        let running = call.status == .pending || call.status == .running || call.status == .awaitingApproval
        let failed = call.status == .failed || call.status == .denied

        let kind: TurnActivityDisplay.Kind
        let key: String
        let activeText: String
        let finishedText: String
        let continuationText: String
        let icon: String
        if name.contains("上下文压缩") || name.contains("contextcompaction") || name.contains("context_compaction") {
            kind = .compaction; key = "context-compaction"
            activeText = "正在自动压缩上下文"
            finishedText = "上下文已自动压缩"
            continuationText = "自动压缩了上下文"
            icon = "text.line.last.and.arrowtriangle.forward"
        } else if let skill = skillName(in: call.arguments), name.contains("skill") {
            kind = .tool; key = "skill:" + skill.lowercased()
            activeText = "正在读取 \(skill) 技能"
            finishedText = "已读取 \(skill) 技能"
            continuationText = "读取了 \(skill) 技能"
            icon = "wrench"
        } else if name.contains("load") && (["read", "file"].contains(where: name.contains)) {
            kind = .tool; key = "load-file-tool"
            activeText = "正在加载工具读取文件"
            finishedText = "加载了工具读取文件"
            continuationText = "加载了工具读取文件"
            icon = "wrench"
        } else if ["search", "grep", "find", "query"].contains(where: name.contains) {
            kind = .search; key = "search"; activeText = "正在搜索"; finishedText = "已完成搜索"; continuationText = "完成了搜索"; icon = "magnifyingglass"
        } else if ["read", "open", "view", "get"].contains(where: name.contains) {
            kind = .read; key = "read"; activeText = "正在读取文件"; finishedText = "已读取文件"; continuationText = "读取了文件"; icon = "book"
        } else if ["edit", "write", "patch", "update"].contains(where: name.contains) {
            kind = .edit; key = "edit"; activeText = "正在编辑文件"; finishedText = "已编辑文件"; continuationText = "编辑了文件"; icon = "pencil"
        } else if ["shell", "bash", "command", "exec", "run"].contains(where: name.contains) {
            kind = .command; key = "command"; activeText = "正在运行命令"; finishedText = "运行了命令"; continuationText = "运行了命令"; icon = "terminal"
        } else {
            kind = .tool; key = "tool"; activeText = "正在使用工具"; finishedText = "使用了工具"; continuationText = "使用了工具"; icon = "wrench"
        }

        return semantic(
            key: key,
            kind: kind,
            activeText: activeText,
            completedText: failed ? "工具使用失败" : finishedText,
            continuationText: failed ? "工具使用失败" : continuationText,
            icon: icon,
            running: running,
            failed: failed
        )
    }

    private static func semantic(
        key: String,
        kind: TurnActivityDisplay.Kind,
        activeText: String,
        completedText: String,
        continuationText: String,
        icon: String?,
        running: Bool,
        failed: Bool
    ) -> TurnActivitySemantic {
        let display = TurnActivityDisplay(
            kind: kind,
            text: failed ? completedText : (running ? activeText : completedText),
            systemImage: failed ? "exclamationmark.triangle" : icon,
            isRunning: running,
            isFailure: failed
        )
        return TurnActivitySemantic(
            display: display,
            fact: TurnActivityFact(
                key: key,
                kind: kind,
                completedText: completedText,
                continuationText: continuationText,
                systemImage: icon,
                isFailure: failed
            )
        )
    }

    private static func completedSummary(_ facts: [TurnActivityFact]) -> String {
        guard let first = facts.first else { return "已完成处理" }
        guard facts.count > 1 else { return first.completedText }
        if facts.count == 2 {
            return first.completedText + "并" + facts[1].continuationText
        }
        let middle = facts.dropFirst().dropLast().map(\.continuationText).joined(separator: "、")
        return first.completedText + "、" + middle + "并" + facts.last!.continuationText
    }

    private static func summaryIcon(for facts: [TurnActivityFact]) -> String? {
        if facts.contains(where: { $0.kind == .compaction }) {
            return "text.line.last.and.arrowtriangle.forward"
        }
        if facts.contains(where: { $0.kind == .tool }) { return "wrench" }
        if facts.contains(where: { $0.kind == .edit }) { return "pencil" }
        if facts.contains(where: { $0.kind == .search }) { return "magnifyingglass" }
        return facts.last?.systemImage
    }

    /// Extract only a safe, human-readable skill label. The source path and
    /// tool arguments remain private and never reach the transcript.
    private static func skillName(in raw: String) -> String? {
        let patterns = [
            #"(?i)/skills/([^/\s\"']+)/SKILL\.md"#,
            #"(?i)\"(?:skill_name|skill)\"\s*:\s*\"([^\"]+)\""#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: raw)
            else { continue }
            let candidate = String(raw[range])
            guard candidate.count <= 60,
                  candidate.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == " " })
            else { continue }
            let words = candidate.split { $0 == "-" || $0 == "_" || $0 == " " }
            guard !words.isEmpty else { continue }
            return words.enumerated().map { index, word in
                let value = word.lowercased()
                if ["ai", "ui", "ux", "pdf", "mcp"].contains(value) { return value.uppercased() }
                if index > 0 && ["to", "and", "of", "for", "in"].contains(value) { return value }
                return value.prefix(1).uppercased() + value.dropFirst()
            }.joined(separator: " ")
        }
        return nil
    }

    private static func containsCommand(_ command: String, names: [String]) -> Bool {
        let tokens = Set(command.split { character in
            !(character.isLetter || character.isNumber || character == "_" || character == "-")
        }.map(String.init))
        return names.contains(where: tokens.contains)
    }

    private static func reasoningSnippet(_ text: String) -> String {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard var result = lines.last else { return "正在思考" }
        while let first = result.first, "#*-•>".contains(first) {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespaces)
        }
        return result.isEmpty ? "正在思考" : result
    }
}
