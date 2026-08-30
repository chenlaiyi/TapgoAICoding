import Foundation
import TapgoCore

/// All user-facing strings in Tapgo AICoding.
enum L10n {
    // MARK: - App
    static let appName = "Tapgo AICoding"
    static let newThreadCommand = "新建会话"

    // MARK: - Sidebar
    static let threads = "会话"
    static let newThread = "新建会话"
    static let noThreadsYet = "还没有会话"
    static let startANewThread = "开始一个新会话"
    static let projectPickerTitle = "项目"
    static let noProjectSelected = "未选择项目"
    static let selectProjectHint = "选择一个项目来开始新任务"
    static let legacyGroupTitle = "未分类 (历史会话)"
    static let removeFromList = "从列表中移除"
    static let rename = "重命名"
    static let openInFinder = "在 Finder 中打开"
    static let openInTerminal = "在 Terminal 中打开"
    static let copySSHCmd = "复制 SSH 命令"
    static let testConnection = "测试连接"
    static let closeBtn = "关闭"

    // MARK: - Settings
    static let openSettings = "设置…"
    static let tabProjects = "项目"
    static let tabRemoteHosts = "远程主机"
    static let tabAbout = "关于"
    static let addLocal = "添加本地目录"
    static let addRemote = "添加远程项目"
    static let addRemoteHost = "添加远程主机"
    static let hostAlias = "别名"
    static let hostHost = "主机 (IP / 域名)"
    static let hostUser = "用户"
    static let hostPort = "端口"
    static let hostIdentity = "私钥路径 (可空)"
    static let hostLastTest = "最近测试"
    static let remotePathLabel = "远程路径"
    static let localPathLabel = "本地路径"

    // MARK: - New task
    static let newTaskTitle = "新任务"
    static let newTaskChooseProject = "为新任务选择项目"
    static let localFolder = "本地文件夹"
    static let remoteProject = "远程项目"
    static let quickNoProject = "快速任务 (无项目)"
    static let quickNoProjectHint = "不绑定项目,仅作为临时对话"
    static let recentProjects = "最近项目"
    static let noRecentProjects = "没有最近项目"

    // MARK: - Status / Chat
    static let noThreadSelected = "未选中会话"
    static let noThreadSelectedHint = "在左侧选择一个会话,或在右上角新建。"
    static let interrupt = "中断"
    static let selectThreadHint = "选中一个会话,查看它的执行轨迹。"
    static let statusIdle = "空闲"
    static let statusReady = "就绪"
    static let statusRunning = "执行中"
    static let statusFailed = "失败"

    // MARK: - Remote banner
    static let remoteBanner = "远程项目 · 通过 SSH 转发命令"
    static let remoteBannerHint = "本项目的命令会通过配置的 SSH 主机在远程执行,并把真实输出显示在此。"
    static let viaSSHPrefix = "通过 SSH"

    // MARK: - Composer
    static let sendButton = "发送"
    static let attachImages = "添加图片附件"
    static let composePlaceholder = "给当前模型发条任务… (⌘↩ 发送)"
    static let noProject = "无项目"

    // MARK: - Approval
    static let approvalCommandRequested = "执行命令 - 需要批准"
    static let approvalFileChangeRequested = "修改文件 - 需要批准"
    static let approvalToolCallRequested = "工具调用 - 需要批准"
    static let approvalDefaultReason = "需要你的批准"
    static let approve = "批准"
    static let deny = "拒绝"
    static let approvalPending = "待批准"
    static let approvalApproved = "已批准"
    static let approvalDenied = "已拒绝"
    static let approvalApprovedForSession = "本次会话已批准"
    static let approvalAutoApproved = "已自动通过"
    static let approvalCancelled = "已取消"
    static let approvalPolicyTitle = "批准策略"
    static let sandboxModeTitle = "沙箱模式"
    static let reasoningEffortTitle = "思考强度"
    static let appearanceTitle = "外观"
    static let approvalPolicyHint = "批准策略设为\"询问\"后，harness 在执行命令/修改文件前会暂停并在聊天里请求批准。默认\"永不询问\"保持全自动审批。"
    static let apply = "应用"
    static let resetDefault = "默认"

    // MARK: - Errors
    static let failedToSendApproval = "发送批准失败:"
    static let openLocalFolder = "打开本地文件夹…"
    static let modelChipHint = "固定模型 (来自独立 Codex home)"

    // MARK: - Tooltips
    static let tooltipNewThread = "新建会话"
    static let tooltipOpenLocal = "打开本地项目目录 (⌘O)"
    static let tooltipSettings = "设置 (⌘,)"

    // MARK: - Trajectory
    static let trajectory = "执行轨迹"
    static let emptyTurn = "(空)"
    static let projectBadge = "项目"

    // MARK: - Setup
    static let setupTitle = "首次运行"
    static let setupHeadline = "Tapgo AICoding 还没有独立配置"
    static let setupBody = "请在终端运行 ./scripts/init-tapgo.sh 写入独立 Codex home,然后回到这里点击重新检查。"
    static let setupConsole = "在终端运行:"
    static let setupRetry = "重新检查"
    static let setupOpenScripts = "打开 scripts 目录"

    // MARK: - Formatters
    static let userPrefix = "用户:"
    static let assistantPrefix = "助手:"
    static let reasoningPrefix = "思考:"
    static let toolPrefix = "工具:"
    static let errorPrefix = "错误:"
    static let reasoning = "思考过程"
    static let reasoningSummary = "思考摘要"
    static func turnCount(_ n: Int) -> String { "\(n) 个回合" }
    static func approvalLabel(_ kind: String) -> String { "审批(\(approvalKindName(kind)))" }
    static func toolCallName(_ name: String) -> String { "工具: \(name)" }
    static func commandDisplay(_ command: String) -> String { "$ \(command)" }
    static func fileChangeDisplay(_ kind: String, _ path: String) -> String { "\(fileChangeKindName(kind)) \(path)" }
    static func exitCode(_ code: Int32) -> String { "退出码 \(code)" }
    static func remoteHostBadge(_ alias: String) -> String { "@\(alias)" }
    static func pickedAtPath(_ path: String) -> String { "路径: \(path)" }
    static func sshCmdFor(_ host: String, _ path: String) -> String { "ssh \(host) 'cd \(path) && bash -lc \"\\$SHELL\"'" }

    /// Chinese label for an approval kind raw value.
    static func approvalKindName(_ kind: String) -> String {
        switch kind {
        case "commandExecution": return "命令执行"
        case "fileChange": return "文件改动"
        case "toolCall": return "工具调用"
        default: return kind
        }
    }

    /// Chinese label for a file-change kind raw value.
    static func fileChangeKindName(_ kind: String) -> String {
        switch kind {
        case "create": return "添加"
        case "update": return "修改"
        case "delete": return "删除"
        default: return kind
        }
    }
}
