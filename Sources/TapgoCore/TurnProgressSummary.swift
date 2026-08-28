import Foundation

/// Codex-style live progress derived from the app-server's replace-in-place
/// `turn/plan/updated` and `turn/diff/updated` snapshots.
public struct TurnProgressSummary: Hashable, Sendable {
    public enum StepStatus: String, Hashable, Sendable {
        case pending
        case inProgress
        case completed
    }

    public struct Step: Identifiable, Hashable, Sendable {
        public let id: Int
        public let text: String
        public let status: StepStatus

        public init(id: Int, text: String, status: StepStatus) {
            self.id = id
            self.text = text
            self.status = status
        }
    }

    public let id: String
    public let steps: [Step]
    public let changedFiles: Int
    public let additions: Int
    public let deletions: Int

    public var currentStepNumber: Int {
        if let index = steps.firstIndex(where: { $0.status == .inProgress }) {
            return index + 1
        }
        if let index = steps.firstIndex(where: { $0.status == .pending }) {
            return index + 1
        }
        return steps.count
    }

    public var completedSteps: Int {
        steps.filter { $0.status == .completed }.count
    }

    public init?(turn: Turn) {
        self.init(id: turn.id, items: turn.items)
    }

    public init?(id: String, items: [TurnItem]) {
        let parsedSteps = Self.planSteps(in: items)
        guard !parsedSteps.isEmpty else { return nil }
        let stats = Self.changeStats(in: items)
        self.id = id
        steps = parsedSteps
        changedFiles = stats.files
        additions = stats.additions
        deletions = stats.deletions
    }

    private static func planSteps(in items: [TurnItem]) -> [Step] {
        let result = items.reversed().compactMap { item -> String? in
            guard case .toolCall(let call) = item,
                  item.isPlanSnapshot else { return nil }
            return call.result
        }.first
        guard let result else { return [] }

        var steps: [Step] = []
        for rawLine in result.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let marker = line.first else { continue }
            let status: StepStatus
            switch marker {
            case "✓": status = .completed
            case "→": status = .inProgress
            case "○": status = .pending
            default: continue
            }
            let text = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            steps.append(Step(id: steps.count, text: text, status: status))
        }
        return steps
    }

    private static func changeStats(in items: [TurnItem]) -> (files: Int, additions: Int, deletions: Int) {
        if let aggregate = items.reversed().compactMap({ item -> FileChange? in
            guard case .fileChange(let change) = item,
                  item.isTurnDiffSnapshot else { return nil }
            return change
        }).first {
            let files = DiffParser.parse(aggregate.diff)
            if !files.isEmpty {
                return (
                    Set(files.map(\.displayPath)).count,
                    files.reduce(0) { $0 + $1.totalAdditions },
                    files.reduce(0) { $0 + $1.totalRemovals }
                )
            }
        }

        if let fallback = items.reversed().compactMap({ item -> String? in
            guard case .toolCall(let call) = item,
                  item.isWorktreeStatsSnapshot else { return nil }
            return call.result
        }).first,
           let parsed = parseWorktreeStats(fallback) {
            return parsed
        }

        let changes = items.compactMap { item -> FileChange? in
            guard case .fileChange(let change) = item,
                  !item.isTurnDiffSnapshot else { return nil }
            return change
        }
        var paths: Set<String> = []
        var additions = 0
        var deletions = 0
        for change in changes {
            paths.insert(change.path)
            let files = DiffParser.parse(change.diff)
            if files.isEmpty {
                let raw = rawLineCounts(change.diff)
                additions += raw.additions
                deletions += raw.deletions
            } else {
                additions += files.reduce(0) { $0 + $1.totalAdditions }
                deletions += files.reduce(0) { $0 + $1.totalRemovals }
            }
        }
        return (paths.count, additions, deletions)
    }

    private static func parseWorktreeStats(
        _ text: String
    ) -> (files: Int, additions: Int, deletions: Int)? {
        var values: [String: Int] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let value = Int(parts[1]) else { continue }
            values[String(parts[0])] = value
        }
        guard let files = values["files"],
              let additions = values["additions"],
              let deletions = values["deletions"] else { return nil }
        return (files, additions, deletions)
    }

    private static func rawLineCounts(_ diff: String) -> (additions: Int, deletions: Int) {
        var additions = 0
        var deletions = 0
        for line in diff.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("+") && !line.hasPrefix("+++") { additions += 1 }
            if line.hasPrefix("-") && !line.hasPrefix("---") { deletions += 1 }
        }
        return (additions, deletions)
    }
}
