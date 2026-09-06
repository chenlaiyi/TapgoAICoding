import Foundation

/// A remote project must never acquire a local execution route.
public struct RemoteExecutionContext {
    public let host: RemoteHost
    public let path: String

    public enum ConfigurationError: LocalizedError {
        case missingProject, missingHost, missingPath
        public var errorDescription: String? {
            switch self {
            case .missingProject: return "此任务的项目已被移除，请重新选择项目后再运行。"
            case .missingHost: return "远程主机配置已被移除，请重新添加主机并关联项目。"
            case .missingPath: return "远程项目目录无效，请重新选择远程目录。"
            }
        }
    }

    public static func resolve(project: Project, hosts: [RemoteHost]) throws -> Self? {
        guard project.isRemote else { return nil }
        guard let id = project.remoteHostId, let host = hosts.first(where: { $0.id == id }) else {
            throw ConfigurationError.missingHost
        }
        guard let path = project.remotePath.flatMap(RemoteCommandBuilder.validatePath),
              path.hasPrefix("/") || path == "~" || path.hasPrefix("~/") else {
            throw ConfigurationError.missingPath
        }
        return Self(host: host, path: path)
    }

    public var instructions: String {
        """
        【当前远程项目】SSH 目标：\(host.user)@\(host.host):\(host.port)（\(host.alias)）；目录：\(path)。
        执行器通过 SSH 在该主机启动。执行目录以本回合环境和工具的 pwd 为准，不使用客户端镜像目录。
        首次识别项目或发现历史上下文冲突时，核对 hostname、pwd、git remote；目录名不等于仓库名。
        旧回复、其他电脑的路径和记忆不代表当前环境；需要项目约定时读取远端当前目录的 AGENTS.md / MEMORY.md。
        用户只问当前项目时，用两三句说明主机、目录和仓库即可；不要扩展为文件盘点或同步建议。
        """
    }
}
