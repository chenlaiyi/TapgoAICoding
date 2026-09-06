import Foundation

/// User-facing transcript labels never contain raw tool arguments or reasoning excerpts.
public enum ConversationPresentation {
    public static func workItems(_ presentation: TurnResponsePresentation, showWorkProcess: Bool) -> [TurnItem] {
        showWorkProcess ? presentation.work : []
    }

    public static func activityTitle(_ activity: TurnActivityRollup, running: Bool) -> String {
        let display = TurnPresentation.activityDisplay(for: activity, turnIsRunning: running)
        let title: String
        switch display.kind {
        case .reasoning: title = "思考过程"
        case .search: title = "查阅资料"
        case .read: title = "读取内容"
        case .edit: title = "修改文件"
        case .command: title = "执行命令"
        case .tool: title = "使用工具"
        case .compaction: title = "整理上下文"
        }
        let count = activity.events.count > 1 ? " · \(activity.events.count) 项" : ""
        let state = display.isFailure ? " · 未完成" : (running && display.isRunning ? " · 进行中" : "")
        return title + count + state
    }

    public static func workTitle(status: Turn.Status, duration: TimeInterval?) -> String {
        switch status {
        case .pending, .running: return "正在处理"
        case .awaitingApproval: return "等待确认"
        case .failed: return "处理未完成"
        case .interrupted: return "处理已中断"
        case .completed:
            guard let duration, duration.isFinite, duration >= 0, duration < Double(Int.max / 2) else { return "已处理" }
            return "已处理 " + DurationFormatter.string(seconds: duration)
        }
    }

    public static func emptyResponse(status: Turn.Status) -> String? {
        switch status {
        case .completed: return "任务已结束，未返回最终回复。"
        case .failed: return "任务未完成，可重试。"
        case .interrupted: return "任务已中断，可继续提问或重试。"
        default: return nil
        }
    }
}
