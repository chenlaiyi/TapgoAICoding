import Foundation
import TapgoCore

/// EVO-053：H5（app.js）与 App（PhoneRemote.EvolutionStatus）之间的字段契约。
///
/// 风险模式：Swift 侧改名/删字段，H5 只是少显示一块，谁也不报错。这里把
/// 「App 真实序列化出来的 JSON」与「app.js 真实读取的键」对照：
///   * app.js 读的键必须都存在（少一个就失败，列出缺哪些）；
///   * JSON 里未被 H5 读取的键必须落在白名单里（改名导致的"用了新键、旧键废弃"
///     不会静默通过）。
@MainActor
func runEvolutionH5Contract(_ t: TestRunner) {
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let appJSPath = repoRoot.appendingPathComponent("Sources/TapgoCore/Resources/PhoneRemote/app.js")
    guard let appJS = try? String(contentsOf: appJSPath, encoding: .utf8), !appJS.isEmpty else {
        t.expect(false, "h5-contract: app.js 不可读")
        return
    }

    let funnel = FeedbackFunnelSnapshot(
        generatedAt: "2026-09-13T00:00:00Z",
        draftsTotal: 5, draftsOpen: 2, draftsStale: 1,
        registeredTotal: 6, shippedTotal: 5, registeredStale: 0,
        draftToRegisteredRate: 0.4, registeredToShippedRate: 0.8333,
        registeredToShippedMedianDays: 12.5, unknownReleaseDate: 1
    )
    let summary = EvolutionMetricsSummary(
        latestVersion: "0.5.311", successRate: 0.98, medianCycleSeconds: 900,
        p95CycleSeconds: 1163.8, mttrMedianSeconds: 86400, mttrSampleCount: 3,
        unrecoveredFailureCount: 1, runDurationMedianSeconds: 497,
        runDurationP95Seconds: 520, runTokensTotal: 12000, runCostUSDTotal: 1.25,
        localAppRunning: "0.5.299", localAppInstalled: "0.5.311", localAppStale: true
    )
    let evolution = PhoneRemote.EvolutionStatus(
        version: "0.5.311", phase: "deploy", phaseIndex: 7, phaseCount: 9,
        status: "running", message: "三机部署中",
        benchmarkScore: 100, modelEvalBestScore: 88,
        backlogOpen: 3, backlogTop: "EVO-999 下一项",
        updatedAt: "2026-09-13T00:00:00Z",
        rollbackDrillRuns: 2, lastRollbackDrillTag: "v0.5.307",
        lastRollbackDrillPassed: true, lastRollbackDrillAt: "2026-09-13T01:00:00Z",
        maintenanceRuns: 4, lastMaintenanceStatus: "ok", lastMaintenanceAt: "2026-09-13T02:00:00Z",
        funnel: funnel, metricsSummary: summary
    )
    let snapshot = PhoneRemote.buildState(
        threads: [], activeId: nil, rev: 1, hostname: "h5-contract-host",
        appVersion: "0.5.311", evolution: evolution
    )
    let data = PhoneRemote.stateJSON(snapshot)
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let encoded = root["evolution"] as? [String: Any] else {
        t.expect(false, "h5-contract: 快照里没有 evolution 对象")
        return
    }
    let jsonKeys = Set(encoded.keys)
    t.expect(jsonKeys.count >= 15, "h5-contract: evolution 字段数 ≥ 15（实际 \(jsonKeys.count)）")

    // app.js 顶层读取的键
    let pattern = try! NSRegularExpression(pattern: #"evo\.([A-Za-z_][A-Za-z0-9_]*)"#)
    let range = NSRange(appJS.startIndex..., in: appJS)
    let used = Set(pattern.matches(in: appJS, range: range).compactMap { match -> String? in
        guard let r = Range(match.range(at: 1), in: appJS) else { return nil }
        return String(appJS[r])
    })
    t.expect(used.count >= 10, "h5-contract: app.js 读取的字段数 ≥ 10（实际 \(used.count)）")

    let missing = used.subtracting(jsonKeys).sorted()
    t.expect(missing.isEmpty, "h5-contract: app.js 读取的键必须都在序列化结果里，缺失 \(missing)")

    // 白名单：序列化里有、但 H5 当前不读（给 App 内其它消费者或保留字段）
    let allowUnused: Set<String> = ["schemaVersion", "message", "updatedAt", "canary"]
    let unused = jsonKeys.subtracting(used).sorted()
    let unexpected = Set(unused).subtracting(allowUnused).sorted()
    t.expect(unexpected.isEmpty, "h5-contract: 未被 H5 读取的键必须在白名单内，意外字段 \(unexpected)")

    // 嵌套对象：H5 读的是点号路径，这里双向断言——(i) 序列化结果里该路径存在，
    // (ii) app.js 里确实使用了这条路径。任何一侧改形状都会被抓住。
    func resolve(_ path: String, in object: [String: Any]) -> Any? {
        var current: Any? = object
        for part in path.split(separator: ".") {
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[String(part)]
        }
        return current
    }
    guard let funnelObject = encoded["funnel"] as? [String: Any] else {
        t.expect(false, "h5-contract: funnel 未序列化")
        return
    }
    // 序列化路径 ↔ app.js 里实际读取的表达式（app.js 用中间变量读嵌套字段）
    let funnelContract: [(path: String, expression: String)] = [
        ("drafts.total", "fDrafts.total"),
        ("drafts.open", "fDrafts.open"),
        ("registered.total", "fRegistered.total"),
        ("registered.shipped", "fRegistered.shipped"),
        ("conversion.registeredToShipped", "fConversion.registeredToShipped"),
    ]
    let missingFunnel = funnelContract.map(\.path).filter { resolve($0, in: funnelObject) == nil }
    t.expect(missingFunnel.isEmpty, "h5-contract: funnel 缺路径 \(missingFunnel)")
    let notReferenced = funnelContract.filter { !appJS.contains($0.expression) }.map(\.path)
    t.expect(notReferenced.isEmpty, "h5-contract: app.js 未使用已序列化的 funnel 路径 \(notReferenced)")

    let metricsKeys = Set((encoded["metricsSummary"] as? [String: Any])?.keys ?? [:].keys)
    let missingMetrics = Set([
        "p95CycleSeconds", "mttrMedianSeconds", "runDurationMedianSeconds",
        "runTokensTotal", "runCostUSDTotal", "localAppStale", "localAppRunning",
    ]).subtracting(metricsKeys).sorted()
    t.expect(missingMetrics.isEmpty, "h5-contract: metricsSummary 缺字段 \(missingMetrics)")

    // 值本身也要真的过河（不是空对象）
    let metrics = encoded["metricsSummary"] as? [String: Any]
    t.expectEqual(metrics?["p95CycleSeconds"] as? Double, 1163.8, "h5-contract: p95 值透传")
    let funnelConversion = (encoded["funnel"] as? [String: Any])?["conversion"] as? [String: Any]
    t.expectEqual(funnelConversion?["registeredToShipped"] as? Double, 0.8333,
                  "h5-contract: 漏斗转化率透传")
    t.expectEqual(encoded["backlogOpen"] as? Int, 3, "h5-contract: backlog 计数透传")
    t.expectEqual((metrics?["localAppStale"] as? Bool), true, "h5-contract: 本机漂移标记透传")
}
