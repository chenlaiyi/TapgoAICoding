import Foundation

/// DSH-compatible process summary titles for a range of tool activity.
enum MobileProcessLabel {
    /// Category order used when counts tie: the first appearance wins.
    private static let categoryOrder = [
        "read", "readImage", "search", "write", "edit", "commands", "code",
        "webSearch", "webFetch", "computer", "subagents", "plan", "questions", "tools",
    ]

    /// Closed-state label for one category.
    private static let doneLabels: [String: String] = [
        "read": "已读取文件", "readImage": "已读取图片", "search": "已搜索代码",
        "write": "已写入文件", "edit": "修改了文件", "commands": "执行了命令",
        "code": "运行了代码", "webSearch": "已搜索网页", "webFetch": "已访问网页",
        "computer": "已操作电脑",
        "subagents": "已协调子智能体", "plan": "更新了计划", "questions": "向用户提出了问题",
        "tools": "已调用工具", "context": "已注入上下文",
    ]

    /// Running-state label for one category.
    private static let runningLabels: [String: String] = [
        "read": "正在读取文件", "readImage": "正在读取图片", "search": "正在搜索代码",
        "write": "正在写入文件", "edit": "正在修改文件", "commands": "正在运行命令",
        "code": "正在运行代码", "webSearch": "正在搜索网页", "webFetch": "正在访问网页",
        "computer": "正在操作电脑",
        "subagents": "正在协调子智能体", "plan": "正在更新计划", "questions": "正在提问",
        "tools": "正在调用工具", "context": "正在注入上下文",
    ]

    /// DSH category for one tool name.
    /// - Parameter name: tool name from the session event.
    /// - Returns: the category key shared with the DSH web client.
    static func category(for name: String) -> String {
        if name == "read" { return "read" }
        if name == "read_image" { return "readImage" }
        if name == "grep" || name == "glob" || name.hasSuffix("_inspect") { return "search" }
        if name == "write" { return "write" }
        if name == "edit" || name == "apply_patch" { return "edit" }
        if ["bash", "pwsh", "exec_command", "write_stdin"].contains(name) || name.hasPrefix("terminal_") {
            return "commands"
        }
        if name == "run_code" { return "code" }
        if name == "web_search" { return "webSearch" }
        if name == "web_fetch" { return "webFetch" }
        if name.hasPrefix("cua_") || name.hasPrefix("computer_") { return "computer" }
        if name == "subagent" || name.hasPrefix("subagent_") { return "subagents" }
        if ["todo_write", "create_goal", "update_goal", "get_goal"].contains(name) { return "plan" }
        if name == "ask_user_question" || name == "request_user_input" { return "questions" }
        return "tools"
    }

    /// Leading symbol for the activity mix, matching the DSH process-row icons.
    /// - Parameter activities: activities in first-appearance order.
    /// - Returns: an SF Symbol name.
    static func symbol(activities: [MobileChatActivity]) -> String {
        if let running = activities.last(where: { !$0.finished }) {
            return symbol(for: category(for: running.name))
        }
        var counts: [String: Int] = [:]
        var order: [String] = []
        for activity in activities {
            let category = category(for: activity.name)
            if counts[category] == nil { order.append(category) }
            counts[category, default: 0] += 1
        }
        let ranked = categoryOrder.filter { counts[$0] != nil }
            + order.filter { !categoryOrder.contains($0) }
        guard let dominant = ranked.max(by: { counts[$0, default: 0] < counts[$1, default: 0] }) else {
            return "list.bullet.clipboard"
        }
        return symbol(for: dominant)
    }

    /// SF Symbol for one category.
    /// - Parameter category: DSH category key.
    /// - Returns: the process-row icon.
    private static func symbol(for category: String) -> String {
        switch category {
        case "search": return "magnifyingglass"
        case "read": return "book"
        case "readImage": return "photo"
        case "commands": return "terminal"
        case "code": return "chevron.left.forwardslash.chevron.right"
        case "write", "edit": return "pencil"
        case "webSearch", "webFetch": return "globe"
        case "computer": return "macwindow"
        case "subagents": return "person.2"
        case "plan": return "list.bullet"
        default: return "wrench.and.screwdriver"
        }
    }

    /// Collapsed-row title with per-category counts and the current action last.
    /// - Parameters:
    ///   - activities: activities in first-appearance order.
    ///   - hasReasoning: whether the range also contains reasoning text.
    ///   - running: whether the range is still streaming.
    /// - Returns: a one-line title such as `已执行 1 次搜索 · 已运行 5 条命令`.
    static func countedTitle(activities: [MobileChatActivity], hasReasoning: Bool,
                             running: Bool = false) -> String {
        var parts = countedParts(activities.filter(\.finished))
        if let runningActivity = activities.last(where: { !$0.finished }) {
            let category = category(for: runningActivity.name)
            let label = runningLabel(for: runningActivity.name, category: category)
            let detail = category == "computer" ? "" : runningActivity.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(detail.isEmpty ? label : "\(label) · \(detail)")
        }
        guard !parts.isEmpty else { return hasReasoning ? "已完成分析" : "已完成分析" }
        return parts.joined(separator: " · ")
    }

