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
    public let healthCheck: String?
    public let worktreeVerified: String?
    public let benchmarkScore: Int?
    /// EVO-036：单轮墙钟时长与可选 token/成本（state schema v3）。
    public let durationSeconds: Double?
    public let tokens: Int?
    public let costUSD: Double?

    public init(
        version: String, status: String, builtAt: String?, testStatus: String?,
        healthCheck: String? = nil, worktreeVerified: String? = nil, benchmarkScore: Int? = nil,
        durationSeconds: Double? = nil, tokens: Int? = nil, costUSD: Double? = nil
    ) {
        self.version = version
        self.status = status
        self.builtAt = builtAt
        self.testStatus = testStatus
        self.healthCheck = healthCheck
        self.worktreeVerified = worktreeVerified
        self.benchmarkScore = benchmarkScore
        self.durationSeconds = durationSeconds
        self.tokens = tokens
        self.costUSD = costUSD
    }
}

public struct EvolutionTestRunEntry: Equatable {
    public let status: String?
    public let failedSections: [String]
    public let reruns: [(section: String, passed: Bool)]
    public let environmentFailures: Int
    public let realFailures: Int

    public init(
        status: String?, failedSections: [String],
        reruns: [(section: String, passed: Bool)],
        environmentFailures: Int, realFailures: Int
    ) {
        self.status = status
        self.failedSections = failedSections
        self.reruns = reruns
        self.environmentFailures = environmentFailures
        self.realFailures = realFailures
    }

    public static func == (lhs: EvolutionTestRunEntry, rhs: EvolutionTestRunEntry) -> Bool {
        lhs.status == rhs.status && lhs.failedSections == rhs.failedSections
            && lhs.environmentFailures == rhs.environmentFailures
            && lhs.realFailures == rhs.realFailures
            && lhs.reruns.map { "\($0.section):\($0.passed)" } == rhs.reruns.map { "\($0.section):\($0.passed)" }
    }
}

public struct EvolutionCyclePoint: Equatable {
    public let version: String
    public let seconds: Double

    public init(version: String, seconds: Double) {
        self.version = version
        self.seconds = seconds
    }
}

public struct EvolutionIterationPoint: Equatable {
    public let version: String
    public let status: String
    public let date: String?

