import Foundation
import TapgoCore

/// EVO-041：自进化成本快照的写入/读取契约（App 写，evolve.sh 读）。
func runEvolutionCost(_ t: TestRunner) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-cost-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    t.expectEqual(TapgoCore.EvolutionCostSnapshot.fileName, "evolution_cost.json",
                  "cost: file name is stable for evolve.sh")
    let home = URL(fileURLWithPath: "/tmp/fake-home")
    t.expect(TapgoCore.EvolutionCostSnapshot.stateDirectory(home: home).path
                .hasSuffix("Library/Application Support/Tapgo AICoding/state"),
             "cost: state directory convention")

    let written = TapgoCore.EvolutionCostSnapshot.write(
        tokens: 4321, threadId: "evo-abc", model: "MiniMax-M3", stateDirectory: tmp)
    t.expectEqual(written?.tokens, 4321, "cost: write returns snapshot")
    t.expectEqual(written?.schemaVersion, 1, "cost: schema version")
    t.expectEqual(written?.costUSD, nil, "cost: never fabricates USD cost")

    let loaded = TapgoCore.EvolutionCostSnapshot.load(stateDirectory: tmp)
    t.expectEqual(loaded?.tokens, 4321, "cost: round-trips tokens")
    t.expectEqual(loaded?.threadId, "evo-abc", "cost: round-trips thread id")
    t.expectEqual(loaded?.model, "MiniMax-M3", "cost: round-trips model")

    // 覆盖写：只保留最新累计值（evolve.sh 按增量归因）
    TapgoCore.EvolutionCostSnapshot.write(tokens: 9999, threadId: "evo-abc", stateDirectory: tmp)
    t.expectEqual(TapgoCore.EvolutionCostSnapshot.load(stateDirectory: tmp)?.tokens, 9999,
                  "cost: overwrite keeps latest cumulative value")

    // 最小字段：costUSD / model 缺失时仍可解码
    let url = TapgoCore.EvolutionCostSnapshot.fileURL(stateDirectory: tmp)
    try? "{\"schemaVersion\":1,\"threadId\":\"evo-min\",\"tokens\":7,\"updatedAt\":\"2026-09-13T00:00:00Z\"}"
        .write(to: url, atomically: true, encoding: .utf8)
    let minimal = TapgoCore.EvolutionCostSnapshot.load(stateDirectory: tmp)
    t.expectEqual(minimal?.tokens, 7, "cost: decodes without optional fields")
    t.expectEqual(minimal?.costUSD, nil, "cost: absent cost stays nil")
    t.expectEqual(minimal?.model, nil, "cost: absent model stays nil")

    // 文件不存在 / 非法 JSON 都不崩
    t.expectEqual(TapgoCore.EvolutionCostSnapshot.load(
        stateDirectory: tmp.appendingPathComponent("missing", isDirectory: true)), nil,
                  "cost: missing file loads nil")
    try? "not-json".write(to: url, atomically: true, encoding: .utf8)
    t.expectEqual(TapgoCore.EvolutionCostSnapshot.load(stateDirectory: tmp), nil,
                  "cost: invalid json loads nil")
}
