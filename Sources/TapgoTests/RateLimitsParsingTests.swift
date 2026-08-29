// TapgoTests/RateLimitsParsingTests.swift
import Foundation
@testable import TapgoCore

@MainActor
func runRateLimitsParsing(_ t: TestRunner) {
    // Full Codex app-server shape (camelCase).
    let payload: JSONValue = .object([
        "rateLimits": .object([
            "primary": .object([
                "usedPercent": .int(42),
                "windowDurationMins": .int(300),
                "resetsAt": .int(1_779_752_562),
            ]),
            "secondary": .object([
                "usedPercent": .int(7),
                "windowDurationMins": .int(10080),
                "resetsAt": .int(1_780_339_362),
            ]),
            "credits": .object([
                "hasCredits": .bool(true),
                "unlimited": .bool(false),
                "balance": .string("12.50"),
            ]),
            "planType": .string("plus"),
            "rateLimitsByLimitId": .object([
                "codex": .object([
                    "limitName": .string("Codex"),
                    "primary": .object([
                        "usedPercent": .int(42),
                        "windowDurationMins": .int(300),
                        "resetsAt": .int(1_779_752_562),
                    ]),
                ]),
            ]),
        ])
    ])

    let snap = RateLimitsSnapshot.fromJSON(payload.objectValue?["rateLimits"])
    t.expectNotNil(snap, "rate limits: camelCase parsed")
    t.expectEqual(snap?.primary?.usedPercent ?? -1, 42, "primary: usedPercent")
    t.expectEqual(snap?.primary?.windowDurationMins ?? -1, 300, "primary: windowDurationMins")
    t.expectEqual(snap?.primary?.windowLabel ?? "", "5 小时", "primary: windowLabel")
    t.expectEqual(snap?.secondary?.windowLabel ?? "", "每周", "secondary: windowLabel")
    t.expectEqual(snap?.secondary?.usedPercent ?? -1, 7, "secondary: usedPercent")
    t.expectEqual(snap?.credits?.balance ?? "", "12.50", "credits: balance")
    t.expectEqual(snap?.credits?.hasCredits ?? false, true, "credits: hasCredits")
    t.expectEqual(snap?.planLabel ?? "", "Plus", "planLabel capitalised")
    t.expectEqual(snap?.byLimitId.count ?? -1, 1, "byLimitId: 1 entry")
    t.expectEqual(snap?.byLimitId.first?.limitId ?? "", "codex", "byLimitId[0]: id")
    t.expectEqual(snap?.worstUsedPercent ?? -1, 42, "worstUsedPercent picks primary")

    // snake_case fallback (older harness).
    let snake: JSONValue = .object([
        "rate_limits": .object([
            "primary": .object([
                "used_percent": .int(99),
                "window_duration_mins": .int(60),
                "resets_at": .int(1_779_752_562),
            ]),
        ])
    ])
    let s2 = RateLimitsSnapshot.fromJSON(snake.objectValue?["rate_limits"])
    t.expectNotNil(s2, "rate limits: snake_case parsed")
    t.expectEqual(s2?.primary?.usedPercent ?? -1, 99, "snake primary: used")
    t.expectEqual(s2?.primary?.windowLabel ?? "", "1 小时", "snake primary: label")

    // Empty payload → nil so the popover shows "等待首次订阅用量上报".
    t.expectNil(RateLimitsSnapshot.fromJSON(nil), "nil payload → nil")
    t.expectNil(RateLimitsSnapshot.fromJSON(.object([:])), "empty object → nil")

    // Level thresholds (parity with TokenUsage.contextLevel).
    t.expectEqual(RateLimitWindow(usedPercent: 30, windowDurationMins: 300, resetsAt: nil).level, .normal, "30% normal")
    t.expectEqual(RateLimitWindow(usedPercent: 60, windowDurationMins: 300, resetsAt: nil).level, .warn, "60% warn")
    t.expectEqual(RateLimitWindow(usedPercent: 85, windowDurationMins: 300, resetsAt: nil).level, .critical, "85% critical")

    // Credits.isVisible gates the third cell.
    t.expectEqual(RateLimitsCredits(hasCredits: false, unlimited: false, balance: "0").isVisible, false, "credits hidden when none")
    t.expectEqual(RateLimitsCredits(hasCredits: true, unlimited: false, balance: "5").isVisible, true, "credits shown when hasCredits")
    t.expectEqual(RateLimitsCredits(hasCredits: false, unlimited: true, balance: "").isVisible, true, "credits shown when unlimited")

    // badgeText fallback order: worst rate-limit > context% > "—".
    let badgeSnap = RateLimitsSnapshot(
        primary: RateLimitWindow(usedPercent: 60, windowDurationMins: 300, resetsAt: nil),
        secondary: nil, credits: nil, planType: nil, byLimitId: [], fetchedAt: Date()
    )
    t.expectEqual(badgeSnap.badgeText(fallbackContextPercent: 80), "60%", "badge: rate-limit wins over context")
    let empty = RateLimitsSnapshot(primary: nil, secondary: nil, credits: nil, planType: nil, byLimitId: [], fetchedAt: Date())
    t.expectEqual(empty.badgeText(fallbackContextPercent: 33), "33%", "badge: falls back to context")
    t.expectEqual(empty.badgeText(fallbackContextPercent: nil), "—", "badge: em-dash when nothing")

    // resetCaption: present + within a few hours.
    let inTwoHours = Date().addingTimeInterval(2 * 3600)
    let window = RateLimitWindow(usedPercent: 42, windowDurationMins: 300, resetsAt: inTwoHours)
    let caption = RateLimitsSnapshot.resetCaption(for: window)
    t.expect(caption?.contains("重置于") == true, "reset caption includes 重置于")

    // resetCaption: nil resetsAt → nil caption (no "重置于" decoration).
    let noReset = RateLimitWindow(usedPercent: 42, windowDurationMins: 300, resetsAt: nil)
    t.expectNil(RateLimitsSnapshot.resetCaption(for: noReset), "reset caption nil when resetsAt absent")

    // windowLabel for unknown duration (custom minutes).
    let customWindow = RateLimitWindow(usedPercent: 10, windowDurationMins: 90, resetsAt: nil)
    t.expectEqual(customWindow.windowLabel, "90 分钟", "windowLabel: custom minutes")
}
