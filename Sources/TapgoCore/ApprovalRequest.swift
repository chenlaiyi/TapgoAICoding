import Foundation

/// An approval request raised by the harness. The user must explicitly
/// approve or deny before the harness proceeds. The Codex protocol calls
/// this `item/commandExecution/requestApproval` and
/// `item/fileChange/requestApproval`.
public struct ApprovalRequest: Identifiable, Hashable, Codable {
    public let id: String
    /// Top-level JSON-RPC id supplied by current Codex app-server approval
    /// requests. The client must echo this exact value in its response frame.
    /// Nil is retained for compatibility with legacy notification-shaped
    /// approvals, which used an id inside `params` instead.
    public var rpcRequestId: JSONValue?
    public var kind: Kind
    public var reason: String
    public var payload: Payload
    public var decision: Decision?

    public init(
        id: String,
        rpcRequestId: JSONValue? = nil,
        kind: Kind,
        reason: String,
        payload: Payload,
        decision: Decision? = nil
    ) {
        self.id = id
        self.rpcRequestId = rpcRequestId
        self.kind = kind
        self.reason = reason
        self.payload = payload
        self.decision = decision
    }

    /// Current app-server approvals are server-initiated JSON-RPC requests,
    /// not notifications. Return the response frame that unblocks the server.
    public func rpcResponseFrame(approve: Bool) -> JSONValue? {
        guard let rpcRequestId else { return nil }
        return .object([
            "id": rpcRequestId,
            "result": .object([
                "decision": .string(approve ? "accept" : "decline"),
            ]),
        ])
    }

    /// Make the display/persistence id unique across app-server processes.
    /// The protocol-level rpcRequestId is intentionally preserved verbatim.
    public func scoped(forTurn turnId: String) -> ApprovalRequest {
        ApprovalRequest(
            id: "\(turnId):\(id)",
            rpcRequestId: rpcRequestId,
            kind: kind,
            reason: reason,
            payload: payload,
            decision: decision
        )
    }

    public enum Kind: String, Hashable, Codable {
        case commandExecution
        case fileChange
        case toolCall
    }

    public enum Decision: String, Hashable, Codable {
        case approved
        case denied
        case approvedForSession
        case cancelled
    }

    /// One of these is set depending on `kind`. We keep the data
    /// non-optional inside the matching case so the UI can switch on it.
    public enum Payload: Hashable, Codable {
        case command(CommandExecution)
        case fileChange(FileChange)
        case toolCall(ToolCall)

        private enum CodingKeys: String, CodingKey { case kind, value }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try c.decode(String.self, forKey: .kind)
            switch kind {
            case "command":
                self = .command(try c.decode(CommandExecution.self, forKey: .value))
            case "fileChange":
                self = .fileChange(try c.decode(FileChange.self, forKey: .value))
            case "toolCall":
                self = .toolCall(try c.decode(ToolCall.self, forKey: .value))
            default:
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown approval payload kind \(kind)"))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .command(let e):
                try c.encode("command", forKey: .kind)
                try c.encode(e, forKey: .value)
            case .fileChange(let f):
                try c.encode("fileChange", forKey: .kind)
                try c.encode(f, forKey: .value)
            case .toolCall(let t):
                try c.encode("toolCall", forKey: .kind)
                try c.encode(t, forKey: .value)
            }
        }

        public var command: CommandExecution? {
            if case .command(let c) = self { return c } else { return nil }
        }
        public var fileChange: FileChange? {
            if case .fileChange(let f) = self { return f } else { return nil }
        }
        public var toolCall: ToolCall? {
            if case .toolCall(let t) = self { return t } else { return nil }
        }
    }
}
