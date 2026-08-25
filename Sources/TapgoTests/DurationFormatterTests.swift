// TapgoTests/DurationFormatterTests.swift
import Foundation
import TapgoCore

@MainActor
func runDurationFormatter(_ t: TestRunner) {
    t.expectEqual(DurationFormatter.string(seconds: 5), "5s", "fmt: seconds")
    t.expectEqual(DurationFormatter.string(seconds: 65), "1m 05s", "fmt: minutes")
    t.expectEqual(DurationFormatter.string(seconds: 3600), "1h 00m", "fmt: hour")
    t.expectEqual(DurationFormatter.string(seconds: 3725), "1h 02m", "fmt: hour+min")
    t.expectEqual(DurationFormatter.string(seconds: -3), "0s", "fmt: negative → 0s")

    // Turn.duration / durationText.
    let t1 = Turn(
        id: "t", userInput: "x", status: .completed,
        startedAt: Date(timeIntervalSince1970: 1000),
        completedAt: Date(timeIntervalSince1970: 1012)
    )
    t.expectEqual(t1.duration ?? -1, TimeInterval(12), "turn: duration")
    t.expectEqual(t1.durationText ?? "nil", "12s", "turn: durationText")

    let running = Turn(id: "t2", userInput: "x", status: .running, startedAt: Date())
    t.expectNil(running.duration, "turn: running has no duration")
    t.expectNil(running.durationText, "turn: running has no durationText")
}
