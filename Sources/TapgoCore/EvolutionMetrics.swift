import Foundation

/// 自进化运行态指标（TapgoCore 纯逻辑，App 与测试共用）。
///
/// 数据源：
///   - `evolution/versions/v*.json`（结构化版本记录）
///   - `evolution_state_history.jsonl`（每次状态迁移一行）
///   - `evolution/BACKLOG.md`（未完成/已完成项计数）
///
/// 指标用于 App 内“自进化日志”顶部的紧凑看板；不引入网络或数据库。
public struct EvolutionRecordEntry: Equatable {
    public let version: String
    public let date: String?
    public let testStatus: String?

    public init(version: String, date: String?, testStatus: String?) {
        self.version = version
        self.date = date
        self.testStatus = testStatus
    }
}

public struct EvolutionHistoryEntry: Equatable {
    public let version: String
    public let status: String
    public let builtAt: String?
    public let testStatus: String?

    public init(version: String, status: String, builtAt: String?, testStatus: String?) {
        self.version = version
        self.status = status
        self.builtAt = builtAt
        self.testStatus = testStatus
    }
}

public struct EvolutionMetricsSnapshot: Equatable {
    public let recordCount: Int
    public let iterationCount: Int
    public let publishedCount: Int
    public let failedCount: Int
    public let successRate: Double?
    public let medianCycleSeconds: Double?
    public let cycleDurations: [Double]
    public let testPassedTotal: Int
    public let testVersionCount: Int
    public let openBacklog: Int
    public let doneBacklog: Int

    public init(
        recordCount: Int, iterationCount: Int, publishedCount: Int, failedCount: Int,
        successRate: Double?, medianCycleSeconds: Double?, cycleDurations: [Double],
        testPassedTotal: Int, testVersionCount: Int, openBacklog: Int, doneBacklog: Int
    ) {
        self.recordCount = recordCount
        self.iterationCount = iterationCount
        self.publishedCount = publishedCount
        self.failedCount = failedCount
        self.successRate = successRate
        self.medianCycleSeconds = medianCycleSeconds
        self.cycleDurations = cycleDurations
        self.testPassedTotal = testPassedTotal
        self.testVersionCount = testVersionCount
        self.openBacklog = openBacklog
        self.doneBacklog = doneBacklog
    }

    public var hasData: Bool { recordCount > 0 || iterationCount > 0 }

    public static let empty = EvolutionMetricsSnapshot(
        recordCount: 0, iterationCount: 0, publishedCount: 0, failedCount: 0,
        successRate: nil, medianCycleSeconds: nil, cycleDurations: [],
        testPassedTotal: 0, testVersionCount: 0, openBacklog: 0, doneBacklog: 0
    )
}

public enum EvolutionMetrics {
    public static let terminalStatuses: Set<String> = ["published", "local_built"]
    public static let failedStatuses: Set<String> = ["push_failed", "release_failed", "health_failed"]

    public static func compute(
        records: [EvolutionRecordEntry],
        history: [EvolutionHistoryEntry],
        backlogText: String
    ) -> EvolutionMetricsSnapshot {
        // 同一版本多次状态迁移时，最后一条生效。
        var finalByVersion: [String: EvolutionHistoryEntry] = [:]
        for entry in history where !entry.version.isEmpty {
            finalByVersion[entry.version] = entry
        }
        let finalEntries = Array(finalByVersion.values)
        let published = finalEntries.filter { terminalStatuses.contains($0.status) }.count
        let failed = finalEntries.filter { failedStatuses.contains($0.status) }.count
        let denominator = published + failed
        let successRate = denominator > 0 ? Double(published) / Double(denominator) : nil

        var terminalTimes: [(date: Date, version: String)] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        for entry in finalEntries where terminalStatuses.contains(entry.status) {
            if let raw = entry.builtAt, let date = formatter.date(from: raw) {
                terminalTimes.append((date, entry.version))
            }
        }
        terminalTimes.sort { $0.date < $1.date }
        var durations: [Double] = []
        for index in 1..<terminalTimes.count {
            durations.append(terminalTimes[index].date.timeIntervalSince(terminalTimes[index - 1].date))
        }
        let median: Double?
        if durations.isEmpty {
            median = nil
        } else {
            let sorted = durations.sorted()
            let mid = sorted.count / 2
            median = sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        }

        var testTotal = 0
        var testVersions = 0
        for entry in finalEntries {
            let passed = passedCount(in: entry.testStatus)
            if passed > 0 {
                testTotal += passed
                testVersions += 1
            }
        }

        let openBacklog = countMatches(in: backlogText, pattern: #"^\s*-\s*\[ \]"#)
        let doneBacklog = countMatches(in: backlogText, pattern: #"^\s*-\s*\[[xX]\]"#)

        return EvolutionMetricsSnapshot(
            recordCount: records.count,
            iterationCount: finalEntries.count,
            publishedCount: published,
            failedCount: failed,
            successRate: successRate,
            medianCycleSeconds: median,
            cycleDurations: durations,
            testPassedTotal: testTotal,
            testVersionCount: testVersions,
            openBacklog: openBacklog,
            doneBacklog: doneBacklog
        )
    }

    public static func parseHistory(_ text: String) -> [EvolutionHistoryEntry] {
        var entries: [EvolutionHistoryEntry] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = object["version"] as? String,
                  let status = object["status"] as? String else { continue }
            entries.append(EvolutionHistoryEntry(
                version: version,
                status: status,
                builtAt: object["builtAt"] as? String,
                testStatus: object["testStatus"] as? String
            ))
        }
        return entries
    }

    public static func parseRecords(directory: URL) -> [EvolutionRecordEntry] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        var records: [EvolutionRecordEntry] = []
        for url in files where url.pathExtension == "json" && url.lastPathComponent.hasPrefix("v") {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = object["version"] as? String else { continue }
            records.append(EvolutionRecordEntry(
                version: version,
                date: object["date"] as? String,
                testStatus: object["testStatus"] as? String
            ))
        }
        return records.sorted { $0.version.localizedStandardCompare($1.version) == .orderedAscending }
    }

    public static func load(projectRoot: URL, stateDirectory: URL) -> EvolutionMetricsSnapshot {
        let records = parseRecords(directory: projectRoot.appendingPathComponent("evolution/versions"))
        let historyURL = stateDirectory.appendingPathComponent("evolution_state_history.jsonl")
        let historyText: String
        if let text = try? String(contentsOf: historyURL, encoding: .utf8) {
            historyText = text
        } else if let state = try? String(contentsOf: stateDirectory.appendingPathComponent("evolution_state.json"), encoding: .utf8) {
            historyText = state
        } else {
            historyText = ""
        }
        let backlogText = (try? String(contentsOf: projectRoot.appendingPathComponent("evolution/BACKLOG.md"), encoding: .utf8)) ?? ""
        return compute(records: records, history: parseHistory(historyText), backlogText: backlogText)
    }

    private static func passedCount(in testStatus: String?) -> Int {
        guard let text = testStatus,
              let regex = try? NSRegularExpression(pattern: #"(\d+)\s+passed"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return 0 }
        return Int(text[range]) ?? 0
    }

    private static func countMatches(in text: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
