import Foundation

/// 自进化会话成本快照（App 写入，evolve.sh 读取）。
///
/// 文件位置：`~/Library/Application Support/Tapgo AICoding/state/evolution_cost.json`
///
/// 语义（EVO-041）：App 把**自进化会话**（`Thread.mode == .evolutionMode`，
/// thread id 前缀 `evo-`）到写文件为止的累计 token 用量写出来。costUSD 只在
/// 有可信来源时才写（当前没有价格表，因此通常为 nil —— 不估算金额）。
///
/// evolve.sh 取「上一次发布记录里的 tokens → 本次快照 tokens」的**增量**作为该轮
/// 成本归因，所以这里只负责如实记录累计值，不负责拆分。
public struct EvolutionCostSnapshot: Codable, Equatable {
    public static let fileName = "evolution_cost.json"

    public let schemaVersion: Int
    public let threadId: String
    public let tokens: Int
    public let costUSD: Double?
    public let model: String?
    public let updatedAt: String

    public init(
        schemaVersion: Int = 1,
        threadId: String,
        tokens: Int,
        costUSD: Double? = nil,
        model: String? = nil,
        updatedAt: String
    ) {
        self.schemaVersion = schemaVersion
        self.threadId = threadId
        self.tokens = tokens
        self.costUSD = costUSD
        self.model = model
        self.updatedAt = updatedAt
    }

    /// 与 evolve.sh 其它运行态文件一致的目录约定。
    public static func stateDirectory(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home
            .appendingPathComponent("Library/Application Support/Tapgo AICoding/state", isDirectory: true)
    }

    public static func fileURL(stateDirectory: URL) -> URL {
        stateDirectory.appendingPathComponent(fileName)
    }

    public static func load(stateDirectory: URL) -> EvolutionCostSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(stateDirectory: stateDirectory)) else { return nil }
        return try? JSONDecoder().decode(EvolutionCostSnapshot.self, from: data)
    }

    /// 原子写入；失败返回 nil（成本归属不该影响主流程）。
    @discardableResult
    public static func write(
        tokens: Int,
        threadId: String,
        model: String? = nil,
        costUSD: Double? = nil,
        stateDirectory: URL,
        now: Date = Date()
    ) -> EvolutionCostSnapshot? {
        let snapshot = EvolutionCostSnapshot(
            threadId: threadId,
            tokens: tokens,
            costUSD: costUSD,
            model: model,
            updatedAt: ISO8601DateFormatter().string(from: now)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return nil }
        do {
            try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
            try data.write(to: fileURL(stateDirectory: stateDirectory), options: .atomic)
        } catch {
            return nil
        }
        return snapshot
    }
}
