// TapgoTests/EvolutionEntryFilterTests.swift
import Foundation
import TapgoCore

/// Tests for `EvolutionEntryFilter` — the pure-Foundation search layer
/// behind the 「自进化日志」sheet's "按版本号 / commit / 改动关键词过滤"
/// feature (v0.5.38). If this drifts (e.g. accidentally becomes
/// case-sensitive, or starts matching whitespace queries), the in-app
/// filter UI quietly breaks for users. These pins the contract.

@MainActor
func runEvolutionEntryFilter(_ t: TestRunner) {
    let filter = EvolutionEntryFilter()

    // Sample fixtures covering every searchable field.
    let v37 = EvolutionEntry(
        version: "v0.5.37",
        date: "2026-08-30",
        commit: "ceb6e5b",
        tag: "v0.5.37",
        summary: "圆形额度表改显「剩余量」",
        changes: [
            "contextMeterChip 翻转：有额度数据时显示最差窗口剩余量",
            "无障碍标签同步：有额度数据时报「套餐余量 X%」"
        ],
        why: "同一个数字三种口径让用户无法直接对照。",
        next: "观察圆环填充方向语义。"
    )
    let v36 = EvolutionEntry(
        version: "v0.5.36",
        date: "2026-08-30",
        commit: "65c6444",
        tag: "v0.5.36",
        summary: "额度口径统一：弹窗余量卡片改显「剩余量」",
        changes: ["ModelUsagePopover.quotaCells() 展示层翻转：usedPercent → max(0, 100 - usedPercent)"],
        why: "同一个「剩余额度」标题下混用两种口径会让用户误读。",
        next: "真机确认弹窗与侧栏数字一致。"
    )
    let v35 = EvolutionEntry(
        version: "v0.5.35",
        date: "2026-08-30",
        commit: nil,
        tag: nil,
        summary: "接入 DeepSeek V4 系列",
        changes: ["config.toml 新增 [model_providers.deepseek]"],
        why: "V4 系列原生 Responses API 与 harness 0.149+ 零桥接兼容。",
        next: "deepseek-v4-flash-vision-exp 暂未接入。"
    )
    let history = [v37, v36, v35]

    // Empty / whitespace query never matches anything directly (and
    // filter(...) returns the input as-is).
    t.expect(!filter.matches(v37, query: ""),
                 "matches: empty query → false (single entry)")
    t.expect(!filter.matches(v37, query: "   "),
                 "matches: whitespace-only query → false")
    t.expectEqual(filter.filter(history, query: "").map(\.id),
                       history.map(\.id),
                       "filter: empty query preserves order and identity")
    t.expectEqual(filter.filter(history, query: "  \n\t ").map(\.id),
                       history.map(\.id),
                       "filter: whitespace query preserves order and identity")

    // Match by version (full + substring + case-insensitive).
    t.expect(filter.matches(v37, query: "v0.5.37"),
                 "matches: full version string")
    t.expect(filter.matches(v37, query: "0.5.37"),
                 "matches: version substring")
    t.expect(filter.matches(v37, query: "V0.5.37"),
                 "matches: version is case-insensitive")

    // Match by commit (full + partial).
    t.expect(filter.matches(v37, query: "ceb6e5b"),
                 "matches: full commit SHA")
    t.expect(filter.matches(v37, query: "ceb6"),
                 "matches: commit substring")

    // Match by tag.
    t.expect(filter.matches(v36, query: "v0.5.36"),
                 "matches: tag string")
    // The version field is always tested alongside tag — a tag-less entry
    // still matches its own version via the version field. Here we verify
    // the cross-field disambiguation instead: v36's `tag="v0.5.36"` must
    // not accidentally match unrelated entries via the tag field.
    let crossField = filter.filter([v37, v36, v35], query: "v0.5.36")
    t.expectEqual(crossField.map(\.version), ["v0.5.36"],
                       "filter: query 'v0.5.36' only matches the version (v36), not v37/v35")
    t.expect(!filter.matches(v35, query: "v0.5.36"),
                  "no-match: unrelated version string does not match a different entry")

    // Match by summary keyword (Chinese).
    t.expect(filter.matches(v37, query: "剩余量"),
                 "matches: summary substring (Chinese)")
    t.expect(filter.matches(v37, query: "剩余"),
                 "matches: partial summary substring")

    // Match by changes keyword (English + Chinese).
    t.expect(filter.matches(v36, query: "quotaCells"),
                 "matches: changes substring (identifier)")
    t.expect(filter.matches(v36, query: "100 -"),
                 "matches: changes substring (numeric)")
    t.expect(filter.matches(v35, query: "DeepSeek"),
                 "matches: changes substring (English)")

    // Match by why / next.
    t.expect(filter.matches(v37, query: "用户无法直接对照"),
                 "matches: why substring")
    t.expect(filter.matches(v35, query: "vision"),
                 "matches: next substring")

    // No-match on random keywords.
    t.expect(!filter.matches(v37, query: "kubernetes"),
                  "no-match: unrelated keyword")
    t.expect(!filter.matches(v35, query: "ceb6e5b"),
                  "no-match: only the entry with commit should match commit")

    // filter() end-to-end with active query.
    let onlyRemaining = filter.filter(history, query: "剩余量")
    t.expectEqual(onlyRemaining.map(\.version),
                       ["v0.5.37", "v0.5.36"],
                       "filter: 剩余量 hits both quota-realignment entries (summary), not v0.5.35")
    let onlyDeepSeek = filter.filter(history, query: "deepseek")
    t.expectEqual(onlyDeepSeek.map(\.version),
                       ["v0.5.35"],
                       "filter: deepseek only matches v0.5.35 (lowercased across all fields)")
    let onlyNext = filter.filter(history, query: "vision")
    t.expectEqual(onlyNext.map(\.version),
                       ["v0.5.35"],
                       "filter: vision matches the next field of v0.5.35 only")

    // No matches returns empty (UI renders 空态).
    t.expect(filter.filter(history, query: "kubernetes").isEmpty,
                 "filter: no-match returns empty list (UI empty state path)")

    // Identifiable id is stable across repeated access.
    t.expectEqual(v37.id, v37.commit,
                       "id: prefers commit when present")
    t.expectEqual(v35.id, "v0.5.35",
                       "id: falls back to version when commit missing")
}
