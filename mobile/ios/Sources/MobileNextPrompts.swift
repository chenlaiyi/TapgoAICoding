import Foundation

/// Latest completed turn's recommendations; selecting one only edits the local draft.
struct MobileNextPrompts: Equatable {
    private(set) var turn: Int?
    private(set) var prompts: [String] = []
    private(set) var failed = false

    mutating func consume(_ event: [String: Any]) {
        guard let type = event["type"] as? String, let data = event["data"] as? [String: Any] else { return }
        if type == "turn/start", let current = data["turn"] as? Int {
            turn = current
            prompts = []
            failed = false
        } else if type == "session/next-prompts-result", let current = data["turn"] as? Int, current == turn {
            restore(data, running: false)
        }
    }

    mutating func restore(_ value: [String: Any]?, running: Bool) {
        guard !running, let value, let current = value["turn"] as? Int, current >= 0,
              let status = value["status"] as? String, ["idle", "ready", "error"].contains(status),
              let raw = value["prompts"] as? [String], raw.count <= 3 else { return }
        let normalized = raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard normalized.allSatisfy({ !$0.isEmpty }) else { return }
        turn = current
        prompts = status == "ready" ? normalized.reduce(into: []) { result, prompt in
            if !result.contains(prompt) { result.append(prompt) }
        } : []
        failed = status == "error"
    }

    static func appending(_ prompt: String, to draft: String) -> String {
        draft.isEmpty ? prompt : draft + "\n\n" + prompt
    }
}
