import Foundation

/// DSH-compatible process summary titles for a range of tool activity.
enum MobileProcessLabel {
    /// Category order used when counts tie: the first appearance wins.
    private static let categoryOrder = [
        "read", "readImage", "search", "write", "edit", "commands", "code",
        "webSearch", "webFetch", "subagents", "plan", "questions", "tools",
    ]

    /// Closed-state label for one category.
    private static let doneLabels: [String: String] = [
        "read": "已读取文件", "readImage": "已读取图片", "search": "已搜索代码",
        "write": "已写入文件", "edit": "修改了文件", "commands": "执行了命令",
        "code": "运行了代码", "webSearch": "已搜索网页", "webFetch": "已访问网页",
        "subagents": "已协调子智能体", "plan": "更新了计划", "questions": "向用户提出了问题",
        "tools": "已调用工具", "context": "已注入上下文",
    ]

    /// Running-state label for one category.
    private static let runningLabels: [String: String] = [
        "read": "正在读取文件", "readImage": "正在读取图片", "search": "正在搜索代码",
        "write": "正在写入文件", "edit": "正在修改文件", "commands": "正在运行命令",
        "code": "正在运行代码", "webSearch": "正在搜索网页", "webFetch": "正在访问网页",
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
        if name == "subagent" || name.hasPrefix("subagent_") { return "subagents" }
        if ["todo_write", "create_goal", "update_goal", "get_goal"].contains(name) { return "plan" }
        if name == "ask_user_question" || name == "request_user_input" { return "questions" }
        return "tools"
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
            let label = runningLabels[category] ?? "正在调用工具"
            return running.detail.isEmpty ? label : "\(label) · \(running.detail)"
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
