// TapgoTests/ReasoningMergeTests.swift
import Foundation
import TapgoCore

@MainActor
func runReasoningMerge(_ t: TestRunner) {
    // A streamed trace wins — we don't throw it away for the summary.
    let a = ReasoningMerge.finalizeText(streamed: "step 1\nstep 2", summary: ["summary line"])
    t.expectEqual(a, "step 1\nstep 2", "merge: streamed trace kept")

    // Whitespace-only streamed → summary used (nothing meaningful streamed).
    let b = ReasoningMerge.finalizeText(streamed: "   \n", summary: ["condensed"])
    t.expectEqual(b, "condensed", "merge: whitespace streamed → summary")

    // No streamed at all → summary joined.
    let c = ReasoningMerge.finalizeText(streamed: "", summary: ["a", "b"])
    t.expectEqual(c, "a\nb", "merge: empty streamed → summary joined")
}
