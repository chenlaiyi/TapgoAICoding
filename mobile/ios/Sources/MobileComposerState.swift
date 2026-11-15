import Foundation

/// Reads the Host's existing projections; per-key cuts prevent late baselines from replacing newer changes.
struct MobileComposerState {
    private var cuts: [String: Int] = [:]
    private(set) var planActive = false
    private(set) var goalObjective: String?
    private(set) var goalPhase: String?

    mutating func restore(_ baseline: [String: Any]) {
        guard let seq = baseline["asOfSeq"] as? Int, let values = baseline["values"] as? [String: Any] else { return }
        for key in ["plan", "goal"] { replace(key, value: values[key], seq: seq) }
    }

    mutating func consume(_ frame: [String: Any]) {
        guard let seq = frame["seq"] as? Int, let changes = frame["changes"] as? [[String: Any]] else { return }
        for change in changes {
            guard let key = change["key"] as? String else { continue }
            replace(key, value: change["val"], seq: seq)
        }
    }

    private mutating func replace(_ key: String, value: Any?, seq: Int) {
        guard key == "plan" || key == "goal", seq >= (cuts[key] ?? -1) else { return }
        cuts[key] = seq
        let value = value as? [String: Any]
        switch key {
        case "plan": planActive = value?["active"] as? Bool ?? false
        case "goal":
            let goal = value?["goal"] as? [String: Any]
            goalObjective = goal?["objective"] as? String
            goalPhase = goal?["phase"] as? String
        default: break
        }
    }
}
