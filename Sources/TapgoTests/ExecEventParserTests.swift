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

    // 5) Current app-server shape: top-level JSON-RPC id + itemId in params.
    let currentCommand: [String: JSONValue] = [
        "threadId": .string("thread-1"),
        "turnId": .string("turn-1"),
        "itemId": .string("item-current"),
        "reason": .string("需要访问工作区外目录"),
        "command": .string("git fetch --prune origin"),
        "cwd": .string("/tmp/repo"),
    ]
    if case .approvalRequested(let req)? = ExecEventParser.parse(
        method: "item/commandExecution/requestApproval",
        params: currentCommand,
        rpcRequestId: .int(77)
    ) {
        t.expectEqual(req.id, "item-current", "current cmd approval: itemId")
        t.expectEqual(req.rpcRequestId, .int(77), "current cmd approval: rpc id preserved")
        if case .command(let ce) = req.payload {
            t.expectEqual(ce.id, "item-current", "current cmd approval: payload item id")
            t.expectEqual(ce.command, "git fetch --prune origin", "current cmd approval: command")
        } else {
            t.expect(false, "current cmd approval: payload is command")
        }
        if let response = req.rpcResponseFrame(approve: true)?.objectValue {
            t.expectEqual(response["id"], .int(77), "current cmd response: rpc id echoed")
            t.expectEqual(
                response["result"]?.objectValue?["decision"],
                .string("accept"),
                "current cmd response: accept decision"
            )
        } else {
            t.expect(false, "current cmd response: frame generated")
        }
        let scoped = req.scoped(forTurn: "local-turn")
        t.expectEqual(scoped.id, "local-turn:item-current",
                      "current cmd approval: display id is turn-scoped")
        t.expectEqual(scoped.rpcRequestId, .int(77),
                      "current cmd approval: scoping preserves rpc id")
        var cancelled = scoped
        cancelled.decision = .cancelled
        let roundTripped = try? JSONDecoder().decode(
            ApprovalRequest.self,
            from: JSONEncoder().encode(cancelled)
        )
        t.expectEqual(roundTripped?.decision, .cancelled,
                      "current cmd approval: cancelled decision persists")
    } else {
        t.expect(false, "current cmd approval: parsed")
    }

    // 6) Current file approval may contain only itemId/reason/grantRoot.
    let currentFile: [String: JSONValue] = [
        "itemId": .string("item-file-current"),
        "reason": .string("需要写入外部目录"),
        "grantRoot": .string("/tmp/export"),
    ]
    if case .approvalRequested(let req)? = ExecEventParser.parse(
        method: "item/fileChange/requestApproval",
        params: currentFile,
        rpcRequestId: .string("rpc-file-1")
    ) {
        t.expectEqual(req.id, "item-file-current", "current file approval: itemId")
        if case .fileChange(let file) = req.payload {
            t.expectEqual(file.path, "/tmp/export", "current file approval: grantRoot shown")
        } else {
            t.expect(false, "current file approval: payload is fileChange")
        }
        let decision = req.rpcResponseFrame(approve: false)?
            .objectValue?["result"]?.objectValue?["decision"]
        t.expectEqual(decision, .string("decline"), "current file response: decline decision")
    } else {
        t.expect(false, "current file approval: parsed")
    }
}

/// Current Codex command output streams via an outputDelta notification and
/// repeats the canonical aggregate on item/completed as a recovery fallback.
@MainActor
func runExecEventParserCommandOutput(_ t: TestRunner) {
    let delta: [String: JSONValue] = [
        "itemId": .string("cmd-1"),
        "delta": .string("line 1\n"),
    ]
    if case .commandOutput(let id, let output)? = ExecEventParser.parse(
        method: "item/commandExecution/outputDelta",
        params: delta
    ) {
        t.expectEqual(id, "cmd-1", "command delta: item id")
        t.expectEqual(output, "line 1\n", "command delta: output")
    } else {
        t.expect(false, "command delta: parsed")
    }

    let completed: [String: JSONValue] = [
        "item": .object([
            "id": .string("cmd-1"),
            "type": .string("commandExecution"),
            "command": .string("printf test"),
            "status": .string("completed"),
            "exitCode": .int(0),
            "aggregatedOutput": .string("line 1\nline 2\n"),
        ]),
    ]
    if case .commandCompleted(let id, let exitCode, let status, let output)? =
        ExecEventParser.parse(method: "item/completed", params: completed) {
        t.expectEqual(id, "cmd-1", "command completed: item id")
        t.expectEqual(exitCode, 0, "command completed: exit code")
        t.expectEqual(status, "completed", "command completed: status")
        t.expectEqual(output, "line 1\nline 2\n", "command completed: aggregate fallback")
    } else {
        t.expect(false, "command completed: parsed")
    }
}

