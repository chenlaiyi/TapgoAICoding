import Foundation

/// 自进化指标摘要（`evolution-metrics.py --out` 写入
/// `state/evolution_metrics_summary.json`，App 与手机端只读）。
///
/// 真源是 Python 指标工具；这里只做宽容解析，避免三处重复实现计算口径。
/// 缺文件/缺字段都返回 nil 或默认值，绝不影响界面其它部分。
public struct EvolutionMetricsSummary: Codable, Equatable {
    public static let fileName = "evolution_metrics_summary.json"

    public let latestVersion: String?
    public let successRate: Double?
    public let medianCycleSeconds: Double?
    public let p95CycleSeconds: Double?
    public let mttrMedianSeconds: Double?
    public let mttrSampleCount: Int
    public let unrecoveredFailureCount: Int
    public let runDurationMedianSeconds: Double?
    public let runDurationP95Seconds: Double?
    public let runTokensTotal: Int?
    public let runCostUSDTotal: Double?
    public let localAppRunning: String?
    public let localAppInstalled: String?
    public let localAppStale: Bool?

    public init(
        latestVersion: String? = nil,
        successRate: Double? = nil,
        medianCycleSeconds: Double? = nil,
        p95CycleSeconds: Double? = nil,
        mttrMedianSeconds: Double? = nil,
        mttrSampleCount: Int = 0,
        unrecoveredFailureCount: Int = 0,
        runDurationMedianSeconds: Double? = nil,
        runDurationP95Seconds: Double? = nil,
        runTokensTotal: Int? = nil,
        runCostUSDTotal: Double? = nil,
        localAppRunning: String? = nil,
        localAppInstalled: String? = nil,
        localAppStale: Bool? = nil
    ) {
        self.latestVersion = latestVersion
        self.successRate = successRate
        self.medianCycleSeconds = medianCycleSeconds
        self.p95CycleSeconds = p95CycleSeconds
        self.mttrMedianSeconds = mttrMedianSeconds
        self.mttrSampleCount = mttrSampleCount
        self.unrecoveredFailureCount = unrecoveredFailureCount
        self.runDurationMedianSeconds = runDurationMedianSeconds
        self.runDurationP95Seconds = runDurationP95Seconds
        self.runTokensTotal = runTokensTotal
        self.runCostUSDTotal = runCostUSDTotal
        self.localAppRunning = localAppRunning
        self.localAppInstalled = localAppInstalled
        self.localAppStale = localAppStale
    }

    public var hasData: Bool {
        successRate != nil || p95CycleSeconds != nil || runDurationMedianSeconds != nil
    }

    public static func parse(_ text: String) -> EvolutionMetricsSummary? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let latest = object["latestRecord"] as? [String: Any]
        let localApp = object["localApp"] as? [String: Any]
        return EvolutionMetricsSummary(
            latestVersion: latest?["version"] as? String,
            successRate: object["successRate"] as? Double,
            medianCycleSeconds: object["medianCycleSeconds"] as? Double,
            p95CycleSeconds: object["p95CycleSeconds"] as? Double,
            mttrMedianSeconds: object["mttrMedianSeconds"] as? Double,
            mttrSampleCount: object["mttrSamples"] as? Int ?? 0,
            unrecoveredFailureCount: object["unrecoveredFailures"] as? Int ?? 0,
            runDurationMedianSeconds: object["runDurationMedianSeconds"] as? Double,
            runDurationP95Seconds: object["runDurationP95Seconds"] as? Double,
            runTokensTotal: object["runTokensTotal"] as? Int,
            runCostUSDTotal: object["runCostUSDTotal"] as? Double,
            localAppRunning: localApp?["running"] as? String,
            localAppInstalled: localApp?["installed"] as? String,
            localAppStale: localApp?["stale"] as? Bool
        )
    }

    public static func load(stateDirectory: URL) -> EvolutionMetricsSummary? {
        let url = stateDirectory.appendingPathComponent(fileName)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }
}
