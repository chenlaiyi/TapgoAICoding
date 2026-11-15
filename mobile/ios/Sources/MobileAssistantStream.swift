import Foundation

/// Folds the Host's dense assistant-attempt frames; gaps require a fresh follow baseline.
struct MobileAssistantStream {
    enum Change: Equatable {
        case ignored, updated, abandoned, resync
        case committed(sequence: Int, eventType: String)
    }
    private(set) var attemptID: String?
    private(set) var turn: Int?
    private(set) var step: Int?
    private(set) var revision = 0
    private(set) var nextIndex = 0
    private(set) var startedAfterSequence = -1
    private(set) var active = false
    private var textBlocks: [Int: String] = [:]
    private var reasoningBlocks: [Int: String] = [:]

    var text: String { textBlocks.keys.sorted().compactMap { textBlocks[$0] }.joined(separator: "\n\n") }
    var reasoning: String { reasoningBlocks.keys.sorted().compactMap { reasoningBlocks[$0] }.joined(separator: "\n\n") }

    mutating func retire() {
        attemptID = nil
        turn = nil
        step = nil
        active = false
        nextIndex = 0
        textBlocks = [:]
        reasoningBlocks = [:]
    }

    mutating func receive(_ frame: [String: Any]) -> Change {
        guard let type = frame["type"] as? String,
              let id = frame["attemptId"] as? String, !id.isEmpty,
              let incomingRevision = frame["revision"] as? Int, incomingRevision >= 1 else { return .resync }
        let lifecycleRestart = type == "start" && incomingRevision == 1
        if lifecycleRestart && attemptID == id { return .ignored }
        if !lifecycleRestart && incomingRevision <= revision { return .ignored }
        guard lifecycleRestart || incomingRevision == revision + 1 else { return .resync }
        switch type {
        case "start":
            guard let turn = frame["turn"] as? Int, turn >= 1,
                  let step = frame["step"] as? Int, step >= 1,
                  let after = frame["startedAfterSeq"] as? Int, after >= -1,
                  !active || lifecycleRestart else { return .resync }
            retire()
            self.turn = turn
            self.step = step
            attemptID = id
            startedAfterSequence = after
            active = true
            revision = incomingRevision
            return .updated
        case "chunk":
            guard active, attemptID == id,
                  let index = frame["index"] as? Int, index == nextIndex,
                  let chunk = frame["chunk"] as? [String: Any], append(chunk) else { return .resync }
            nextIndex += 1
            revision = incomingRevision
            return .updated
        case "end":
            guard active, attemptID == id, frame["index"] as? Int == nextIndex,
                  let outcome = frame["outcome"] as? [String: Any] else { return .resync }
            if outcome["kind"] as? String == "abandoned" {
                revision = incomingRevision
                retire()
                return .abandoned
            }
            guard outcome["kind"] as? String == "committed", let seq = outcome["seq"] as? Int, seq >= 0,
                  let eventType = outcome["eventType"] as? String,
                  eventType == "assistant/message" || eventType == "assistant/attempt" else { return .resync }
            revision = incomingRevision
            active = false
            return .committed(sequence: seq, eventType: eventType)
        default: return .resync
        }
    }

    /// Matches only a settlement belonging to the active turn and step after its opening cursor.
    func matches(_ event: [String: Any]) -> Bool {
        guard active, let type = event["type"] as? String,
              type == "assistant/message" || type == "assistant/attempt",
              let seq = event["seq"] as? Int, seq > startedAfterSequence,
              let data = event["data"] as? [String: Any],
              data["turn"] as? Int == turn, data["step"] as? Int == step else { return false }
        if type == "assistant/message", event["surfaceOp"] != nil {
            return event["surfaceOp"] as? String == "append"
        }
        return true
    }

    /// Replaces the live prefix atomically; compact records must account for every dense chunk index.
    mutating func restore(_ baseline: [String: Any]?) -> Bool {
        var restored = MobileAssistantStream()
        guard let baseline else { self = restored; return true }
        guard let revision = baseline["revision"] as? Int, revision >= 0 else { return false }
        restored.revision = revision
        guard let value = baseline["activeAttempt"] else { self = restored; return true }
        guard let attempt = value as? [String: Any], let id = attempt["attemptId"] as? String, !id.isEmpty,
              let turn = attempt["turn"] as? Int, turn >= 1, let step = attempt["step"] as? Int, step >= 1,
              let after = attempt["startedAfterSeq"] as? Int, after >= -1,
              let next = attempt["nextIndex"] as? Int, next >= 0,
              let records = attempt["stream"] as? [[String: Any]] else { return false }
        restored.attemptID = id
        restored.turn = turn
        restored.step = step
        restored.startedAfterSequence = after
        restored.active = true
        for record in records {
            switch record["type"] as? String {
            case "text-chunks", "reasoning-chunks":
                guard let texts = record["texts"] as? [String], !texts.isEmpty,
                      let index = record["index"] as? Int, index >= 0 else { return false }
                for text in texts {
                    let type = record["type"] as? String == "text-chunks" ? "text-delta" : "reasoning-delta"
                    guard restored.append(["type": type, "index": index, "text": text]) else { return false }
                    restored.nextIndex += 1
                }
            case "tool-call-chunks":
                guard let args = record["args"] as? [String], !args.isEmpty else { return false }
                restored.nextIndex += args.count
            case "chunk":
                guard let chunk = record["chunk"] as? [String: Any], restored.append(chunk) else { return false }
                restored.nextIndex += 1
            default: return false
            }
        }
        guard restored.nextIndex == next else { return false }
        self = restored
        return true
    }

    private mutating func append(_ chunk: [String: Any]) -> Bool {
        guard let type = chunk["type"] as? String else { return false }
        guard type == "text-delta" || type == "reasoning-delta" else { return true }
        guard let text = chunk["text"] as? String, let index = chunk["index"] as? Int, index >= 0 else { return false }
        if type == "text-delta" { textBlocks[index, default: ""] += text }
        else { reasoningBlocks[index, default: ""] += text }
        return true
    }
}
