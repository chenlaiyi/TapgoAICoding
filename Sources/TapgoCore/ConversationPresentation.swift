import Foundation

/// User-facing transcript labels never contain raw tool arguments or reasoning excerpts.
public enum ConversationPresentation {
    public static func workItems(_ presentation: TurnResponsePresentation, showWorkProcess: Bool) -> [TurnItem] {
        showWorkProcess ? presentation.work : []
    }

    public static func activityTitle(_ activity: TurnActivityRollup, running: Bool) -> String {
        let display = TurnPresentation.activityDisplay(for: activity, turnIsRunning: running)
        // v0.5.234: 对齐 Codex 实机 —— 行为行标题直接用 display.text（含命令
        // 内容 / 文件路径），不是纯标签。
        // v0.5.243: reasoning 标签对齐 ZCode 源码(chat.reasoning.thought)——「思考」,
        // 不再叫「思考过程」。
        let base: String
        if display.kind == .reasoning {
            base = "思考"
        } else if display.text.isEmpty {
            switch display.kind {
            case .search: base = "查阅资料"
            case .read: base = "读取内容"
            case .edit: base = "修改文件"
            case .command: base = running ? "运行命令" : "运行了命令"
            case .tool: base = "使用"
            case .compaction: base = "整理上下文"
            default: base = "处理中"
            }
        } else {
            base = display.text
        }
        let count = activity.events.count > 1 ? " · \(activity.events.count) \(Self.rollupUnit(for: display.kind))" : ""
        let state = display.isFailure ? " · 失败" : (running && display.isRunning ? " · 进行中" : "")
        return base + count + state
    }

    /// v0.5.244: 聚合数量单位对齐 ZCode 组行(executeGroup=N 个命令、
    /// changesGroup=N 个文件、explore=N 次检索),不再统一用「项」。
    private static func rollupUnit(for kind: TurnActivityDisplay.Kind) -> String {
        switch kind {
        case .command: return "个命令"
        case .edit: return "个文件"
        case .search: return "次检索"
        default: return "项"
        }
    }

    public static func workTitle(status: Turn.Status, duration: TimeInterval?) -> String {
        // v0.5.252: 对齐 Codex 桌面端实测文案 —— 进行中固定「正在思考」(不带时长),
        // 完成后「已处理 {duration}」,中断「已停止」。
        switch status {
        case .pending, .running:
            return "正在思考"
        case .awaitingApproval: return "等待确认"
        case .failed: return "处理未完成"
        case .interrupted: return "已停止"
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
