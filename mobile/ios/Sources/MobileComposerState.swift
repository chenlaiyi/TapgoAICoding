import Foundation

/// Reads the Host's existing projections; per-key cuts prevent late baselines from replacing newer changes.
struct MobileComposerState {
    private var cuts: [String: Int] = [:]
    private(set) var sessionTitle: String?
    private(set) var planActive = false
    private(set) var planPending = false
    private(set) var goalObjective: String?
    private(set) var goalPhase: String?
    private(set) var goalRoundsStarted: Int?
    private(set) var goalMaxRounds: Int?
    private(set) var imageLimits = MobileImageLimits.fallback

    mutating func restore(_ baseline: [String: Any]) {
        guard let seq = baseline["asOfSeq"] as? Int, let values = baseline["values"] as? [String: Any] else { return }
        for key in ["plan", "goal", "title", "imageLimits"] { replace(key, value: values[key], seq: seq) }
    }

    mutating func consume(_ frame: [String: Any]) {
        guard let seq = frame["seq"] as? Int, let changes = frame["changes"] as? [[String: Any]] else { return }
        for change in changes {
            guard let key = change["key"] as? String else { continue }
            replace(key, value: change["val"], seq: seq)
        }
    }

    private mutating func replace(_ key: String, value: Any?, seq: Int) {
        guard ["plan", "goal", "title", "imageLimits"].contains(key), seq >= (cuts[key] ?? -1) else { return }
        cuts[key] = seq
        let text = value as? String
        let value = value as? [String: Any]
        switch key {
        case "title": sessionTitle = text.flatMap { $0.isEmpty ? nil : $0 }
        case "plan":
            planActive = value?["active"] as? Bool ?? false
            planPending = value?["pending"] as? Bool ?? false
        case "goal":
            let goal = value?["goal"] as? [String: Any]
            goalObjective = goal?["objective"] as? String
            goalPhase = goal?["phase"] as? String
            goalRoundsStarted = value?["roundsStarted"] as? Int
            goalMaxRounds = goal?["maxGoalRounds"] as? Int
        case "imageLimits":
            if let value, let limits = MobileImageLimits(wire: value) { imageLimits = limits }
        default: break
        }
    }
}
