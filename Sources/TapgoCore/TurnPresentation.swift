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

/// One transcript activity row. ZCode-style: every reasoning / command /
/// tool event renders as its own quiet line showing what actually happened
/// (the command text, the search query…); consecutive search-like tool
/// calls group into a single 查阅 row with counts.
public struct TurnActivityRollup: Identifiable, Hashable {
    public let id: String
    public var latest: TurnItem
    public var events: [TurnItem]
    public fileprivate(set) var isTail: Bool

    fileprivate init(firstItem: TurnItem) {
        id = "activity-" + firstItem.id
        latest = firstItem
        events = [firstItem]
        isTail = true
    }

    fileprivate mutating func append(_ item: TurnItem) {
        latest = item
        events.append(item)
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

    fileprivate func appendingSuffix(_ suffix: String) -> TurnActivityDisplay {
        TurnActivityDisplay(
            kind: kind,
            text: text + " · " + suffix,
            systemImage: systemImage,
            isRunning: isRunning,
            isFailure: isFailure
        )
    }
}

fileprivate struct TurnActivitySemantic {
    let display: TurnActivityDisplay
}

public enum TurnPresentation {
    /// ZCode-style transcript: every reasoning / command / tool event keeps
    /// its own quiet row (with the concrete command or query); consecutive
    /// search-like tool calls group into one 查阅 row with counts. File
    /// edits stay a separate batch; messages/approvals/errors stay items.
    public static func compactBlocks(_ items: [TurnItem]) -> [TurnPresentationBlock] {
        var blocks: [TurnPresentationBlock] = []
        var searchGroup: TurnActivityRollup?
        var files: [FileChange] = []

        func flushSearches() {
            if let group = searchGroup {
                blocks.append(.activity(group))
            }
            searchGroup = nil
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
            case .fileChange(let file):
                flushSearches()
                files.append(file)

            case .toolCall(let call):
                flushFiles()
                if Self.isSearchToolCall(.toolCall(call)) {
                    if searchGroup == nil {
                        searchGroup = TurnActivityRollup(firstItem: item)
                    } else {
                        searchGroup?.append(item)
                    }
                } else {
                    flushSearches()
                    blocks.append(.activity(TurnActivityRollup(firstItem: item)))
                }

            case .reasoning, .reasoningSummary, .commandExecution:
                flushSearches()
                flushFiles()
                blocks.append(.activity(TurnActivityRollup(firstItem: item)))

            default:
                flushSearches()
                flushFiles()
                blocks.append(.item(item))
            }
        }

        flushSearches()
        flushFiles()
        return blocks
    }

    /// Convert raw internal events into the quiet, semantic activity wording
    /// used by ZCode: the label (思考/查阅/终端/编辑/读取) plus the concrete
    /// command or query, so the transcript reads like a real work log.
    public static func activityDisplay(for item: TurnItem) -> TurnActivityDisplay {
        let running = itemRunningStatus(item)
        return semantic(for: item, running: running).display
    }

    fileprivate static func itemRunningStatus(_ item: TurnItem) -> Bool {
        switch item {
        case .commandExecution(let e): return e.status == .pending || e.status == .running || e.status == .awaitingApproval
        case .toolCall(let c): return c.status == .pending || c.status == .running || c.status == .awaitingApproval
        case .fileChange(let f): return f.status == .pending || f.status == .awaitingApproval
        default: return false
        }
    }

