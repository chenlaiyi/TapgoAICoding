import Foundation

/// Places transcript rows by the event sequence that existed when their content started.
enum MobileTranscriptOrder {
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
