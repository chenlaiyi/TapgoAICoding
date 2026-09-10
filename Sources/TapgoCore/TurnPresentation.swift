import Foundation

/// A compact, user-facing slice of a turn. The raw `Turn.items` remain
/// untouched for persistence, search, export and diagnostics; only chat
/// rendering consumes these blocks.
public enum TurnPresentationBlock: Identifiable, Hashable {
    case item(TurnItem)
    case activity(TurnActivityRollup)
    case fileBatch([FileChange])
    // v0.5.245: ZCode executeGroup —— 连续命令折叠成一行;文件批次沿用
    // fileBatch 形态(changesGroup 已被 fileBatch 覆盖)。
    case commandGroup([CommandExecution])

    public var id: String {
        switch self {
        case .item(let item):
            return "item-" + item.id
        case .activity(let activity):
            return activity.id
        case .fileBatch(let files):
            return "batch-" + (files.first?.id ?? "file")
        case .commandGroup(let cmds):
            return "cmdgrp-" + (cmds.first?.id ?? "cmd")
        }
    }
}

/// One transcript activity row. 目标 IDE 风格: every reasoning / command /
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
    /// 多段聚合时的合并正文（仅 `.reasoning` / `.search` 类目使用），单行活动为空。
    /// 渲染层基于它计算字符数与展开后的完整内容。
    public let summaryText: String?
    /// 从工具参数里解析出的目标文件路径（编辑/查询/读取行）。非空时渲染层把
    /// 这一行画成「图标 + 标签 + 文件图标 + 文件名 + 路径」的富行，替代原始
    /// JSON 参数截断——与 ZCode 参考样式一致。
    public let filePath: String?

    fileprivate init(
        kind: Kind,
        text: String,
        systemImage: String?,
        isRunning: Bool,
        isFailure: Bool = false,
        summaryText: String? = nil,
        filePath: String? = nil
    ) {
        self.kind = kind
        self.text = text
        self.systemImage = systemImage
        self.isRunning = isRunning
        self.isFailure = isFailure
        self.summaryText = summaryText
        self.filePath = filePath
    }

    fileprivate func appendingSuffix(_ suffix: String) -> TurnActivityDisplay {
        TurnActivityDisplay(
            kind: kind,
            text: text + " · " + suffix,
            systemImage: systemImage,
            isRunning: isRunning,
            isFailure: isFailure,
            summaryText: summaryText,
            filePath: filePath
        )
    }
}

fileprivate struct TurnActivitySemantic {
    let display: TurnActivityDisplay
}

public enum TurnPresentation {
    /// 目标 IDE 风格 transcript: every reasoning / command / tool event keeps
    /// its own quiet row (with the concrete command or query); consecutive
    /// search-like tool calls group into one 查阅 row with counts. File
    /// edits stay a separate batch; messages/approvals/errors stay items.
    public static func compactBlocks(_ items: [TurnItem]) -> [TurnPresentationBlock] {
        var blocks: [TurnPresentationBlock] = []
        var searchGroup: TurnActivityRollup?
        var reasoningGroup: TurnActivityRollup?
        // v0.5.245: ZCode executeGroup —— 连续命令折叠成一行。
        var commandGroup: [CommandExecution] = []
        var files: [FileChange] = []

        func flushSearches() {
            if let group = searchGroup {
                blocks.append(.activity(group))
            }
            searchGroup = nil
        }

        func flushReasoning() {
            if let group = reasoningGroup {
                blocks.append(.activity(group))
            }
            reasoningGroup = nil
        }

        func flushFiles() {
            if !files.isEmpty {
                blocks.append(.fileBatch(files))
            }
            files = []
        }

        // v0.5.245: 终端分组 flush;N=1 不折叠以避免样式退化(走单行 activity)。
        func flushCommands() {
            if commandGroup.count > 1 {
                blocks.append(.commandGroup(commandGroup))
            } else {
                for cmd in commandGroup {
                    blocks.append(.activity(TurnActivityRollup(firstItem: .commandExecution(cmd))))
                }
            }
            commandGroup = []
        }

        for item in items where !item.isAppGeneratedProgress
            && !item.isPlanSnapshot
            && !item.isTurnDiffSnapshot
            && !item.isWorktreeStatsSnapshot {
            switch item {
            case .fileChange(let file):
                flushReasoning()
                flushSearches()
                flushCommands()
                files.append(file)

            case .toolCall(let call):
                flushReasoning()
                flushFiles()
                flushCommands()
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

            case .reasoning, .reasoningSummary:
                // 连续 reasoning / reasoningSummary 合并到同一行：点开后才看得到
                // 完整正文，避免一次回合里出现 5–10 行灰色 "思考中"。
                flushSearches()
                flushFiles()
                flushCommands()
                if reasoningGroup == nil {
                    reasoningGroup = TurnActivityRollup(firstItem: item)
                } else {
                    reasoningGroup?.append(item)
                }

            case .commandExecution(let cmd):
                flushReasoning()
                flushSearches()
                flushFiles()
                commandGroup.append(cmd)

            default:
                flushReasoning()
                flushSearches()
                flushFiles()
                flushCommands()
                blocks.append(.item(item))
            }
        }

        flushReasoning()
        flushSearches()
        flushFiles()
        flushCommands()
        return blocks
    }

