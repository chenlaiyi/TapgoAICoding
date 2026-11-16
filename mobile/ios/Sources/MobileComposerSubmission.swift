import Foundation

/// The next submission uses the Host's command handlers, never a prompt-only imitation.
enum MobileComposerMode: String, CaseIterable {
    case message, plan, goal
    var title: String {
        switch self {
        case .message: "普通对话"
        case .plan: "方案模式"
        case .goal: "追求目标"
        }
    }
    var command: String? {
        switch self {
        case .message: nil
        case .plan: "plan"
        case .goal: "goal"
        }
    }
}

struct MobileDraftAttachment: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let data: Data
    let image: Bool
}

enum MobileComposerFailure: LocalizedError {
    case invalidImage, unavailable, rejected(String)
    var errorDescription: String? {
        switch self {
        case .invalidImage: "照片格式不可用"
        case .unavailable: "连接不可用或此电脑不支持该操作"
        case .rejected(let message): message
        }
    }
}

/// Identity of one chat submission, reused when the same draft is sent again after an unknown outcome.
struct MobilePendingSubmission: Equatable {
    let requestId: String
    let text: String
    let mode: MobileComposerMode
    let attachmentNames: [String]
    let attachmentBytes: Int

    /// Records the payload the Host deduplicates by request id.
    /// - Parameters:
    ///   - text: Message text exactly as typed.
    ///   - mode: Composer mode used for delivery.
    ///   - attachments: Draft attachments submitted with the text.
    ///   - requestId: Existing identity to keep for an unchanged draft.
    init(text: String, mode: MobileComposerMode, attachments: [MobileDraftAttachment],
         requestId: String = UUID().uuidString) {
        self.requestId = requestId
        self.text = text
        self.mode = mode
        self.attachmentNames = attachments.map(\.name)
        self.attachmentBytes = attachments.reduce(0) { $0 + $1.data.count }
    }

    /// Whether `other` delivers the same message, so this submission's request id may be reused.
    /// - Parameter other: The submission about to be sent.
    /// - Returns: `true` when text, mode, and attachments are unchanged.
    func matches(_ other: MobilePendingSubmission) -> Bool {
        text == other.text && mode == other.mode
            && attachmentNames == other.attachmentNames && attachmentBytes == other.attachmentBytes
    }
}

/// Authenticated wire requests shared by new and existing conversation composers.
@MainActor
struct MobileComposerTransport {
    let session: URLSession
    let origin: URL

    /// Sends one authenticated client request.
    /// - Parameters:
    ///   - method: Host endpoint name.
    ///   - args: Wire arguments for that endpoint.
    ///   - timeout: Request timeout; `nil` keeps the session's default.
    /// - Returns: the endpoint's result value.
    func call(_ method: String, args: [String: Any], timeout: TimeInterval? = nil) async throws -> Any {
        var request = URLRequest(url: origin.appendingPathComponent("api/\(method)"))
        request.httpMethod = "POST"
        if let timeout { request.timeoutInterval = timeout }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": "client-request", "rpcId": UUID().uuidString, "method": method, "payload": ["args": args]
        ])
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = body["result"] as? [String: Any], result["ok"] as? Bool == true else {
            throw MobileComposerFailure.unavailable
        }
        return result["value"] ?? NSNull()
    }

    func content(text: String, attachments: [MobileDraftAttachment], sessionId: String) async throws -> [[String: Any]] {
        var content: [[String: Any]] = []
        for attachment in attachments {
            if attachment.image {
                content.append(["type": "image", "mediaType": "image/jpeg", "data": attachment.data.base64EncodedString(),
                                "name": attachment.name])
            } else {
                var components = URLComponents(url: origin.appendingPathComponent("api/session/uploadFileBinary"),
                                               resolvingAgainstBaseURL: false)
                components?.queryItems = [URLQueryItem(name: "sessionId", value: sessionId),
                                          URLQueryItem(name: "name", value: attachment.name)]
                guard let url = components?.url else { throw MobileComposerFailure.unavailable }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = Self.promptTimeout
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                let (data, response) = try await session.upload(for: request, from: attachment.data)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      result["ok"] as? Bool == true,
                      let value = result["value"] as? [String: Any], let receipt = value["receiptId"] as? String else {
                    throw MobileComposerFailure.rejected("文件上传失败，附件已保留，请重试")
                }
                content.append(["type": "file", "receiptId": receipt])
            }
        }
        if !text.isEmpty { content.append(["type": "text", "text": text]) }
        return content
    }

    /// Sends one chat prompt or composer command.
    /// - Parameters:
    ///   - text: Message text exactly as typed.
    ///   - attachments: Draft attachments submitted with the text.
    ///   - mode: Composer mode that selects the command path.
    ///   - sessionId: Session receiving the message.
    ///   - requestId: Submission identity the Host deduplicates by.
    func submit(text: String, attachments: [MobileDraftAttachment], mode: MobileComposerMode,
                sessionId: String, requestId: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .goal {
            let control = trimmed.lowercased()
            if trimmed.isEmpty || ["clear", "pause", "resume", "edit"].contains(control)
                || control.split(whereSeparator: \.isWhitespace).first == "edit" {
                throw MobileComposerFailure.rejected("请填写具体目标，目标不能只包含控制命令")
            }
        }
        if mode == .plan && trimmed == "off" {
            throw MobileComposerFailure.rejected("请填写具体方案要求；退出方案模式请使用退出按钮")
        }
        let content = try await content(text: text, attachments: attachments, sessionId: sessionId)
        if let command = mode.command {
            try await execute(line: "/\(command)\(text.isEmpty ? "" : " " + text)",
                              attachments: content.filter { $0["type"] as? String != "text" }, sessionId: sessionId)
        } else {
            _ = try await call("session/prompt", args: ["request": ["requestId": requestId,
                "sessionId": sessionId, "mode": "queue", "content": content,
                "clientTimeZone": TimeZone.current.identifier]], timeout: Self.promptTimeout)
        }
    }

    /// A message carrying a photo may need longer than the session's default before the Host answers.
    static let promptTimeout: TimeInterval = 120

    func execute(line: String, attachments: [[String: Any]] = [], sessionId: String) async throws {
        let value = try await call("commands/execute", args: ["agentId": sessionId, "line": line,
                                                             "submittedAttachments": attachments])
        guard let execution = value as? [String: Any], let result = execution["result"] as? [String: Any] else {
            throw MobileComposerFailure.unavailable
        }
        guard result["kind"] as? String == "success" else {
            throw MobileComposerFailure.rejected(result["text"] as? String ?? "此电脑无法执行该操作")
        }
    }
}
