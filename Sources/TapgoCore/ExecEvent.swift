import Foundation

/// Normalized event from the Codex app-server harness. We map every
/// server notification we care about into one of these cases so the
/// UI never has to inspect raw JSON.
///
/// `agentMessage` and `reasoning` come in two flavors:
///   - `*Delta` events from streaming notifications (`agentMessage/delta`,
///     `reasoning/textDelta`). These are appended to the assistant's
///     accumulating text in the SessionStore.
///   - The final `text` of an `agentMessage` or `reasoning` item is
///     delivered via the corresponding `item/completed` notification —
///     the SessionStore should treat that as the authoritative final
///     value, replacing any accumulated partial text.
public enum ExecEvent: Hashable {
    case threadStarted(threadId: String)
    case turnStarted(turnId: String)
    case turnCompleted(status: String, errorMessage: String?, usage: TokenUsage?)

    /// A mid-turn `thread/tokenUsage/updated` tick, used to keep the context
    /// meter live instead of waiting for the turn to complete.
    case tokenUsageUpdated(usage: TokenUsage)

    /// Stable app-server snapshots. Both replace the prior snapshot for the
    /// same turn rather than representing append-only deltas.
    case planUpdated(turnId: String, explanation: String?, steps: [PlanStep])
    case turnDiffUpdated(turnId: String, diff: String)

    case agentMessageDelta(id: String, delta: String)
    case agentMessage(id: String, text: String)

    case reasoningDelta(id: String, delta: String)
    case reasoning(id: String, summary: [String])

    /// Streamed cond/apsed "reasoning summary" (distinct from the raw
    /// `reasoning/textDelta` trace). Mirrors Codex's summary band.
    case reasoningSummaryDelta(id: String, index: Int?, delta: String)

    case commandStarted(id: String, command: String, cwd: String?)
    case commandOutput(id: String, output: String)
    case commandCompleted(id: String, exitCode: Int32?, status: String, aggregatedOutput: String?)

    case fileChange(id: String, changes: [FileChangeOp])

    case mcpToolCallStarted(id: String, server: String, tool: String, arguments: JSONValue?)
    case mcpToolCallCompleted(id: String, status: String, error: String?, resultSummary: String?)

    case webSearch(id: String, query: String?)
    case contextCompaction(id: String, status: String)

    /// The harness wants the user to approve a command, file change, or
    /// tool call before it proceeds. `ApprovalRow` renders this inline
    /// and `SessionStore` resolves it via `respondToApproval`.
    case approvalRequested(ApprovalRequest)
    /// A pending approval reached the local deadline and was automatically
    /// declined so the harness cannot remain wedged in the background.
    case approvalExpired(ApprovalRequest)

    /// `account/rateLimits/updated` notification from the harness.
    /// Carries the live subscription/quota snapshot used by the
    /// composer popover (5h + weekly windows + credits balance).
    case rateLimitsUpdated(snapshot: RateLimitsSnapshot)

    case error(message: String)

    public struct FileChangeOp: Hashable {
        public let path: String
        public let kind: String   // "add" | "delete" | "update"
    }

    public struct PlanStep: Hashable {
        public let step: String
        public let status: String

        public init(step: String, status: String) {
            self.step = step
            self.status = status
        }
    }
}