/// Stable turn snapshots and context-compaction lifecycle introduced by the
/// current app-server UI protocol.
@MainActor
func runExecEventParserTurnSnapshots(_ t: TestRunner) {
    let plan: [String: JSONValue] = [
        "turnId": .string("turn-plan-1"),
        "explanation": .string("先检查，再修改"),
        "plan": .array([
            .object(["step": .string("检查代码"), "status": .string("completed")]),
            .object(["step": .string("实施升级"), "status": .string("inProgress")]),
        ]),
    ]
    if case .planUpdated(let turnId, let explanation, let steps)? =
        ExecEventParser.parse(method: "turn/plan/updated", params: plan) {
        t.expectEqual(turnId, "turn-plan-1", "plan: turn id")
        t.expectEqual(explanation, "先检查，再修改", "plan: explanation")
        t.expectEqual(steps.count, 2, "plan: steps count")
        t.expectEqual(steps.last?.status, "inProgress", "plan: status")
    } else {
        t.expect(false, "plan: parsed")
    }

    let diff: [String: JSONValue] = [
        "turnId": .string("turn-diff-1"),
        "diff": .string("--- a/a.swift\n+++ b/a.swift\n"),
    ]
    if case .turnDiffUpdated(let turnId, let snapshot)? =
        ExecEventParser.parse(method: "turn/diff/updated", params: diff) {
        t.expectEqual(turnId, "turn-diff-1", "diff: turn id")
        t.expect(snapshot.contains("+++"), "diff: unified diff preserved")
    } else {
        t.expect(false, "diff: parsed")
    }

    let compactStarted: [String: JSONValue] = [
        "item": .object([
            "id": .string("compact-1"),
            "type": .string("contextCompaction"),
        ]),
    ]
    if case .contextCompaction(let id, let status)? =
        ExecEventParser.parse(method: "item/started", params: compactStarted) {
        t.expectEqual(id, "compact-1", "compact start: id")
        t.expectEqual(status, "inProgress", "compact start: status")
    } else {
        t.expect(false, "compact start: parsed")
    }
    if case .contextCompaction(let id, let status)? =
        ExecEventParser.parse(method: "item/completed", params: compactStarted) {
        t.expectEqual(id, "compact-1", "compact complete: id")
        t.expectEqual(status, "completed", "compact complete: status")
    } else {
        t.expect(false, "compact complete: parsed")
    }
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

/// Exercises `account/rateLimits/updated` notification parsing. Mirrors the
/// `codex account/rateLimits/read` response shape.
@MainActor
func runExecEventParserRateLimitsUpdated(_ t: TestRunner) {
    let params: [String: JSONValue] = [
        "rateLimits": .object([
            "primary": .object([
                "usedPercent": .int(11),
                "windowDurationMins": .int(300),
                "resetsAt": .int(1_779_752_562),
            ]),
            "secondary": .object([
                "usedPercent": .int(2),
                "windowDurationMins": .int(10080),
                "resetsAt": .int(1_780_339_362),
            ]),
            "credits": .object([
                "hasCredits": .bool(false),
                "unlimited": .bool(true),
                "balance": .string(""),
            ]),
            "planType": .string("pro"),
        ])
    ]
    if case .rateLimitsUpdated(let snap)? =
        ExecEventParser.parse(method: "account/rateLimits/updated", params: params) {
        t.expectEqual(snap.primary?.usedPercent ?? -1, 11, "rate-limits event: primary %")
        t.expectEqual(snap.secondary?.windowDurationMins ?? -1, 10080, "rate-limits event: secondary duration")
        t.expectEqual(snap.credits?.unlimited ?? false, true, "rate-limits event: credits unlimited")
        t.expectEqual(snap.planLabel ?? "", "Pro", "rate-limits event: plan label")
    } else {
        t.expect(false, "rate-limits event: parsed as rateLimitsUpdated")
    }

    // snake_case alternative wrapper (defensive).
    let snake: [String: JSONValue] = [
        "rate_limits": .object([
            "primary": .object([
                "used_percent": .int(50),
                "window_duration_mins": .int(300),
            ]),
        ])
    ]
    if case .rateLimitsUpdated(let s2)? =
        ExecEventParser.parse(method: "account/rateLimits/updated", params: snake) {
        t.expectEqual(s2.primary?.usedPercent ?? -1, 50, "rate-limits event: snake_case parsed")
    } else {
        t.expect(false, "rate-limits event: snake_case parsed")
    }

    // Empty payload should NOT yield a stray event (the popover handles nil itself).
    t.expectNil(
        ExecEventParser.parse(method: "account/rateLimits/updated", params: [:]),
        "rate-limits event: empty params → nil"
    )
}
