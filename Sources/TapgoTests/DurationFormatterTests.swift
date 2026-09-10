// TapgoTests/DurationFormatterTests.swift
import Foundation
import TapgoCore

@MainActor
func runDurationFormatter(_ t: TestRunner) {
    t.expectEqual(DurationFormatter.string(seconds: 5), "5 秒", "fmt: seconds")
    t.expectEqual(DurationFormatter.string(seconds: 65), "1 分 5 秒", "fmt: minutes")
    t.expectEqual(DurationFormatter.string(seconds: 3600), "1 小时", "fmt: hour")
    t.expectEqual(DurationFormatter.string(seconds: 3725), "1 小时 2 分 5 秒", "fmt: hour+min+sec")
    t.expectEqual(DurationFormatter.string(seconds: -3), "0 秒", "fmt: negative → 0s")
    // v0.5.210: 中间零值省略（对齐 Codex "1 小时" / "1 小时 5 秒" / "1 小时 2 分"）。
    t.expectEqual(DurationFormatter.string(seconds: 3660), "1 小时 1 分", "fmt: hour+min no sec")
    t.expectEqual(DurationFormatter.string(seconds: 3605), "1 小时 5 秒", "fmt: hour+sec no min")

    // Turn.duration / durationText.
    let t1 = Turn(
        id: "t", userInput: "x", status: .completed,
        startedAt: Date(timeIntervalSince1970: 1000),
        completedAt: Date(timeIntervalSince1970: 1012)
    )
    t.expectEqual(t1.duration ?? -1, TimeInterval(12), "turn: duration")
    t.expectEqual(t1.durationText ?? "nil", "12 秒", "turn: durationText")

    let running = Turn(id: "t2", userInput: "x", status: .running, startedAt: Date())
    t.expectNil(running.duration, "turn: running has no duration")
    t.expectNil(running.durationText, "turn: running has no durationText")
}