    /// The running tail shows the current action with its concrete detail;
    /// a closed 查阅 group shows counts ("查阅 · 2 搜索, 1 列表"); every
    /// other closed row keeps the same concrete wording as while running.
    public static func activityDisplay(
        for activity: TurnActivityRollup,
        turnIsRunning: Bool
    ) -> TurnActivityDisplay {
        let liveTail = turnIsRunning && activity.isTail
        let latestRunning = isLiveLatest(in: activity)

        if let failure = activity.events.first(where: { isFailedEvent($0) }) {
            var display = activityDisplay(for: failure)
            if !display.text.hasSuffix("执行失败") { display = display.appendingSuffix("执行失败") }
            return TurnActivityDisplay(
                kind: display.kind,
                text: display.text,
                systemImage: "exclamationmark.triangle",
                isRunning: false,
                isFailure: true
            )
        }

        // While the turn is running, only the still-live tail gets the
        // "正在 …" wording; completed siblings fold into a quiet summary.
        if liveTail, latestRunning {
            return activityDisplay(for: activity.latest)
        }
        if turnIsRunning {
            return completedTail(activity)
        }
        if activity.events.count > 1, activity.events.allSatisfy({ Self.isSearchToolCall($0) }) {
            return .init(
                kind: .search,
                text: searchCountsText(activity.events),
                systemImage: "magnifyingglass",
                isRunning: false
            )
        }

        return activityDisplay(for: activity.latest)
    }

    /// True only when the latest event is itself in a running state.
    fileprivate static func isLiveLatest(in activity: TurnActivityRollup) -> Bool {
        switch activity.latest {
        case .commandExecution(let e):
            return e.status == .pending || e.status == .running || e.status == .awaitingApproval
        case .toolCall(let c):
            return c.status == .pending || c.status == .running || c.status == .awaitingApproval
        case .fileChange(let f):
            return f.status == .pending || f.status == .awaitingApproval
        default:
            return false
        }
    }

    /// While the turn is still running but the latest event has settled,
    /// show a short completed summary of the most recent kind so the row
    /// still reflects the work that just happened.
    fileprivate static func completedTail(_ activity: TurnActivityRollup) -> TurnActivityDisplay {
        var display = activityDisplay(for: activity.latest)
        if display.kind != .reasoning, !display.text.hasSuffix("完成") {
            display = display.appendingSuffix("完成")
        }
        return TurnActivityDisplay(
            kind: display.kind,
            text: display.text,
            systemImage: display.systemImage,
            isRunning: false,
            isFailure: display.isFailure
        )
    }

    fileprivate static func semantic(for item: TurnItem) -> TurnActivitySemantic {
        semantic(for: item, running: itemRunningStatus(item))
    }