    /// Convert raw internal events into the quiet, semantic activity wording
    /// used by 目标 IDE: the label (思考/查阅/终端/编辑/读取) plus the concrete
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
                isFailure: true,
                summaryText: display.summaryText
            )
        }

        // 合并后的 reasoning / reasoningSummary 组：折起成一行 "思考过程"，并把
        // 完整正文与字符数塞进 `summaryText`，渲染层（ReasoningDisclosure）据此显示
        // 字符数徽标和点开展开的内容。运行中仍只展示尾部最新一条的 "正在思考 · …"。
        if activity.events.count > 1,
           activity.events.allSatisfy({ Self.isReasoningEvent($0) }) {
            let joined = reasoningJoinedText(activity.events)
            let totalChars = joined.count
            let tail = activity.latest
            if liveTail, latestRunning {
                var tailDisplay = activityDisplay(for: tail)
                return TurnActivityDisplay(
                    kind: tailDisplay.kind,
                    text: tailDisplay.text,
                    systemImage: tailDisplay.systemImage,
                    isRunning: true,
                    isFailure: false,
                    summaryText: joined
                )
            }
            return TurnActivityDisplay(
                kind: .reasoning,
                // v0.5.243: ZCode 对齐(chat.reasoning.thought)——「思考」。
                text: "思考 · \(totalChars) 字符",
                systemImage: "brain",
                isRunning: false,
                isFailure: false,
                summaryText: joined
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
            // summaryText 仍写入 trimmed 文本供多段合并时使用；单条推理时
            // 渲染层（ReasoningDisclosure）按 text 自身决定是否展开，单行文字
            // 仍保持 "思考" 这种极简标签，避免在每次推理都加字符数噪音。
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return semantic(
                key: "reasoning",
                kind: .reasoning,
                activeText: "正在思考 · " + reasoningSnippet(text),
                completedText: "思考",
                continuationText: "思考",
                icon: "brain",
                running: running,
                failed: false,
                summaryText: trimmed.isEmpty ? nil : trimmed
            )

        case .commandExecution(let execution):
            return commandSemantic(execution)

        case .toolCall(let call):
            return toolSemantic(call)

        case .fileChange(let change):
            let active = change.status == .pending || change.status == .awaitingApproval
            let failed = change.status == .failed || change.status == .denied
            let label = fileChangeLabel(change)
            // v0.5.217: 完成态改用过去式 + 差异统计（对齐 Codex 实机）。
            let completedLabel = fileChangeCompletedLabel(change)
            return semantic(
                key: "edit",
                kind: .edit,
                activeText: label,
                completedText: failed ? completedLabel + " · 执行失败" : completedLabel,
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

        // ZCode 参考样式：运行中是「正在执行 <命令>」，完成后变成「终端 <命令>」
        // 的安静回顾行；标签与命令之间只有空格，不加「·」。
        return semantic(
            key: "command",
            kind: .command,
            activeText: "正在运行 " + command,
            completedText: failed ? "已运行 " + command + " · 执行失败" : "已运行 " + command,
            continuationText: "已运行 " + command,
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
                icon: "arrow.triangle.2.circlepath",
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
        var label: String
        var icon: String
        if ["search", "grep", "query", "find", "glob"].contains(where: name.contains) {
            // v0.5.216: 对齐 Codex 实机（截图 4「查找设备页面验收窗口」）
            // —— 动词按工具名派生（search→搜索 / find|grep|glob→查找 /
            // query→查询），不再统一静态「查询」。
            let verb: String = name.contains("search")
                ? "搜索"
                : (name.contains("find") || name.contains("grep") || name.contains("glob"))
                    ? "查找"
                    : "查询"
            kind = .search; label = verb; icon = "magnifyingglass"
        } else if ["list", "ls"].contains(where: name.contains) {
            kind = .search; label = "查询"; icon = "list.bullet"
        } else if ["read", "open", "view", "get"].contains(where: name.contains) {
            // v0.5.211: 图像文件按 Codex 实机显示「查看图像」（而非通用
            // 「读取」）；其他文件仍显示「读取」。
            // v0.5.215: 对齐 Codex 实机文件读取图标（截图 1 显示 stacked-pages 风格）。
            kind = .read; label = "读取"; icon = "doc.text"
        } else if ["edit", "write", "patch", "update"].contains(where: name.contains) {
            kind = .edit; label = "编辑"; icon = "pencil"
        } else if ["shell", "bash", "command", "exec", "run"].contains(where: name.contains) {
            kind = .command; label = "终端"; icon = "terminal"
        } else {
            // v0.5.215: 对齐 Codex 实机活动行格式（截图 3：「已使用 浏览器」）。
            // 默认 fallback 标签由「使用工具 · <name>」改为「使用 <name>」。
            kind = .tool; label = "使用 " + call.name; icon = "wrench"
        }

        // 目标文件行（ZCode 参考样式）：编辑/查询/读取解析出目标文件后，
        // 单行只显示「标签 + 文件名 + 路径」，原始 JSON 参数不再上屏。
        let filePath = extractFilePath(from: call.arguments, kind: kind)
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp"]
        let isImage: Bool = {
            guard let path = filePath as NSString? else { return false }
            return imageExts.contains(path.pathExtension.lowercased())
        }()
        if isImage {
            label = "查看图像"
            icon = "photo"
        } else if kind == .read {
            // label/label/icon already set above for text read; no-op.
        }
        let base: String
        if filePath != nil {
            base = running ? "正在" + label : label
        } else {
            let detail = argsSnippet(call.arguments)
            base = detail.isEmpty ? label : "\(label) · \(detail)"
        }
        // v0.5.218: 对齐 Codex 实机 —— search 活动完成态用过去式（已查找 / 已搜索
        // / 已查询）而不是沿用现时式标签。
        let capturedLabel = label
        let capturedBase = base
        let completedBase: String = {
            guard kind == .search, !running, !capturedLabel.isEmpty else { return capturedBase }
            let past: String
            switch capturedLabel {
            case "搜索": past = "已搜索"
            case "查找": past = "已查找"
            case "查询": past = "已查询"
            default: past = "已" + capturedLabel
            }
            return past + capturedBase.dropFirst(capturedLabel.count)
        }()
        // v0.5.222: 对齐 Codex 实机（图 3「已使用 浏览器」）—— `.tool` 完成态
        // 用过去式「已使用 <name>」（其它活动行 file/search/command 已在 0.5.217
        // ~0.5.219 完成过去式对齐）。
        let capturedToolBase = base
        let toolCompletedBase: String = {
            guard kind == .tool, !running else { return capturedToolBase }
            let stripped = capturedToolBase.hasPrefix("使用 ") ? String(capturedToolBase.dropFirst(3)) : capturedToolBase
            return "已使用 " + stripped
        }()
        return semantic(
            key: "tool:" + name,
            kind: kind,
            activeText: base,
            completedText: failed ? toolCompletedBase + " · 执行失败" : toolCompletedBase,
            continuationText: base,
            icon: icon,
            running: running,
            failed: failed,
            filePath: filePath
        )
    }

    /// Pull the target file out of a tool-call argument object so the
    /// activity row can render "标签 文件名 路径" instead of raw JSON.
    static func extractFilePath(from rawArguments: String, kind: TurnActivityDisplay.Kind) -> String? {
        guard [TurnActivityDisplay.Kind.edit, .search, .read].contains(kind),
              let data = rawArguments.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        for key in ["path", "file_path", "file", "abs_path", "notebook_path"] {
            if let value = obj[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private static func semantic(
        key: String,
        kind: TurnActivityDisplay.Kind,
        activeText: String,
        completedText: String,
        continuationText: String,
        icon: String?,
        running: Bool,
        failed: Bool,
        summaryText: String? = nil,
        filePath: String? = nil
    ) -> TurnActivitySemantic {
        let display = TurnActivityDisplay(
            kind: kind,
            text: failed ? completedText : (running ? activeText : completedText),
            systemImage: failed ? "exclamationmark.triangle" : icon,
            isRunning: running,
            isFailure: failed,
            summaryText: summaryText,
            filePath: filePath
        )
        return TurnActivitySemantic(
            display: display
        )
    }

    /// 目标 IDE groups consecutive searches into one row whose text carries the
    /// per-category counts, e.g. "查询 · 2 搜索，1 文件".
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
        if reads > 0 { parts.append("\(reads) 文件") }
        return parts.isEmpty ? "查询" : "查询 · " + parts.joined(separator: "，")
    }

    fileprivate static func isSearchToolCall(_ item: TurnItem) -> Bool {
        guard case .toolCall(let call) = item else { return false }
        let name = call.name.lowercased()
        return ["search", "grep", "query", "find", "glob", "list", "ls"].contains(where: name.contains)
    }

    /// 推理事件（reasoning 或 reasoningSummary）。`compactBlocks` 把连续的
    /// 此类事件合并成一个 rollup，`activityDisplay` 走聚合路径。
    fileprivate static func isReasoningEvent(_ item: TurnItem) -> Bool {
        switch item {
        case .reasoning, .reasoningSummary: return true
        default: return false
        }
    }

    /// 把多段思考文本用双换行拼接，便于 `ReasoningDisclosure` 一次展开显示。
    fileprivate static func reasoningJoinedText(_ events: [TurnItem]) -> String {
        events.compactMap { event -> String? in
            switch event {
            case .reasoning(_, let t), .reasoningSummary(_, let t):
                return t.trimmingCharacters(in: .whitespacesAndNewlines)
            default:
                return nil
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
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

    /// v0.5.217: 完成态过去式标签 + 差异统计（对齐 Codex 实机截图 1
    /// 「已创建 /path +220 -0」）。
    public static func fileChangeCompletedLabel(_ change: FileChange) -> String {
        let pastVerb: String
        switch change.kind {
        case .create: pastVerb = "已创建"
        case .update: pastVerb = "已编辑"
        case .delete: pastVerb = "已删除"
        }
        let base = pastVerb + " " + change.path
        let stats = diffStats(change.diff)
        guard let s = stats, (s.added + s.removed) > 0 else { return base }
        return base + " +\(s.added) -\(s.removed)"
    }

    /// 解 unified diff 文本统计 +N -M。忽略 +++ / --- 文件头与 @@ hunk 头。
    public static func diffStats(_ diff: String) -> (added: Int, removed: Int)? {
        guard !diff.isEmpty else { return nil }
        var added = 0, removed = 0
        for raw in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@") { continue }
            if line.hasPrefix("+") { added += 1 }
            else if line.hasPrefix("-") { removed += 1 }
        }
        if added == 0 && removed == 0 { return nil }
        return (added, removed)
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