/// Map a single app-server notification into an ExecEvent, or nil if we
/// don't care about this method/payload.
public enum ExecEventParser {
    public static func parse(
        method: String,
        params: [String: JSONValue],
        rpcRequestId: JSONValue? = nil
    ) -> ExecEvent? {
        switch method {
        case "thread/started":
            guard let id = params["thread"]?.objectValue?["id"]?.stringValue else { return nil }
            return .threadStarted(threadId: id)

        case "turn/started":
            guard let id = params["turn"]?.objectValue?["id"]?.stringValue else { return nil }
            return .turnStarted(turnId: id)

        case "turn/completed":
            let turn = params["turn"]?.objectValue ?? [:]
            let status = turn["status"]?.stringValue ?? "completed"
            let errorMessage: String?
            if status == "failed" {
                let info = turn["error"]?.objectValue
                errorMessage = info?["message"]?.stringValue
                    ?? stringifyError(info)
            } else {
                errorMessage = nil
            }
            let usage = TokenUsage.fromJSON(
                params["usage"] ?? params["total_token_usage"] ?? turn["usage"]
            )
            return .turnCompleted(status: status, errorMessage: errorMessage, usage: usage)

        case "thread/tokenUsage/updated":
            // The live tick nests the counters under `tokenUsage.total` /
            // `tokenUsage.last`, with `modelContextWindow` on the outer.
            guard let tu = params["tokenUsage"]?.objectValue else { return nil }
            let inner = tu["total"]?.objectValue ?? tu["last"]?.objectValue ?? tu
            var merged = inner
            if let ctx = tu["modelContextWindow"] { merged["modelContextWindow"] = ctx }
            guard let usage = TokenUsage.fromJSON(.object(merged)) else { return nil }
            return .tokenUsageUpdated(usage: usage)

        case "turn/plan/updated":
            let turnId = params["turnId"]?.stringValue
                ?? params["turn_id"]?.stringValue
                ?? "current"
            let steps = (params["plan"]?.arrayValue ?? []).compactMap { value -> ExecEvent.PlanStep? in
                guard let item = value.objectValue,
                      let step = item["step"]?.stringValue else { return nil }
                return .init(step: step, status: item["status"]?.stringValue ?? "pending")
            }
            return .planUpdated(
                turnId: turnId,
                explanation: params["explanation"]?.stringValue,
                steps: steps
            )

        case "turn/diff/updated":
            guard let diff = params["diff"]?.stringValue else { return nil }
            let turnId = params["turnId"]?.stringValue
                ?? params["turn_id"]?.stringValue
                ?? "current"
            return .turnDiffUpdated(turnId: turnId, diff: diff)

        case "item/started", "item/completed":
            guard let item = params["item"]?.objectValue,
                  let id = item["id"]?.stringValue,
                  let type = item["type"]?.stringValue
            else { return nil }
            return parseItem(completed: method == "item/completed", id: id, type: type, item: item)

        case "agentMessage/delta", "item/agentMessage/delta":
            guard let id = params["itemId"]?.stringValue,
                  let delta = params["delta"]?.stringValue
            else { return nil }
            return .agentMessageDelta(id: id, delta: delta)

        case "item/commandExecution/outputDelta", "commandExecution/outputDelta":
            guard let id = params["itemId"]?.stringValue
                    ?? params["item_id"]?.stringValue,
                  let delta = params["delta"]?.stringValue
            else { return nil }
            return .commandOutput(id: id, output: delta)

        case "reasoning/textDelta", "item/reasoning/textDelta":
            guard let id = params["itemId"]?.stringValue,
                  let delta = params["delta"]?.stringValue
            else { return nil }
            return .reasoningDelta(id: id, delta: delta)

        case "reasoningSummaryTextDelta",
             "reasoning/summaryTextDelta",
             "reasoningSummary/textDelta",
             "item/reasoningSummary/textDelta",
             "item/reasoning/summaryTextDelta":
            guard let delta = params["delta"]?.stringValue
                  ?? params["text"]?.stringValue else { return nil }
            let id = params["itemId"]?.stringValue
                ?? params["item_id"]?.stringValue
                ?? params["reasoningId"]?.stringValue
                ?? "reasoning-summary"
            let index = params["summary_index"]?.intOrBoolAsInt
                ?? params["summaryIndex"]?.intOrBoolAsInt
            return .reasoningSummaryDelta(id: id, index: index, delta: delta)

        case "account/rateLimits/updated":
            // Codex app-server: { "rateLimits": { ... } }
            if let snap = RateLimitsSnapshot.fromJSON(
                params["rateLimits"] ?? params["rate_limits"]
            ) {
                return .rateLimitsUpdated(snapshot: snap)
            }
            return nil

        case "error":
            if let msg = params["message"]?.stringValue {
                return .error(message: msg)
            }
            if let info = params["error"]?.objectValue,
               let msg = info["message"]?.stringValue {
                return .error(message: msg)
            }
            return .error(message: "Harness 错误")

        case "item/commandExecution/requestApproval":
            return parseApprovalRequest(
                kind: .commandExecution,
                params: params,
                rpcRequestId: rpcRequestId
            ).map { .approvalRequested($0) }

        case "item/fileChange/requestApproval":
            return parseApprovalRequest(
                kind: .fileChange,
                params: params,
                rpcRequestId: rpcRequestId
            ).map { .approvalRequested($0) }

        case "item/toolCall/requestApproval":
            return parseApprovalRequest(
                kind: .toolCall,
                params: params,
                rpcRequestId: rpcRequestId
            ).map { .approvalRequested($0) }

        default:
            return nil
        }
    }

