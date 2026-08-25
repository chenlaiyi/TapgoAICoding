// TapgoTests/ExecEventParserTests.swift
import Foundation
import TapgoCore

/// Exercises `ExecEventParser` approval notification parsing with
/// synthetic params (no harness needed). Covers the three approval
/// kinds and the tolerant id/item shapes the harness uses.
@MainActor
func runExecEventParserApprovalRequests(_ t: TestRunner) {
    // 1) commandExecution — id via top-level `request_id`.
    let cmd: [String: JSONValue] = [
        "request_id": .string("req-cmd"),
        "item": .object([
            "id": .string("item-cmd"),
            "type": .string("commandExecution"),
            "command": .string("ls -la /tmp"),
            "cwd": .string("/tmp"),
            "reason": .string("需要批准执行命令"),
        ]),
    ]
    if case .approvalRequested(let req)? = ExecEventParser.parse(method: "item/commandExecution/requestApproval", params: cmd) {
        t.expectEqual(req.id, "req-cmd", "cmd approval: id from request_id")
        t.expectEqual(req.kind, .commandExecution, "cmd approval: kind")
        t.expectEqual(req.reason, "需要批准执行命令", "cmd approval: reason")
        if case .command(let ce) = req.payload {
            t.expectEqual(ce.command, "ls -la /tmp", "cmd approval: command")
            t.expectEqual(ce.cwd, "/tmp", "cmd approval: cwd")
            t.expectEqual(ce.status, .awaitingApproval, "cmd approval: status")
        } else {
            t.expect(false, "cmd approval: payload is command")
        }
    } else {
        t.expect(false, "cmd approval: event is approvalRequested")
    }

    // 2) fileChange — id via top-level `id` (legacy shape).
    let fc: [String: JSONValue] = [
        "id": .string("req-fc"),
        "item": .object([
            "id": .string("item-fc"),
            "kind": .string("update"),
            "path": .string("/Users/alice/CPA/README.md"),
            "reason": .string("修改文件"),
        ]),
    ]
    if case .approvalRequested(let req)? = ExecEventParser.parse(method: "item/fileChange/requestApproval", params: fc) {
        t.expectEqual(req.id, "req-fc", "fc approval: id from top-level id")
        t.expectEqual(req.kind, .fileChange, "fc approval: kind")
        if case .fileChange(let file) = req.payload {
            t.expectEqual(file.path, "/Users/alice/CPA/README.md", "fc approval: path")
            t.expectEqual(file.kind, .update, "fc approval: kind")
            t.expectEqual(file.status, .awaitingApproval, "fc approval: status")
        } else {
            t.expect(false, "fc approval: payload is fileChange")
        }
    } else {
        t.expect(false, "fc approval: event is approvalRequested")
    }

    // 3) toolCall — arguments as a JSON object.
    let tc: [String: JSONValue] = [
        "id": .string("req-tc"),
        "item": .object([
            "id": .string("item-tc"),
            "name": .string("apply_patch"),
            "arguments": .object(["path": .string("/tmp/a")]),
        ]),
    ]
    if case .approvalRequested(let req)? = ExecEventParser.parse(method: "item/toolCall/requestApproval", params: tc) {
        t.expectEqual(req.id, "req-tc", "tc approval: id")
        t.expectEqual(req.kind, .toolCall, "tc approval: kind")
        if case .toolCall(let tool) = req.payload {
            t.expectEqual(tool.name, "apply_patch", "tc approval: name")
            t.expect(tool.arguments.contains("path"), "tc approval: arguments serialized")
            t.expectEqual(tool.status, .awaitingApproval, "tc approval: status")
        } else {
            t.expect(false, "tc approval: payload is toolCall")
        }
    } else {
        t.expect(false, "tc approval: event is approvalRequested")
    }

    // 4) Unknown method must not produce a stray event.
    t.expectNil(ExecEventParser.parse(method: "item/commandExecution/foo", params: cmd),
                "unknown method: nil")
}

/// Exercises `TokenUsage.fromJSON` (both camelCase and snake_case wire
/// shapes) and the `turn/completed` usage delivery.
@MainActor
func runExecEventParserReasoningSummary(_ t: TestRunner) {
    let p: [String: JSONValue] = [
        "itemId": .string("rs-1"),
        "summary_index": .int(0),
        "delta": .string("第一步"),
    ]
    if case .reasoningSummaryDelta(let id, let index, let delta)? =
        ExecEventParser.parse(method: "reasoningSummaryTextDelta", params: p) {
        t.expectEqual(id, "rs-1", "summary: id")
        t.expectEqual(index ?? -1, 0, "summary: index")
        t.expectEqual(delta, "第一步", "summary: delta")
    } else {
        t.expect(false, "summary: parsed as reasoningSummaryDelta")
    }

    // Alternate method + fallback id.
    let p2: [String: JSONValue] = ["delta": .string("第二步")]
    if case .reasoningSummaryDelta(let id, let index, let delta)? =
        ExecEventParser.parse(method: "reasoning/summaryTextDelta", params: p2) {
        t.expectEqual(id, "reasoning-summary", "summary: fallback id")
        t.expectNil(index, "summary: no index")
        t.expectEqual(delta, "第二步", "summary: alternate method")
    } else {
        t.expect(false, "summary: alternate method parsed")
    }
}

