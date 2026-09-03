import Foundation
@testable import TapgoAICoding

/// 守住"makeHistory() 不能明显落后于 EVOLUTION.md"：两个源的版本列表
/// 必须有交集（交集少于 5 条即视为维护疏漏）。该测试在每次 release 前
/// 都应通过 — 如发现失败，先看 `Sources/TapgoAICoding/Views/EvolutionLogView.swift`
/// 的 `makeHistory()` 是否漏 preprend 新版本条目。

@MainActor
func runEvolutionLogSync(_ t: TestRunner) {
    func readFile(_ relativePath: String) -> String {
        let root = FileManager.default.currentDirectoryPath
        return (try? String(contentsOfFile: root + "/" + relativePath, encoding: .utf8)) ?? ""
    }

    let evo = readFile("EVOLUTION.md")
    let view = readFile("Sources/TapgoAICoding/Views/EvolutionLogView.swift")

    // 抓 EVOLUTION.md 里所有 vX.Y.Z 段
    let evoVersions = Set(
        evo.split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { (line: Substring) -> String? in
                let s = String(line)
                if s.hasPrefix("## v") { return String(s.dropFirst(3).split(separator: " ")[0]) }
                return nil
            }
    )

    // 抓 makeHistory 数组里所有 "vX.Y.Z" 字符串
    let viewVersions = Set(
        view.components(separatedBy: "\"").compactMap { (token: String) -> String? in
            if token.hasPrefix("v") && token.contains(".") {
                let head = String(token.prefix(while: { $0 != "\"" }))
                if head.range(of: "^v\\d+\\.\\d+\\.\\d+$", options: .regularExpression) != nil {
                    return head
                }
            }
            return nil
        }
    )

    t.expect(!evoVersions.isEmpty, "evolution-sync: EVOLUTION.md 解析到至少 1 个版本")
    t.expect(!viewVersions.isEmpty, "evolution-sync: makeHistory 解析到至少 1 个版本")
    // 兼容：makeHistory 里 v<0.5.5 是 EVOLUTION 重建前的历史 backlog，忽略；
    // v≥0.5.5 的条目 EVOLUTION.md 必须有，否则就是漏更。
    let modernViewVersions = viewVersions.filter { v in
        let parts = v.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        return (parts[0], parts[1], parts[2]) >= (0, 5, 5)
        return parts.count == 3 && (parts[0], parts[1], parts[2]) >= (0, 5, 5)
    }
    let missingInEvo = modernViewVersions.subtracting(evoVersions)
    t.expect(missingInEvo.isEmpty,
             "evolution-sync: makeHistory 中 v≥0.5.5 的所有条目 EVOLUTION.md 必须有（实际缺 \(missingInEvo.sorted())）")
    let overlap = evoVersions.intersection(viewVersions)
    t.expect(overlap.count >= 5,
             "evolution-sync: makeHistory 与 EVOLUTION 至少 5 个共同版本（实际 \(overlap.count)）")
    // 增量：上一版发布期间 push 过的版本不能在 makeHistory 里完全缺失
    let recent = ["v0.5.78", "v0.5.79", "v0.5.80", "v0.5.81"]
    let missingRecent = recent.filter { !viewVersions.contains($0) }
    t.expect(missingRecent.isEmpty,
             "evolution-sync: 最近 4 个发布版本（v0.5.78..v0.5.81）必须全部在 makeHistory（实际缺 \(missingRecent)）")
}