    private static func parseItem(
        completed: Bool,
        id: String,
        type: String,
        item: [String: JSONValue]
    ) -> ExecEvent? {
        switch type {
        case "agentMessage":
            let text = item["text"]?.stringValue ?? ""
            if completed {
                return .agentMessage(id: id, text: text)
            } else {
                return nil  // we'll get the text either via deltas or item/completed
            }
        case "reasoning":
            if completed {
                let summary = item["summary"]?.arrayValue?.compactMap { $0.stringValue } ?? []
                return .reasoning(id: id, summary: summary)
            } else {
                return nil
            }
        case "commandExecution":
            let command = item["command"]?.stringValue ?? ""
            let status = item["status"]?.stringValue ?? "inProgress"
            if !completed && status == "inProgress" {
                return .commandStarted(id: id, command: command, cwd: item["cwd"]?.stringValue)
            } else if completed {
                let exit = item["exitCode"]?.intOrBoolAsInt.map(Int32.init)
                let output = item["aggregatedOutput"]?.stringValue
                    ?? item["output"]?.stringValue
                return .commandCompleted(
                    id: id,
                    exitCode: exit,
                    status: status,
                    aggregatedOutput: output
                )
            } else {
                return nil
            }
        case "fileChange":
            guard completed else { return nil }
            let raw = item["changes"]?.arrayValue ?? []
            let ops = raw.compactMap { value -> ExecEvent.FileChangeOp? in
                guard let obj = value.objectValue,
                      let path = obj["path"]?.stringValue,
                      let kind = decodeKind(obj["kind"])
                else { return nil }
                return ExecEvent.FileChangeOp(path: path, kind: kind)
            }
            return .fileChange(id: id, changes: ops)
        case "mcpToolCall":
            let server = item["server"]?.stringValue ?? ""
            let tool = item["tool"]?.stringValue ?? ""
            let status = item["status"]?.stringValue ?? "inProgress"
            if !completed && status == "inProgress" {
                return .mcpToolCallStarted(id: id, server: server, tool: tool, arguments: item["arguments"])
            } else if completed {
                let err = item["error"]?.objectValue?["message"]?.stringValue
                let result = summarizeMcpResult(item["result"])
                return .mcpToolCallCompleted(id: id, status: status, error: err, resultSummary: result)
            } else {
                return nil
            }
        case "webSearch":
            guard completed else { return nil }
            return .webSearch(id: id, query: item["query"]?.stringValue)
        case "contextCompaction":
            return .contextCompaction(
                id: id,
                status: completed ? "completed" : "inProgress"
            )
        default:
            return nil
        }
    }

    /// `PatchChangeKind` is one of:
    ///   - string "add" | "delete" | "update"  (older wire format)
    ///   - object `{ "type": "add" | "delete" | "update", ... }` (v2)
    private static func decodeKind(_ v: JSONValue?) -> String? {
        if let s = v?.stringValue { return s }
        if let obj = v?.objectValue {
            return obj["type"]?.stringValue
        }
        return nil
    }

    private static func summarizeMcpResult(_ v: JSONValue?) -> String? {
        guard let v else { return nil }
        // First text item wins. Keep it terse.
        if let content = v.objectValue?["content"]?.arrayValue {
            for item in content {
                if let text = item.objectValue?["text"]?.stringValue {
                    return text
                }
            }
        }
        if let structured = v.objectValue?["structuredContent"] {
            if let data = try? JSONEncoder().encode(structured),
               let s = String(data: data, encoding: .utf8) {
                return s.count > 240 ? String(s.prefix(240)) + "…" : s
            }
        }
        return nil
    }