    public init(version: String, status: String, date: String?) {
        self.version = version
        self.status = status
        self.date = date
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
    public let healthPassedCount: Int
    public let healthFailedCount: Int
    public let worktreePassedCount: Int
    public let worktreeFailedCount: Int
    public let testRunCount: Int
    public let lastTestStatus: String?
    public let flakySections: [String]
    public let environmentFailureCount: Int
    public let realFailureCount: Int
    public let failureReasons: [String: Int]
    public let cyclePoints: [EvolutionCyclePoint]
    public let iterations: [EvolutionIterationPoint]
    public let lastBenchmarkScore: Int?
    public let modelEvalRuns: Int
    public let modelEvalLatestScore: Double?
    public let modelEvalBestScore: Double?
    public let rollbackDrillRuns: Int
    public let lastRollbackDrillTag: String?
    public let lastRollbackDrillPassed: Bool?
    public let maintenanceRuns: Int
    public let lastMaintenanceStatus: String?
    public let lastMaintenanceAt: String?
    /// EVO-036：周期长尾、失败恢复速度与单轮成本。
    public let p95CycleSeconds: Double?
    public let mttrMedianSeconds: Double?
    public let mttrSampleCount: Int
    public let unrecoveredFailureCount: Int
    public let runDurationSampleCount: Int
    public let runDurationMedianSeconds: Double?
    public let runDurationP95Seconds: Double?
    public let runTokensTotal: Int?
    public let runCostUSDTotal: Double?

    public init(
        recordCount: Int, iterationCount: Int, publishedCount: Int, failedCount: Int,
        successRate: Double?, medianCycleSeconds: Double?, cycleDurations: [Double],
        testPassedTotal: Int, testVersionCount: Int, openBacklog: Int, doneBacklog: Int,
        healthPassedCount: Int = 0, healthFailedCount: Int = 0,
        worktreePassedCount: Int = 0, worktreeFailedCount: Int = 0,
        testRunCount: Int = 0, lastTestStatus: String? = nil,
        flakySections: [String] = [], environmentFailureCount: Int = 0,
        realFailureCount: Int = 0, failureReasons: [String: Int] = [:],
        cyclePoints: [EvolutionCyclePoint] = [], iterations: [EvolutionIterationPoint] = [],
        lastBenchmarkScore: Int? = nil,
        modelEvalRuns: Int = 0,
        modelEvalLatestScore: Double? = nil,
        modelEvalBestScore: Double? = nil,
        rollbackDrillRuns: Int = 0,
        lastRollbackDrillTag: String? = nil,
        lastRollbackDrillPassed: Bool? = nil,
        maintenanceRuns: Int = 0,
        lastMaintenanceStatus: String? = nil,
        lastMaintenanceAt: String? = nil,
        p95CycleSeconds: Double? = nil,
        mttrMedianSeconds: Double? = nil,
        mttrSampleCount: Int = 0,
        unrecoveredFailureCount: Int = 0,
        runDurationSampleCount: Int = 0,
        runDurationMedianSeconds: Double? = nil,
        runDurationP95Seconds: Double? = nil,
        runTokensTotal: Int? = nil,
        runCostUSDTotal: Double? = nil
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
        self.healthPassedCount = healthPassedCount
        self.healthFailedCount = healthFailedCount
        self.worktreePassedCount = worktreePassedCount
        self.worktreeFailedCount = worktreeFailedCount
        self.testRunCount = testRunCount
        self.lastTestStatus = lastTestStatus
        self.flakySections = flakySections
        self.environmentFailureCount = environmentFailureCount
        self.realFailureCount = realFailureCount
        self.failureReasons = failureReasons
        self.cyclePoints = cyclePoints
        self.iterations = iterations
        self.lastBenchmarkScore = lastBenchmarkScore
        self.modelEvalRuns = modelEvalRuns
        self.modelEvalLatestScore = modelEvalLatestScore
        self.modelEvalBestScore = modelEvalBestScore
        self.rollbackDrillRuns = rollbackDrillRuns
        self.lastRollbackDrillTag = lastRollbackDrillTag
        self.lastRollbackDrillPassed = lastRollbackDrillPassed
        self.maintenanceRuns = maintenanceRuns
        self.lastMaintenanceStatus = lastMaintenanceStatus
        self.lastMaintenanceAt = lastMaintenanceAt
        self.p95CycleSeconds = p95CycleSeconds
        self.mttrMedianSeconds = mttrMedianSeconds
        self.mttrSampleCount = mttrSampleCount
        self.unrecoveredFailureCount = unrecoveredFailureCount
        self.runDurationSampleCount = runDurationSampleCount
        self.runDurationMedianSeconds = runDurationMedianSeconds
        self.runDurationP95Seconds = runDurationP95Seconds
        self.runTokensTotal = runTokensTotal
        self.runCostUSDTotal = runCostUSDTotal
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
    public static let failedStatuses: Set<String> = [
        "push_failed", "release_failed", "health_failed",
        "worktree_verify_failed", "benchmark_regressed", "canary_failed",
    ]

    public static func compute(
        records: [EvolutionRecordEntry],
        history: [EvolutionHistoryEntry],
        backlogText: String,
        testRuns: [EvolutionTestRunEntry] = []
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
        let median = Self.median(durations)
        let p95Cycle = Self.percentile(durations, 0.95)

        // MTTR：失败状态 → 其后第一个终端成功（同版本 --resume 续跑，或下一版发布）。
        var ordered: [(date: Date, status: String)] = []
        for entry in history {
            if let raw = entry.builtAt, let date = formatter.date(from: raw) {
                ordered.append((date, entry.status))
            }
        }
        ordered.sort { $0.date < $1.date }
        var mttrValues: [Double] = []
        var unrecoveredFailures = 0
        for (index, row) in ordered.enumerated() where failedStatuses.contains(row.status) {
            if let recovered = ordered[(index + 1)...].first(where: { terminalStatuses.contains($0.status) }) {
                mttrValues.append(recovered.date.timeIntervalSince(row.date))
            } else {
                unrecoveredFailures += 1
            }
        }

        // 单轮墙钟时长与可选 token/成本（同一版本多次运行取最后一次）。
        var runDurations: [Double] = []
        var runTokens: [Int] = []
        var runCosts: [Double] = []
        for entry in finalEntries {
            if let duration = entry.durationSeconds { runDurations.append(duration) }
            if let tokens = entry.tokens { runTokens.append(tokens) }
            if let cost = entry.costUSD { runCosts.append(cost) }
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

        let healthPassed = finalEntries.filter { $0.healthCheck == "passed" }.count
        let healthFailed = finalEntries.filter { $0.healthCheck == "failed" }.count
        let worktreePassed = finalEntries.filter { $0.worktreeVerified == "yes" }.count
        let worktreeFailed = finalEntries.filter { $0.status == "worktree_verify_failed" }.count

        var reasons: [String: Int] = [:]
        for entry in finalEntries where failedStatuses.contains(entry.status) {
            reasons[entry.status, default: 0] += 1
        }

        var flakySections: [String] = []
        for run in testRuns {
            let failed = Set(run.failedSections)
            for rerun in run.reruns where failed.contains(rerun.section) && rerun.passed {
                flakySections.append(rerun.section)
            }
        }
        flakySections = Array(Set(flakySections)).sorted()

        var points: [EvolutionCyclePoint] = []
        for index in 1..<terminalTimes.count {
            points.append(EvolutionCyclePoint(
                version: terminalTimes[index].version,
                seconds: terminalTimes[index].date.timeIntervalSince(terminalTimes[index - 1].date)
            ))
        }
        let iterations = finalEntries
            .sorted { ($0.builtAt ?? "") < ($1.builtAt ?? "") }
            .suffix(12)
            .map { EvolutionIterationPoint(version: $0.version, status: $0.status, date: $0.builtAt) }

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
            doneBacklog: doneBacklog,
            healthPassedCount: healthPassed,
            healthFailedCount: healthFailed,
            worktreePassedCount: worktreePassed,
            worktreeFailedCount: worktreeFailed,
            testRunCount: testRuns.count,
            lastTestStatus: testRuns.last?.status,
            flakySections: flakySections,
            environmentFailureCount: testRuns.reduce(0) { $0 + $1.environmentFailures },
            realFailureCount: testRuns.reduce(0) { $0 + $1.realFailures },
            failureReasons: reasons,
            cyclePoints: points,
            iterations: iterations,
            lastBenchmarkScore: finalEntries
                .filter { $0.benchmarkScore != nil }
                .sorted { ($0.builtAt ?? "") < ($1.builtAt ?? "") }
                .last?.benchmarkScore,
            p95CycleSeconds: p95Cycle,
            mttrMedianSeconds: Self.median(mttrValues),
            mttrSampleCount: mttrValues.count,
            unrecoveredFailureCount: unrecoveredFailures,
            runDurationSampleCount: runDurations.count,
            runDurationMedianSeconds: Self.median(runDurations),
            runDurationP95Seconds: Self.percentile(runDurations, 0.95),
            runTokensTotal: runTokens.isEmpty ? nil : runTokens.reduce(0, +),
            runCostUSDTotal: runCosts.isEmpty ? nil : runCosts.reduce(0, +)
        )
    }

    /// 线性插值分位数；空数组返回 nil。
    static func percentile(_ values: [Double], _ fraction: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        if sorted.count == 1 { return sorted[0] }
        let position = Double(sorted.count - 1) * fraction
        let low = Int(position)
        let high = min(low + 1, sorted.count - 1)
        return sorted[low] + (sorted[high] - sorted[low]) * (position - Double(low))
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
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
                testStatus: object["testStatus"] as? String,
                healthCheck: object["healthCheck"] as? String,
                worktreeVerified: object["worktreeVerified"] as? String,
                benchmarkScore: object["benchmarkScore"] as? Int,
                durationSeconds: (object["durationSeconds"] as? NSNumber)?.doubleValue,
                tokens: (object["tokens"] as? NSNumber)?.intValue,
                costUSD: (object["costUSD"] as? NSNumber)?.doubleValue
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

    public static func parseTestRuns(_ text: String) -> [EvolutionTestRunEntry] {
        var entries: [EvolutionTestRunEntry] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let failedSections = (object["failedSections"] as? [[String: Any]] ?? [])
                .compactMap { $0["section"] as? String }
            var reruns: [(String, Bool)] = []
            for item in object["reruns"] as? [[String: Any]] ?? [] {
                if let section = item["section"] as? String, let passed = item["passed"] as? Bool {
                    reruns.append((section, passed))
                }
            }
            entries.append(EvolutionTestRunEntry(
                status: object["status"] as? String,
                failedSections: failedSections,
                reruns: reruns,
                environmentFailures: object["environmentFailures"] as? Int ?? 0,
                realFailures: object["realFailures"] as? Int ?? 0
            ))
        }
        return entries
    }

    public static func parseModelEval(_ text: String) -> [Double] {
        var scores: [Double] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let score = object["score"] as? Double else { continue }
            scores.append(score)
        }
        return scores
    }

    /// 解析 JSONL 文件为对象数组；空行与损坏行直接跳过。
    public static func jsonLines(in url: URL) -> [[String: Any]] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: .newlines).compactMap { line -> [String: Any]? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
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
        let testHistoryText = (try? String(contentsOf: stateDirectory.appendingPathComponent("test_run_history.jsonl"), encoding: .utf8)) ?? ""
        let modelEvalText = (try? String(contentsOf: stateDirectory.appendingPathComponent("model_eval_history.jsonl"), encoding: .utf8)) ?? ""
        let modelScores = parseModelEval(modelEvalText)
        let rollbackRecords = jsonLines(in: stateDirectory.appendingPathComponent("rollback_drill_history.jsonl"))
        let lastRollback = rollbackRecords.last
        let maintenanceRecords = jsonLines(in: stateDirectory.appendingPathComponent("maintenance_history.jsonl"))
        let lastMaintenance = maintenanceRecords.last
        var snapshot = compute(
            records: records,
            history: parseHistory(historyText),
            backlogText: backlogText,
            testRuns: parseTestRuns(testHistoryText)
        )
        snapshot = EvolutionMetricsSnapshot(
            recordCount: snapshot.recordCount, iterationCount: snapshot.iterationCount,
            publishedCount: snapshot.publishedCount, failedCount: snapshot.failedCount,
            successRate: snapshot.successRate, medianCycleSeconds: snapshot.medianCycleSeconds,
            cycleDurations: snapshot.cycleDurations, testPassedTotal: snapshot.testPassedTotal,
            testVersionCount: snapshot.testVersionCount, openBacklog: snapshot.openBacklog,
            doneBacklog: snapshot.doneBacklog, healthPassedCount: snapshot.healthPassedCount,
            healthFailedCount: snapshot.healthFailedCount, worktreePassedCount: snapshot.worktreePassedCount,
            worktreeFailedCount: snapshot.worktreeFailedCount, testRunCount: snapshot.testRunCount,
            lastTestStatus: snapshot.lastTestStatus, flakySections: snapshot.flakySections,
            environmentFailureCount: snapshot.environmentFailureCount,
            realFailureCount: snapshot.realFailureCount, failureReasons: snapshot.failureReasons,
            cyclePoints: snapshot.cyclePoints, iterations: snapshot.iterations,
            lastBenchmarkScore: snapshot.lastBenchmarkScore,
            modelEvalRuns: modelScores.count,
            modelEvalLatestScore: modelScores.last,
            modelEvalBestScore: modelScores.max(),
            rollbackDrillRuns: rollbackRecords.count,
            lastRollbackDrillTag: lastRollback?["tag"] as? String,
            lastRollbackDrillPassed: lastRollback?["passed"] as? Bool,
            maintenanceRuns: maintenanceRecords.count,
            lastMaintenanceStatus: lastMaintenance?["status"] as? String,
            lastMaintenanceAt: lastMaintenance?["ranAt"] as? String,
            p95CycleSeconds: snapshot.p95CycleSeconds,
            mttrMedianSeconds: snapshot.mttrMedianSeconds,
            mttrSampleCount: snapshot.mttrSampleCount,
            unrecoveredFailureCount: snapshot.unrecoveredFailureCount,
            runDurationSampleCount: snapshot.runDurationSampleCount,
            runDurationMedianSeconds: snapshot.runDurationMedianSeconds,
            runDurationP95Seconds: snapshot.runDurationP95Seconds,
            runTokensTotal: snapshot.runTokensTotal,
            runCostUSDTotal: snapshot.runCostUSDTotal
        )
        return snapshot
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
