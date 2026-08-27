import Foundation
import SwiftUI
import TapgoCore

/// Tests for the global font-scale token defined in `Sources/TapgoCore/AppFont.swift`.
///
/// These are pure-logic tests — no SwiftUI rendering, no fonts on disk.
@MainActor
func runAppFontScaleTests(_ runner: TestRunner) {
    runner.section("AppFontScale: enum shape")

    // MARK: - allCases
    runner.expectEqual(AppFontScale.allCases.count, 3, "allCases has 3 elements")
    let rawValues = AppFontScale.allCases.map(\.rawValue)
    runner.expectEqual(rawValues, ["small", "medium", "large"], "rawValues in canonical order")

    // MARK: - Identifiable
    let ids = AppFontScale.allCases.map(\.id)
    runner.expectEqual(ids, ["small", "medium", "large"], "Identifiable.id mirrors rawValue")

    // MARK: - displayName
    runner.expectEqual(AppFontScale.small.displayName,  "小",  "small.displayName = 小")
    runner.expectEqual(AppFontScale.medium.displayName, "中", "medium.displayName = 中")
    runner.expectEqual(AppFontScale.large.displayName,  "大",  "large.displayName = 大")

    // MARK: - multiplier
    // small < medium < large, and medium is exactly 1.0 (the pre-feature UI).
    runner.expect(AppFontScale.small.multiplier < 1.0,
                  "small.multiplier < 1.0 (got \(AppFontScale.small.multiplier))")
    runner.expectEqual(AppFontScale.medium.multiplier, 1.0,
                       "medium.multiplier = 1.0 (pre-feature UI baseline)")
    runner.expect(AppFontScale.large.multiplier > 1.0,
                  "large.multiplier > 1.0 (got \(AppFontScale.large.multiplier))")
    // Sanity bounds — picked so small is still readable and large doesn't
    // break layout. Tighten if you change the values.
    runner.expect(AppFontScale.small.multiplier >= 0.8,
                  "small.multiplier >= 0.8 (got \(AppFontScale.small.multiplier))")
    runner.expect(AppFontScale.large.multiplier <= 1.3,
                  "large.multiplier <= 1.3 (got \(AppFontScale.large.multiplier))")

    // MARK: - RawRepresentable
    runner.expectEqual(AppFontScale(rawValue: "small"),  .small,  "rawValue 'small' → .small")
    runner.expectEqual(AppFontScale(rawValue: "medium"), .medium, "rawValue 'medium' → .medium")
    runner.expectEqual(AppFontScale(rawValue: "large"),  .large,  "rawValue 'large' → .large")
    runner.expectNil(AppFontScale(rawValue: "huge"), "rawValue 'huge' → nil")

    // MARK: - UserDefaults round-trip
    // Save and restore so other tests in the same process stay deterministic.
    let prior = UserDefaults.standard.string(forKey: AppFontScale.userDefaultsKey)
    defer {
        if let prior {
            UserDefaults.standard.set(prior, forKey: AppFontScale.userDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppFontScale.userDefaultsKey)
        }
    }
    runner.expectEqual(AppFontScale.userDefaultsKey, "tapgo.fontScale",
                       "userDefaultsKey constant matches @AppStorage sites")

    // Missing key → defaults to .medium.
    UserDefaults.standard.removeObject(forKey: AppFontScale.userDefaultsKey)
    runner.expectEqual(AppFontScale.current(), .medium, "current() defaults to .medium when key absent")

    // Valid raw values round-trip through UserDefaults.
    for s in AppFontScale.allCases {
        UserDefaults.standard.set(s.rawValue, forKey: AppFontScale.userDefaultsKey)
        runner.expectEqual(AppFontScale.current(), s, "current() = \(s.rawValue) after write")
    }
    // Garbage value → falls back to .medium rather than crashing.
    UserDefaults.standard.set("huge", forKey: AppFontScale.userDefaultsKey)
    runner.expectEqual(AppFontScale.current(), .medium, "current() falls back to .medium for invalid raw")

    // Restore for any later tests in the same process.
    UserDefaults.standard.removeObject(forKey: AppFontScale.userDefaultsKey)

    // MARK: - AppFont helper sanity (no rendering, just resolution)
    // AppFont.scaled returns a Font sized as baseSize * multiplier. We
    // can't easily introspect a SwiftUI.Font, but we CAN assert that the
    // helper doesn't crash for any (style, scale) combination and that
    // the helper accepts the public surface used by every view.
    let scales: [CGFloat] = [
        AppFontScale.small.multiplier,
        AppFontScale.medium.multiplier,
        AppFontScale.large.multiplier,
    ]
    let styles: [Font.TextStyle] = [
        .largeTitle, .title, .title2, .title3, .headline, .body,
        .callout, .subheadline, .footnote, .caption, .caption2,
    ]
    for style in styles {
        for m in scales {
            _ = AppFont.scaled(style, multiplier: m)
        }
    }
    for m in scales {
        _ = AppFont.monoScaled(size: 12, multiplier: m)
        _ = AppFont.monoScaled(size: 12, weight: .semibold, multiplier: m)
    }
    runner.expect(true, "AppFont helpers resolve for every (style × scale) combination")

    runner.endSection()
}
