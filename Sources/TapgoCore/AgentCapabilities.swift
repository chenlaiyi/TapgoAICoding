import Foundation

/// A skill / plugin the agent exposes, shown in the sidebar's top-left
/// section. Single source of truth in Core so the UI and any future
/// "capabilities" listing stay in sync.
public struct AgentSkill: Identifiable, Equatable {
    public let name: String
    public let icon: String
    public let detail: String
    public var id: String { name }

    public init(name: String, icon: String, detail: String) {
        self.name = name
        self.icon = icon
        self.detail = detail
    }
}

public enum AgentCapabilities {
    /// The harness tools this front-end can surface. Static for now —
    /// a future version can derive them from the harness / MCP registry.
    public static let skills: [AgentSkill] = [
        .init(name: "终端执行", icon: "terminal", detail: "在主机上运行命令并读取输出"),
        .init(name: "文件读写", icon: "doc", detail: "读取与修改项目文件"),
        .init(name: "网络搜索", icon: "globe", detail: "从互联网检索最新信息"),
        .init(name: "MCP 工具", icon: "cube", detail: "连接模型上下文协议服务器"),
        .init(name: "技能", icon: "book", detail: "按需加载的专项能力"),
    ]
}
