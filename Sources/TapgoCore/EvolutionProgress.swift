import Foundation

/// 自进化运行进度协议（evolve.sh 写入，App 读取）。
///
/// 文件位置：`~/Library/Application Support/Tapgo AICoding/state/evolution_progress.json`
/// 停止请求：`evolution_stop_request`（App 写入，evolve.sh 在阶段边界检查）。
public struct EvolutionProgress: Codable, Equatable {
    public let schemaVersion: Int
    public let version: String
    public let phase: String
    public let phaseIndex: Int
    public let phaseCount: Int
    public let status: String
    public let message: String?
    public let iterationBranch: String?
    public let startedAt: String?
    public let updatedAt: String?

    public init(
        schemaVersion: Int = 1,
        version: String,
        phase: String,
        phaseIndex: Int,
        phaseCount: Int,
        status: String,
        message: String? = nil,
        iterationBranch: String? = nil,
        startedAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.version = version
        self.phase = phase
        self.phaseIndex = phaseIndex
        self.phaseCount = phaseCount
        self.status = status
        self.message = message
        self.iterationBranch = iterationBranch
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    public static let progressFileName = "evolution_progress.json"
    public static let stopFileName = "evolution_stop_request"

    public var phaseLabel: String {
        switch phase {
        case "preflight": return "核对仓库"
        case "record": return "写入版本记录"
        case "tests": return "全量回归"
        case "build": return "构建 App"
        case "commit": return "提交与打 tag"
        case "push": return "推送 main"
        case "release": return "发布 Release"
        case "deploy": return "三机部署"
        case "done": return "完成"
        case "failed": return "失败"
        case "stopped": return "已停止"
        default: return phase
        }
    }

    public var isActive: Bool { status == "running" }

    public var isStale: Bool {
        guard status == "running", let raw = updatedAt else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let updated = formatter.date(from: raw) else { return false }
        return Date().timeIntervalSince(updated) > 30 * 60
    }

    public var progressFraction: Double {
        guard phaseCount > 0 else { return 0 }
        return min(1, max(0, Double(phaseIndex) / Double(phaseCount)))
    }

    public static func load(stateDirectory: URL) -> EvolutionProgress? {
        let url = stateDirectory.appendingPathComponent(progressFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(EvolutionProgress.self, from: data)
    }

    public static func requestStop(stateDirectory: URL) throws {
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let url = stateDirectory.appendingPathComponent(stopFileName)
        try ISO8601DateFormatter().string(from: Date()).write(to: url, atomically: true, encoding: .utf8)
    }

    public static func stopRequested(stateDirectory: URL) -> Bool {
        FileManager.default.fileExists(atPath: stateDirectory.appendingPathComponent(stopFileName).path)
    }

    public static func clearStopRequest(stateDirectory: URL) {
        try? FileManager.default.removeItem(at: stateDirectory.appendingPathComponent(stopFileName))
    }
}