    /// Counted phrases for finished activities, ranked by the DSH category order.
    /// - Parameter activities: finished activities.
    /// - Returns: up to three phrases such as `已运行 2 条命令`.
    private static func countedParts(_ activities: [MobileChatActivity]) -> [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for activity in activities {
            let category = category(for: activity.name)
            if counts[category] == nil { order.append(category) }
            counts[category, default: 0] += 1
        }
        let ranked = categoryOrder.filter { counts[$0] != nil }
            + order.filter { !categoryOrder.contains($0) }
        return ranked.compactMap { category in
            guard let count = counts[category] else { return nil }
            return countedLabel(category, count: count)
        }
    }

    /// One counted phrase for a category.
    /// - Parameters:
    ///   - category: DSH category key.
    ///   - count: number of activities in that category.
    /// - Returns: the phrase, or nil for a category without a counted label.
    private static func countedLabel(_ category: String, count: Int) -> String? {
        switch category {
        case "read": return "已浏览 \(count) 个文件"
        case "readImage": return "已查看 \(count) 张图片"
        case "search": return "执行了 \(count) 次搜索"
        case "write": return "已写入 \(count) 个文件"
        case "edit": return "已编辑 \(count) 个文件"
        case "commands": return "已运行 \(count) 条命令"
        case "code": return "已运行 \(count) 段代码"
        case "webSearch": return "已搜索 \(count) 次网页"
        case "webFetch": return "已访问 \(count) 个网页"
        case "computer": return "已执行 \(count) 次电脑操作"
        case "subagents": return "已协调 \(count) 个子智能体"
        case "plan": return "已更新 \(count) 次计划"
        case "questions": return "已提出 \(count) 个问题"
        case "tools": return "已调用 \(count) 次工具"
        default: return nil
        }
    }

    /// Human-readable running label, with specific verbs for computer-use tools.
    /// - Parameters:
    ///   - name: tool name.
    ///   - category: mapped category.
    /// - Returns: the running label.
    private static func runningLabel(for name: String, category: String) -> String {
        guard category == "computer" else { return runningLabels[category] ?? "正在调用工具" }
        if name.contains("desktop_state") || name.contains("window_state") || name.contains("screenshot") {
            return "正在查看屏幕"
        }
        if name.contains("browser") { return "正在操作浏览器" }
        if name.contains("click") || name.contains("type") || name.contains("press")
            || name.contains("drag") || name.contains("scroll") || name.contains("launch") {
            return "正在操作电脑"
        }
        return "正在操作电脑"
    }

    /// Summary title for one range of activity.
    /// - Parameters:
    ///   - activities: activities in first-appearance order.
    ///   - hasReasoning: whether the range also contains reasoning text.
    ///   - running: whether the range is still streaming.
    /// - Returns: a DSH-style title such as `执行了命令`, `已读取文件，搜索代码`, or `正在分析请求`.
    static func title(activities: [MobileChatActivity], hasReasoning: Bool, running: Bool = false) -> String {
        if running, activities.isEmpty { return "正在分析请求" }
        if let running = activities.last(where: { !$0.finished }) {
            let category = category(for: running.name)
            let label = runningLabel(for: running.name, category: category)
            let detail = category == "computer" ? "" : running.detail
            return detail.isEmpty ? label : "\(label) · \(detail)"
        }
        var counts: [String: Int] = [:]
        var order: [String] = []
        for activity in activities {
            let category = category(for: activity.name)
            if counts[category] == nil { order.append(category) }
            counts[category, default: 0] += 1
        }
        let ranked = categoryOrder.filter { counts[$0] != nil }
            + order.filter { !categoryOrder.contains($0) }
        let labels = ranked.prefix(3).map { doneLabels[$0] ?? "已调用工具" }
        guard let first = labels.first else {
            return hasReasoning ? "已完成分析" : "已完成分析"
        }
        if labels.count == 1 { return first }
        if labels.count == 2 {
            let second = labels[1]
            let shared = first.hasPrefix("已") && second.hasPrefix("已")
            return "\(first)并\(shared ? String(second.dropFirst()) : second)"
        }
        let title = ([first] + labels.dropFirst()).joined(separator: "，")
        return ranked.count > 3 ? "\(title)等" : title
    }
}
