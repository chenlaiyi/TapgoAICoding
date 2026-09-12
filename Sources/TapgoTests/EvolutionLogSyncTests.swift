import Foundation

/// 守住版本日志的三个不变量：
///   1. makeHistory() 中每个现代版本都能在 EVOLUTION.md 找到；
///   2. EVOLUTION.md 最新 10 个版本必须都已进入 makeHistory()（防止只改日志漏改 UI）；
///   3. Mac 0.x 系列版本节不允许重复，且最新 10 条在 makeHistory 中保持倒序。
///
/// 旧版（v<0.5.5）历史 backlog 不参与双向校验，避免为远古数据补录。
@MainActor
func runEvolutionLogSync(_ t: TestRunner) {
    func readFile(_ relativePath: String) -> String {
        let root = FileManager.default.currentDirectoryPath
        return (try? String(contentsOfFile: root + "/" + relativePath, encoding: .utf8)) ?? ""
    }

    let evo = readFile("EVOLUTION.md")
    let view = readFile("Sources/TapgoAICoding/Views/EvolutionLogView.swift")

    // EVOLUTION.md 版本节保持文件顺序（最新在前）。
    var orderedEvoVersions: [String] = []
    var duplicateMacVersions: [String] = []
    var seenMacVersions = Set<String>()
    for rawLine in evo.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(rawLine)
        guard line.hasPrefix("## v") else { continue }
        let header = String(line.dropFirst(3))
        guard let version = header.split(separator: " ").first.map(String.init),
              version.range(of: "^v\\d+\\.\\d+\\.\\d+$", options: .regularExpression) != nil else { continue }
        // iOS 1.0.x 独立序列，不参与 Mac 版本/重复/顺序校验。
        if header.contains("(iOS)") { continue }
        orderedEvoVersions.append(version)

        // Mac 0.x 系列版本节必须全局唯一。v0.5.70/71/102/106/107/230/232
        // 的历史重复节已在 v0.5.260 清理；iOS 1.0.x 独立序列不在此约束内。
        if version.hasPrefix("v0."), header.contains(" — "),
           !seenMacVersions.insert(version).inserted {
            duplicateMacVersions.append(version)
        }
    }
    let evoVersions = Set(orderedEvoVersions)

    // makeHistory 数组内所有 vX.Y.Z 版本。
    let viewVersionsOrdered = view.components(separatedBy: "\"").compactMap { token -> String? in
        guard token.hasPrefix("v"), token.contains(".") else { return nil }
        let head = String(token.prefix(while: { $0 != "\"" }))
        return head.range(of: "^v\\d+\\.\\d+\\.\\d+$", options: .regularExpression) != nil ? head : nil
    }
    let viewVersions = Set(viewVersionsOrdered)

    func isModern(_ version: String) -> Bool {
        let parts = version.dropFirst().split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        return (parts[0], parts[1], parts[2]) >= (0, 5, 5)
    }

    let rootPath = FileManager.default.currentDirectoryPath
    let iosLog = (try? String(contentsOfFile: rootPath + "/evolution/ios/EVOLUTION.md", encoding: .utf8)) ?? ""
    t.expect(!evo.contains("## v1."), "evolution-sync: 主日志不得含 iOS 版本节")
    t.expect(evo.contains("## iOS 版本序列"), "evolution-sync: 主日志必须指向 iOS 独立序列")
    t.expect(iosLog.contains("## v1.0.0 (iOS)"), "evolution-sync: iOS 日志含 v1.0.0")
    t.expect(iosLog.contains("## v1.0.1 (iOS)"), "evolution-sync: iOS 日志含 v1.0.1")

    let archiveLog = (try? String(contentsOfFile: rootPath + "/evolution/archive/EVOLUTION-pre-0.5.5.md", encoding: .utf8)) ?? ""
    let oldMainVersions = orderedEvoVersions.filter { version in
        let parts = version.dropFirst().split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        return (parts[0], parts[1], parts[2]) < (0, 5, 5)
    }
    t.expect(oldMainVersions.isEmpty, "evolution-sync: 主日志不得含 v0.5.5 之前版本（实际 \(oldMainVersions)）")
    t.expect(archiveLog.contains("## v0.5.4"), "evolution-sync: 归档含 v0.5.4")
    t.expect(archiveLog.contains("## v0.3.0"), "evolution-sync: 归档含 v0.3.0")
    let archiveVersionCount = archiveLog.components(separatedBy: .newlines)
        .filter { $0.hasPrefix("## v") }.count
    t.expect(archiveVersionCount >= 10, "evolution-sync: 归档至少含 10 个版本节（实际 \(archiveVersionCount)）")

    t.expect(!evoVersions.isEmpty, "evolution-sync: EVOLUTION.md 解析到至少 1 个版本")
    t.expect(!viewVersions.isEmpty, "evolution-sync: makeHistory 解析到至少 1 个版本")
    t.expect(duplicateMacVersions.isEmpty,
             "evolution-sync: Mac 0.x 版本节不得重复（重复 \(duplicateMacVersions.sorted())）")

    // 方向一：makeHistory -> EVOLUTION.md，不能引用不存在的日志。
    let missingInEvo = viewVersions.filter(isModern).subtracting(evoVersions)
    t.expect(missingInEvo.isEmpty,
             "evolution-sync: makeHistory 中 v≥0.5.5 的条目 EVOLUTION.md 必须有（实际缺 \(missingInEvo.sorted())）")

    // 方向二：EVOLUTION.md 最新 10 个版本 -> makeHistory，不能漏进 UI。
    let latestTen = Array(orderedEvoVersions.filter(isModern).prefix(10))
    let missingInView = latestTen.filter { !viewVersions.contains($0) }
    t.expect(latestTen.count == 10, "evolution-sync: EVOLUTION.md 至少含 10 个现代版本")
    t.expect(missingInView.isEmpty,
             "evolution-sync: EVOLUTION.md 最新 10 个版本必须进入 makeHistory（实际缺 \(missingInView)）")

    // 方向四：结构化记录（v0.5.258 起）必须同时出现在 EVOLUTION.md 与 makeHistory。
    let recordsDir = FileManager.default.currentDirectoryPath + "/evolution/versions"
    let recordFiles = (try? FileManager.default.contentsOfDirectory(atPath: recordsDir)) ?? []
    var recordVersions: [String] = []
    for file in recordFiles where file.hasPrefix("v") && file.hasSuffix(".json") {
        let path = recordsDir + "/" + file
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? String,
              let tag = object["tag"] as? String else {
            t.expect(false, "evolution-records: 无法解析 \(file)")
            continue
        }
        recordVersions.append(version)
        t.expectEqual(tag, "v\(version)", "evolution-records: tag 与 version 一致 (\(file))")
        t.expect(evoVersions.contains("v\(version)"),
                 "evolution-records: v\(version) 必须有 EVOLUTION.md 小节")
        t.expect(viewVersions.contains("v\(version)"),
                 "evolution-records: v\(version) 必须进入 makeHistory")
    }
    t.expectEqual(Set(recordVersions).count, recordVersions.count,
                  "evolution-records: 版本记录不得重复")

    // 方向三：最新 10 条在 makeHistory 源码中保持倒序。
    let positions = latestTen.compactMap { version -> Int? in
        view.range(of: "\"\(version)\"")?.lowerBound.utf16Offset(in: view)
    }
    t.expectEqual(positions.count, latestTen.count, "evolution-sync: 最新 10 个版本定位成功")
    if positions.count == latestTen.count {
        t.expect(positions == positions.sorted(),
                 "evolution-sync: 最新 10 个版本在 makeHistory 中必须倒序（最新在前）")
    }
}
