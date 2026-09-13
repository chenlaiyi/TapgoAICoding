import Foundation

/// v1.0.2 Phase 3: Mac 端原生配对长链接 (JSON-RPC over TCP) 的响应构造纯函数。
///
/// 约束: `PairingLinkListener.RequestHandler` 只能返回 `Params` (无法返回
/// error frame), 因此失败统一用 `{"ok": false, "error": "<message>"}` 表达;
/// iOS 端 `PairingLink.handleFrame` 据此把 success 转为 failure。
///
/// 输入用轻量 Seed 结构 (不依赖 Thread/Project), 让调用方只做字段映射、
/// 本文件只做语义拼装, 便于在 TapgoTests 里直接单测。
public enum MobilePairingRPC {

    /// 最近会话条目 (调用方从 Thread 映射而来)。
    public struct SessionSeed {
        public let id: String
        public let title: String
        public let projectId: String?
        public let projectName: String?
        public let updatedAt: Date
        public let isAuxiliary: Bool

        public init(id: String, title: String, projectId: String?, projectName: String?,
                    updatedAt: Date, isAuxiliary: Bool) {
            self.id = id; self.title = title
            self.projectId = projectId; self.projectName = projectName
            self.updatedAt = updatedAt; self.isAuxiliary = isAuxiliary
        }
    }

    /// 可切项目条目 (调用方从 Project 映射而来)。
    public struct ProjectSeed {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id; self.name = name
        }
    }

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// listSessions 响应: 过滤辅助会话 → 按 updatedAt 降序 → 取前 limit 条。
    /// 字段与 iOS 端 `DashboardView.parseSessionList` 对齐
    /// (id/title/project/projectId/updatedAt, updatedAt 为 ISO8601)。
    public static func listSessionsResponse(sessions: [SessionSeed],
                                            activeThreadId: String?,
                                            limit: Int = 20) -> MobileRemoteLink.Params {
        let entries: [MobileRemoteLink.AnyJSON] = sessions
            .filter { !$0.isAuxiliary }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { s in
                var obj = MobileRemoteLink.Params()
                obj.set("id", .string(s.id))
                obj.set("title", .string(s.title))
                if let pid = s.projectId {
                    obj.set("projectId", .string(pid))
                    obj.set("project", .string(s.projectName ?? pid))
                }
                obj.set("updatedAt", .string(isoFormatter.string(from: s.updatedAt)))
                return .object(obj.raw)
            }
        var p = MobileRemoteLink.Params()
        p.set("sessions", .array(entries))
        if let aid = activeThreadId, !aid.isEmpty {
            p.set("activeSessionId", .string(aid))
        }
        return p
    }

    /// switchProject 响应: 校验 id 在已知项目里 → 执行 action → {ok, projectId, projectName}。
    /// id 未知时返回 errorParams, action 不执行。
    public static func switchProjectResponse(id: String,
                                             projects: [ProjectSeed],
                                             action: () -> Void) -> MobileRemoteLink.Params {
        guard let project = projects.first(where: { $0.id == id }) else {
            return errorParams("project not found: \(id)")
        }
        action()
        var p = MobileRemoteLink.Params()
        p.set("ok", .bool(true))
        p.set("projectId", .string(project.id))
        p.set("projectName", .string(project.name))
        return p
    }

    /// 失败约定响应 (RequestHandler 只能回 Params, 无法回 error frame)。
    public static func errorParams(_ message: String) -> MobileRemoteLink.Params {
        var p = MobileRemoteLink.Params()
        p.set("ok", .bool(false))
        p.set("error", .string(message))
        return p
    }
}