    private static func stringifyError(_ v: [String: JSONValue]?) -> String? {
        guard let v else { return nil }
        if let data = try? JSONEncoder().encode(v),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return nil
    }

    // MARK: - Approval requests

    /// Build an `ApprovalRequest` from an approval notification. The
    /// harness wire shape varies slightly across versions, so we accept
    /// the item either nested under `item` or directly under a
    /// kind-named key (`commandExecution` / `fileChange` / `toolCall`),
    /// and the request id from either a top-level `request_id` or the
    /// item's `id`.
    private static func parseApprovalRequest(
        kind: ApprovalRequest.Kind,
        params: [String: JSONValue],
        rpcRequestId: JSONValue?
    ) -> ApprovalRequest? {
        let item = params["item"]?.objectValue
            ?? params[kind.rawValue]?.objectValue
            ?? params["request"]?.objectValue

        var requestId = params["approvalId"]?.stringValue
        if requestId == nil { requestId = params["request_id"]?.stringValue }
        if requestId == nil { requestId = params["id"]?.stringValue }
        if requestId == nil { requestId = params["itemId"]?.stringValue }
        if requestId == nil { requestId = params["item_id"]?.stringValue }
        if requestId == nil { requestId = item?["id"]?.stringValue }
        if requestId == nil { requestId = rpcRequestId?.stringValue }
        if requestId == nil, let numericId = rpcRequestId?.intOrBoolAsInt {
            requestId = String(numericId)
        }
        guard let requestId else { return nil }

        let reason = item?["reason"]?.stringValue
            ?? params["reason"]?.stringValue
            ?? "Approval required"

        let payload: ApprovalRequest.Payload
        switch kind {
        case .commandExecution:
            guard let ce = parseApprovalCommand(item ?? params) else { return nil }
            payload = .command(ce)
        case .fileChange:
            guard let fc = parseApprovalFileChange(item ?? params) else { return nil }
            payload = .fileChange(fc)
        case .toolCall:
            guard let tc = parseApprovalToolCall(item ?? params) else { return nil }
            payload = .toolCall(tc)
        }

        return ApprovalRequest(
            id: requestId,
            rpcRequestId: rpcRequestId,
            kind: kind,
            reason: reason,
            payload: payload,
            decision: nil
        )
    }

    private static func parseApprovalCommand(_ v: [String: JSONValue]) -> CommandExecution? {
        let command = v["command"]?.stringValue
            ?? v["networkApprovalContext"]?.objectValue?["host"]?.stringValue.map {
                "访问网络主机 \($0)"
            }
            ?? "待批准的命令"
        return CommandExecution(
            id: v["itemId"]?.stringValue
                ?? v["item_id"]?.stringValue
                ?? v["id"]?.stringValue
                ?? "",
            command: command,
            cwd: v["cwd"]?.stringValue,
            status: .awaitingApproval,
            startedAt: Date()
        )
    }

    private static func parseApprovalFileChange(_ v: [String: JSONValue]) -> FileChange? {
        let path = v["path"]?.stringValue
            ?? v["grantRoot"]?.stringValue
            ?? "待批准的文件变更"
        let kindRaw = v["kind"]?.stringValue ?? v["patchKind"]?.stringValue ?? "update"
        let kind = FileChange.Kind(rawValue: kindRaw) ?? .update
        return FileChange(
            id: v["itemId"]?.stringValue
                ?? v["item_id"]?.stringValue
                ?? v["id"]?.stringValue
                ?? "",
            kind: kind,
            path: path,
            diff: v["diff"]?.stringValue ?? "",
            status: .awaitingApproval
        )
    }

    private static func parseApprovalToolCall(_ v: [String: JSONValue]) -> ToolCall? {
        guard let name = v["name"]?.stringValue else { return nil }
        let arguments: String
        if let args = v["arguments"] {
            arguments = args.toJSONString()
        } else {
            arguments = ""
        }
        return ToolCall(
            id: v["id"]?.stringValue ?? "",
            name: name,
            arguments: arguments,
            status: .awaitingApproval
        )
    }
}