/// Exercises `TokenUsage.fromJSON` (both camelCase and snake_case wire
/// shapes) and the `turn/completed` usage delivery.
@MainActor
func runTokenUsageParsing(_ t: TestRunner) {
    // camelCase (current harness shape).
    let camel: JSONValue = .object([
        "inputTokens": .int(1200),
        "outputTokens": .int(500),
        "totalTokens": .int(1700),
        "cachedInputTokens": .int(300),
        "reasoningOutputTokens": .int(80),
    ])
    let u1 = TokenUsage.fromJSON(camel)
    t.expectNotNil(u1, "usage: camelCase parsed")
    t.expectEqual(u1?.input ?? -1, 1200, "usage: input")
    t.expectEqual(u1?.output ?? -1, 500, "usage: output")
    t.expectEqual(u1?.total ?? -1, 1700, "usage: total")
    t.expectEqual(u1?.cached ?? -1, 300, "usage: cached")
    t.expectEqual(u1?.reasoning ?? -1, 80, "usage: reasoning")

    // snake_case (older harness shape).
    let snake: JSONValue = .object([
        "input_tokens": .int(100),
        "output_tokens": .int(90),
        "total_tokens": .int(190),
        "model_context_window": .int(1_000_000),
    ])
    let u2 = TokenUsage.fromJSON(snake)
    t.expectNotNil(u2, "usage: snake_case parsed")
    t.expectEqual(u2?.input ?? -1, 100, "usage: snake input")
    t.expectEqual(u2?.contextWindow ?? -1, 1_000_000, "usage: context window")

    // Nil / empty object → nil so the UI hides the caption.
    t.expectNil(TokenUsage.fromJSON(nil), "usage: nil object → nil")
    t.expectNil(TokenUsage.fromJSON(.object([:])), "usage: empty object → nil")

    // Through ExecEventParser turn/completed.
    let params: [String: JSONValue] = [
        "turn": .object([
            "id": .string("t1"),
            "status": .string("completed"),
            "usage": .object(["totalTokens": .int(4200)]),
        ]),
    ]
    if case .turnCompleted(let status, let err, let usage)? =
        ExecEventParser.parse(method: "turn/completed", params: params) {
        t.expectEqual(status, "completed", "usage event: status")
        t.expectNil(err, "usage event: no error")
        t.expectEqual(usage?.total ?? -1, 4200, "usage event: total")
    } else {
        t.expect(false, "usage event: parsed as turnCompleted with usage")
    }

    // Live `thread/tokenUsage/updated` tick (nested total + modelContextWindow).
    let liveParams: [String: JSONValue] = [
        "tokenUsage": .object([
            "last": .object(["outputTokens": .int(60)]),
            "total": .object([
                "inputTokens": .int(2000),
                "outputTokens": .int(400),
                "totalTokens": .int(2400),
            ]),
            "modelContextWindow": .int(950_000),
        ]),
    ]
    if case .tokenUsageUpdated(let usage)? =
        ExecEventParser.parse(method: "thread/tokenUsage/updated", params: liveParams) {
        t.expectEqual(usage.total, 2400, "live usage: total")
        t.expectEqual(usage.contextWindow ?? -1, 950_000, "live usage: context window")
    } else {
        t.expect(false, "live usage: parsed as tokenUsageUpdated")
    }

    // contextPercent helper (used by the header context indicator).
    let withCw = TokenUsage(total: 500_000, contextWindow: 1_000_000)
    t.expectEqual(withCw.contextPercent ?? -1, 50, "usage: contextPercent computed")
    t.expectNil(TokenUsage(total: 100).contextPercent, "usage: no contextWindow → nil percent")

    // contextLevel thresholds.
    t.expectEqual(TokenUsage(total: 100_000, contextWindow: 1_000_000).contextLevel, .normal, "level: 10% → normal")
    t.expectEqual(TokenUsage(total: 600_000, contextWindow: 1_000_000).contextLevel, .warn, "level: 60% → warn")
    t.expectEqual(TokenUsage(total: 900_000, contextWindow: 1_000_000).contextLevel, .critical, "level: 90% → critical")
    t.expectNil(TokenUsage(total: 100).contextLevel, "level: no contextWindow → nil")
}
