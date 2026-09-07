import Foundation

/// Lightweight structural checks for the in-source `makeHistory()` array
/// inside `EvolutionLogView`. Catches the class of bug where a hand-edited
/// string literal is malformed (unterminated quote, stray newline, etc.)
/// that the Swift compiler accepts but which the runtime UI silently
/// surfaces as missing entries. The test reads the source file as text
/// — no AST or import needed — so it runs in the same `swift run
/// TapgoTests` harness as the other unit tests.
func runMakeHistoryParityTests(_ t: TestRunner) {
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Sources/TapgoTests
        .deletingLastPathComponent()  // Sources
        .deletingLastPathComponent()  // repo root
    let viewURL = repoRoot
        .appendingPathComponent("Sources/TapgoAICoding/Views/EvolutionLogView.swift")
    let evolutionURL = repoRoot
        .appendingPathComponent("EVOLUTION.md")
    let plistURL = repoRoot
        .appendingPathComponent("AppBuilder/Info.plist")
    let projectYML = repoRoot
        .appendingPathComponent("AppBuilder/project.yml")

    let viewSource: String
    let evolutionSource: String
    let plistSource: String
    let projectSource: String
    do {
        viewSource = try String(contentsOf: viewURL, encoding: .utf8)
        evolutionSource = try String(contentsOf: evolutionURL, encoding: .utf8)
        plistSource = try String(contentsOf: plistURL, encoding: .utf8)
        projectSource = try String(contentsOf: projectYML, encoding: .utf8)
    } catch {
        t.expect(false, "MakeHistory parity: read source files — \(error.localizedDescription)")
        return
    }

    // 1. makeHistory() array: 抽取所有 version 字符串。
    let versionPattern = try! NSRegularExpression(
        pattern: #"version:\s*\"(v[0-9]+\.[0-9]+\.[0-9]+)\""#)
    let versionRange = NSRange(viewSource.startIndex..., in: viewSource)
    let versions = versionPattern.matches(in: viewSource, range: versionRange)
        .compactMap { m -> String? in
            guard let r = Range(m.range(at: 1), in: viewSource) else { return nil }
            return String(viewSource[r])
        }
    t.expect(!versions.isEmpty, "makeHistory 包含至少 1 个 version 字符串")
    t.expect(versions.count >= 20, "makeHistory 版本数 >= 20（项目迭代累积），实际 \(versions.count)")

    // 2. 字符串健康：makeHistory(...) 块内引号数为偶数（防 v0.5.125
    //    中文双引号导致下一个 entry 被吞到字符串内的 bug）。
    if let historyRange = historyArrayRange(in: viewSource) {
        let slice = viewSource[historyRange]
        let quoteCount = slice.filter { $0 == "\"" }.count
        t.expect(quoteCount % 2 == 0,
                  "makeHistory 数组内引号数为偶数 (当前 \(quoteCount))")
        t.expect(!slice.contains("\"\n\""),
                  "makeHistory 数组内字符串没有未转义换行符（\\n 字面）")
    } else {
        t.expect(false, "makeHistory 数组未找到")
    }

    // 3. EVOLUTION.md 顶部 ## 段数量应与 makeHistory 版本数一致。
    // makeHistory 最后 10 个版本（已知正确顺序，因为 makeHistory 是
    // 按发布倒序排列的）必须都在 EVOLUTION.md 中。
    // 旧 v0.5.5 之前的版本在 makeHistory 中已存在但 EVOLUTION.md 历史
    // 有零星漏段；该测试只保证新发版始终双向同步。
    let headerPattern = try! NSRegularExpression(pattern: #"^## (v\d+\.\d+\.\d+)"#)
    let makeHistorySet = Set(versions)
    // 过滤 v1.x（iOS 子项目版本，不在主项目 makeHistory 范围）。
    let evolutionSet: Set<String> = Set(
        evolutionSource.components(separatedBy: "\n").compactMap { line in
            // 用正则一次性抽出 vX.Y.Z 段头，避免手工按字符 split。
            let r = NSRange(line.startIndex..., in: line)
            guard let m = headerPattern.firstMatch(in: line, range: r),
                  let verRange = Range(m.range(at: 1), in: line) else { return nil }
            let v = String(line[verRange])
            // 主项目 makeHistory 只覆盖 v0.5.0+，iOS 子项目用 v1.x
            if v.hasPrefix("v1.") || v.hasPrefix("v0.0.") || v.hasPrefix("v0.1.") || v.hasPrefix("v0.2.") {
                return nil
            }
            return v
        }
    )
    let missingInEvolution = versions.filter { !evolutionSet.contains($0) }
    t.expect(missingInEvolution.isEmpty,
              "makeHistory 每个版本都必须在 EVOLUTION.md 出现，缺失：\(missingInEvolution.prefix(10).joined(separator: ", "))")
    let missingInMakeHistory = evolutionSet.subtracting(makeHistorySet).sorted()
    t.expect(missingInMakeHistory.isEmpty,
              "EVOLUTION.md 每个版本都必须在 makeHistory 出现，缺失：\(missingInMakeHistory.prefix(10).joined(separator: ", "))")

    // 4. Info.plist 与 project.yml 的版本号应一致。
    var plistVersion: String? = nil
    if let m = plistSource.range(of: #"<string>([0-9]+\.[0-9]+\.[0-9]+)</string>"#, options: .regularExpression) {
        let s = String(plistSource[m])
        plistVersion = s.replacingOccurrences(of: "<string>", with: "").replacingOccurrences(of: "</string>", with: "")
    }
    let projectVersionActual: String? = {
        guard let r = projectSource.range(of: #"MARKETING_VERSION:\s*\"([0-9]+\.[0-9]+\.[0-9]+)\""#, options: .regularExpression) else { return nil }
        let s = String(projectSource[r])
        guard let m = s.range(of: #"\"([0-9]+\.[0-9]+\.[0-9]+)\""#, options: .regularExpression) else { return nil }
        return String(s[m]).replacingOccurrences(of: "\"", with: "")
    }()
    let versionsMatch = (plistVersion == projectVersionActual)
    t.expect(versionsMatch,
              "Info.plist (\(plistVersion ?? "?")) == project.yml (\(projectVersionActual ?? "?"))")
}

private func historyArrayRange(in source: String) -> Range<String.Index>? {
    let marker = "private static func makeHistory()"
    guard let markerIdx = source.range(of: marker) else { return nil }
    guard let returnStart = source.range(of: "return [", range: markerIdx.upperBound..<source.endIndex) else { return nil }
    var depth = 1
    var idx = returnStart.upperBound
    while idx < source.endIndex {
        let c = source[idx]
        if c == "[" { depth += 1 }
        if c == "]" {
            depth -= 1
            if depth == 0 { return source.index(after: returnStart.lowerBound)..<source.index(after: idx) }
        }
        idx = source.index(after: idx)
    }
    return nil
}
