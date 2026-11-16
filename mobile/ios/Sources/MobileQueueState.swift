import Foundation

/// One prompt waiting in the live Agent inbox.
struct MobileQueuedItem: Identifiable, Equatable {
    let id: String
    let placement: String
    let text: String
    let attachments: [MobileMessageAttachment]

    /// Whether the Host accepts a text-only edit for this item.
    var isEditable: Bool {
        attachments.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether the item has been moved into the running turn.
    var isSteering: Bool { placement == "steering" }

    /// Short preview shown in the queue strip.
    var preview: String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.isEmpty ? (attachments.isEmpty ? "排队消息" : "附件") : line
    }
}

/// One mutation of a still-pending queue item.
enum MobileQueueAction: Equatable {
    case edit(String)
    case remove
    case steer

    /// The `session/updateQueue` action object this mutation sends.
    var wire: [String: Any] {
        switch self {
        case .edit(let text):
            return ["kind": "edit", "content": [["type": "text", "text": text]]]
        case .remove: return ["kind": "remove"]
        case .steer: return ["kind": "steer"]
        }
    }
}

/// User-facing messages for Host queue refusals.
enum MobileQueueFailure {
    /// Maps one Host error code to the sentence shown under the queue strip.
    /// - Parameter code: machine code from the Host refusal.
    /// - Returns: the localized explanation for that refusal.
    static func message(for code: String) -> String {
        switch code {
        case "session/queue-item-not-found": return "这条消息已被处理"
        case "session/steer-unavailable": return "当前回合已结束，消息仍在队列"
        case "session/attachment-invalid": return "含附件的排队消息请在电脑上编辑"
        default: return "队列操作失败，请重试"
        }
    }
}

/// Complete queue state reported by `session/observeState`.
struct MobileQueueState: Equatable {
    let items: [MobileQueuedItem]
    let running: Bool
    let cursor: Int?

    /// Whether this turn currently accepts a queued item as steering.
    var steeringAvailable: Bool { running }

    /// Decodes one `SessionState` value.
    /// - Parameter value: state object yielded by `session/observeState` or `session/state`.
    /// - Returns: decoded state, or nil when the value is not a session state.
    static func decode(_ value: [String: Any]) -> MobileQueueState? {
        guard let running = value["running"] as? Bool else { return nil }
        let rawItems = value["queue"] as? [[String: Any]] ?? []
        let items = rawItems.compactMap { item -> MobileQueuedItem? in
            guard let id = MobileWireValue.string(item["id"]),
                  let placement = MobileWireValue.string(item["placement"]),
                  placement == "queued" || placement == "steering" else { return nil }
            let content = MobileMessageContent.parse(blocks: item["content"] as? [[String: Any]] ?? [])
            guard !content.text.isEmpty || !content.attachments.isEmpty else { return nil }
            return MobileQueuedItem(id: id, placement: placement,
                                    text: content.text, attachments: content.attachments)
        }
        return MobileQueueState(items: items, running: running,
                                cursor: MobileWireValue.int(value["cursor"]))
    }
}
