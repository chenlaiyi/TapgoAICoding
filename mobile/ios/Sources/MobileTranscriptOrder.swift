import Foundation

/// Places transcript rows by the event sequence that existed when their content started.
enum MobileTranscriptOrder {
    /// Whether a new step process row may extend the preceding one.
    /// - Parameters:
    ///   - lastRole: role of the last transcript row.
    ///   - lastTurn: turn of that row, when it has one.
    ///   - turn: turn of the step being appended.
    /// - Returns: true when no reply text separates the two steps.
    static func canMergeProcess(lastRole: String?, lastTurn: Int?, turn: Int) -> Bool {
        lastRole == "process" && lastTurn == turn
    }

    /// Placement of the live reply text: above its step process row until the step settles.
    /// - Parameters:
    ///   - processIndex: the running step's process row, when one exists.
    ///   - fallback: insertion index used when the step has no process row yet.
    /// - Returns: the index where the live text is inserted.
    static func liveTextIndex(processIndex: Int?, fallback: Int) -> Int {
        processIndex ?? fallback
    }

    /// Index after the last row that existed at `sequence`.
    /// - Parameters:
    ///   - ids: transcript row identities in display order; synthesized rows are negative.
    ///   - sequence: event sequence the new row's content started after.
    /// - Returns: index in `ids` where the row belongs.
    static func insertionIndex(ids: [Int], after sequence: Int) -> Int {
        for index in ids.indices.reversed() where ids[index] >= 0 && ids[index] <= sequence {
            return index + 1
        }
        return 0
    }
}
