import Foundation

/// Filter for the trajectory timeline. Lets the user focus on one kind
/// of activity (commands, file changes, errors, tool calls) instead of
/// wading through every item.
public enum TrajectoryFilter: String, CaseIterable, Identifiable {
    case all
    case commands
    case reasoning
    case files
    case errors
    case tools

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all:      return "全部"
        case .commands: return "命令"
        case .reasoning: return "推理"
        case .files:    return "文件"
        case .errors:   return "错误"
        case .tools:    return "工具"
        }
    }

    /// Whether a `TurnItem` is shown under this filter.
    public static func matches(item: TurnItem, filter: TrajectoryFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .commands:
            if case .commandExecution = item { return true }
            return false
        case .reasoning:
            if case .reasoning = item { return true }
            if case .reasoningSummary = item { return true }
            return false
        case .files:
            if case .fileChange = item { return true }
            return false
        case .errors:
            if case .error = item { return true }
            return false
        case .tools:
            if case .toolCall = item { return true }
            return false
        }
    }
}