    fileprivate static func semantic(for item: TurnItem, running: Bool) -> TurnActivitySemantic {
        switch item {
        case .reasoning(_, let text), .reasoningSummary(_, let text):
            return semantic(
                key: "reasoning",
                kind: .reasoning,
                activeText: "正在思考 · " + reasoningSnippet(text),
                completedText: "思考",
                continuationText: "思考",
                icon: "brain",
                running: running,
                failed: false
            )

        case .commandExecution(let execution):
            return commandSemantic(execution)

        case .toolCall(let call):
            return toolSemantic(call)

        case .fileChange(let change):
            let active = change.status == .pending || change.status == .awaitingApproval
            let failed = change.status == .failed || change.status == .denied
            let label = fileChangeLabel(change)
            return semantic(
                key: "edit",
                kind: .edit,
                activeText: label,
                completedText: failed ? label + " · 执行失败" : label,
                continuationText: label,
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
        let running = execution.status == .pending || execution.status == .running || execution.status == .awaitingApproval
        let failed = execution.status == .failed || execution.status == .denied
        let command = execution.command.replacingOccurrences(of: "\n", with: " ")

        return semantic(
            key: "command",
            kind: .command,
            activeText: "终端 · " + command,
            completedText: failed ? "终端 · " + command + " · 执行失败" : "终端 · " + command,
            continuationText: "终端 · " + command,
            icon: "terminal",
            running: running,
            failed: failed
        )
    }

    private static func toolSemantic(_ call: ToolCall) -> TurnActivitySemantic {
        let name = call.name.lowercased()

        if name.contains("上下文压缩") || name.contains("contextcompaction") || name.contains("context_compaction") {
            return semantic(
                key: "context-compaction",
                kind: .compaction,
                activeText: "正在自动压缩上下文",
                completedText: "上下文已自动压缩",
                continuationText: "自动压缩了上下文",
                icon: "text.line.last.and.arrowtriangle.forward",
                running: call.status == .running,
                failed: call.status == .failed
            )
        }

        if let skill = skillName(in: call.arguments), name.contains("skill") {
            return semantic(
                key: "skill:" + skill.lowercased(),
                kind: .tool,
                activeText: "正在读取 \(skill) 技能",
                completedText: "读取 \(skill) 技能",
                continuationText: "读取 \(skill) 技能",
                icon: "wrench",
                running: call.status == .running || call.status == .pending,
                failed: call.status == .failed || call.status == .denied
            )
        }

        let running = call.status == .pending || call.status == .running || call.status == .awaitingApproval
        let failed = call.status == .failed || call.status == .denied
        let kind: TurnActivityDisplay.Kind
        let label: String
        let icon: String
        if ["search", "grep", "query", "find", "glob"].contains(where: name.contains) {
            kind = .search; label = "查阅"; icon = "magnifyingglass"
        } else if ["list", "ls"].contains(where: name.contains) {
            kind = .search; label = "查阅"; icon = "list.bullet"
        } else if ["read", "open", "view", "get"].contains(where: name.contains) {
            kind = .read; label = "读取"; icon = "book"
        } else if ["edit", "write", "patch", "update"].contains(where: name.contains) {
            kind = .edit; label = "编辑"; icon = "pencil"
        } else if ["shell", "bash", "command", "exec", "run"].contains(where: name.contains) {
            kind = .command; label = "终端"; icon = "terminal"
        } else {
            kind = .tool; label = "使用工具 · " + call.name; icon = "wrench"
        }

        let detail = argsSnippet(call.arguments)
        let base = detail.isEmpty ? label : "\(label) · \(detail)"
        return semantic(
            key: "tool:" + name,
            kind: kind,
            activeText: base,
            completedText: failed ? base + " · 执行失败" : base,
            continuationText: base,
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
            display: display
        )
    }

    /// ZCode groups consecutive searches into one row whose text carries the
    /// per-category counts, e.g. "查阅 · 2 搜索, 1 列表".
    fileprivate static func searchCountsText(_ events: [TurnItem]) -> String {
        var searches = 0
        var listings = 0
        var reads = 0
        for event in events {
            guard case .toolCall(let call) = event else { continue }
            let name = call.name.lowercased()
            if ["list", "ls", "glob"].contains(where: name.contains) { listings += 1 }
            else if ["read", "open", "view", "get"].contains(where: name.contains) { reads += 1 }
            else { searches += 1 }
        }
        var parts: [String] = []
        if searches > 0 { parts.append("\(searches) 搜索") }
        if listings > 0 { parts.append("\(listings) 列表") }
        if reads > 0 { parts.append("\(reads) 读取") }
        return parts.isEmpty ? "查阅" : "查阅 · " + parts.joined(separator: ", ")
    }

    fileprivate static func isSearchToolCall(_ item: TurnItem) -> Bool {
        guard case .toolCall(let call) = item else { return false }
        let name = call.name.lowercased()
        return ["search", "grep", "query", "find", "glob", "list", "ls"].contains(where: name.contains)
    }

    fileprivate static func isFailedEvent(_ item: TurnItem) -> Bool {
        switch item {
        case .commandExecution(let e): return e.status == .failed || e.status == .denied
        case .toolCall(let c): return c.status == .failed || c.status == .denied
        case .fileChange(let f): return f.status == .failed || f.status == .denied
        default: return false
        }
    }

    fileprivate static func argsSnippet(_ raw: String) -> String {
        let firstLine = raw
            .split(whereSeparator: \.isNewline)
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !firstLine.isEmpty else { return "" }
        let flat = firstLine.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 96 ? String(flat.prefix(96)) + "…" : flat
    }

    public static func fileChangeLabel(_ change: FileChange) -> String {
        let verb: String
        switch change.kind {
        case .create: verb = "新建"
        case .update: verb = "编辑"
        case .delete: verb = "删除"
        }
        return verb + " " + change.path
    }

    /// Extract only a safe, human-readable skill label. The source path and
    /// tool arguments remain private and never reach the transcript.
    private static func skillName(in raw: String) -> String? {        let patterns = [
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
