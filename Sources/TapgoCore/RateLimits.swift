// TapgoCore/RateLimits.swift
//
// Wire models for `account/rateLimits/read` and the
// `account/rateLimits/updated` notification emitted by the
// codex app-server. Mirrors the documented Codex schema:
//
//   {
//     "rateLimits": {
//       "primary":   { "usedPercent": 25, "windowDurationMins": 300, "resetsAt": 1779752562 },
//       "secondary": { "usedPercent": 12, "windowDurationMins": 10080, "resetsAt": 1780339362 },
//       "credits":   { "hasCredits": false, "unlimited": false, "balance": "0" },
//       "planType":  "plus",
//       "rateLimitsByLimitId": { "codex": { ... } }
//     }
//   }
//
// Older harnesses may send only `primary` or omit `rateLimitsByLimitId`
// entirely, so every field is optional and `fromJSON` never throws.

import Foundation

/// A single rolling window (e.g. "5 hours" or "weekly") of consumption.
public struct RateLimitWindow: Hashable {
    /// 0-100, but the wire schema is untyped so we accept any Int.
    public let usedPercent: Int
    /// Window length in minutes (300 for 5h, 10080 for a week).
    public let windowDurationMins: Int
    /// Unix seconds when the window rolls over. `nil` if the harness omits it.
    public let resetsAt: Date?

    public init(usedPercent: Int, windowDurationMins: Int, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }

    /// Coarse pressure tier matching the colour scheme used by
    /// `TokenUsage.contextLevel`. The popover uses this to colour the
    /// capsule beneath each quota cell.
    public var level: ContextLevel {
        if usedPercent >= 80 { return .critical }
        if usedPercent >= 50 { return .warn }
        return .normal
    }

    /// Stable label for the window (e.g. "5 小时" / "每周"). Falls back to
    /// a minute count when the harness ships an unknown duration so the UI
    /// never has to special-case missing data.
    public var windowLabel: String {
        switch windowDurationMins {
        case 60: return "1 小时"
        case 300: return "5 小时"
        case 1440: return "每日"
        case 10080: return "每周"
        case let m where m > 0 && m % 1440 == 0: return "每 \(m / 1440) 天"
        case let m where m > 0: return "\(m) 分钟"
        default: return "窗口"
        }
    }
}

/// Purchased Credits balance (separate from the rate-limit windows).
public struct RateLimitsCredits: Hashable {
    public let hasCredits: Bool
    public let unlimited: Bool
    /// String balance because the harness sometimes serialises fractional
    /// or arbitrarily large values. Empty string when not provided.
    public let balance: String

    public init(hasCredits: Bool, unlimited: Bool, balance: String) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }

    /// True when the cell should be hidden entirely (no paid credits).
    public var isVisible: Bool { hasCredits || unlimited }
}

/// One entry under `rateLimitsByLimitId`. The schema reuses the same
/// window/credits shape per "limit id" (e.g. `codex`, `codex_mcp`).
public struct RateLimitsEntry: Hashable {
    public let limitId: String
    public let limitName: String?
    public let primary: RateLimitWindow?
    public let secondary: RateLimitWindow?
    public let credits: RateLimitsCredits?

    public init(
        limitId: String,
        limitName: String?,
        primary: RateLimitWindow?,
        secondary: RateLimitWindow?,
        credits: RateLimitsCredits?
    ) {
        self.limitId = limitId
        self.limitName = limitName
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
    }
}

/// Top-level snapshot. The UI binds to a single value of this type so it
/// can render the popover even before the first notification arrives.
public struct RateLimitsSnapshot: Hashable {
    public let primary: RateLimitWindow?
    public let secondary: RateLimitWindow?
    public let credits: RateLimitsCredits?
    public let planType: String?
    /// Per-limit-id entries (`codex`, MCP, etc.). May be empty.
    public let byLimitId: [RateLimitsEntry]
    /// Monotonic fetch timestamp so the popover can show "updated …" and
    /// avoid showing a value that's clearly stale.
    public let fetchedAt: Date

    public init(
        primary: RateLimitWindow?,
        secondary: RateLimitWindow?,
        credits: RateLimitsCredits?,
        planType: String?,
        byLimitId: [RateLimitsEntry],
        fetchedAt: Date
    ) {
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.planType = planType
        self.byLimitId = byLimitId
        self.fetchedAt = fetchedAt
    }

    /// Worst pressure across primary + secondary, so the circular meter
    /// can colour-shift before the user even opens the popover. `nil`
    /// when nothing is reported yet.
    public var worstUsedPercent: Int? {
        let values = [primary?.usedPercent, secondary?.usedPercent].compactMap { $0 }
        return values.max()
    }

    /// "Free" / "Plus" / "Pro" / etc. Falls back to the raw wire value.
    public var planLabel: String? {
        guard let raw = planType?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return raw.capitalized
    }

    /// Best-effort decode of the `rateLimits` payload. Returns nil only
    /// when there is literally nothing useful (every window absent and no
    /// credits) so the UI can hide the popover entirely.
    public static func fromJSON(_ value: JSONValue?) -> RateLimitsSnapshot? {
        guard let obj = value?.objectValue else { return nil }
        let primary = parseWindow(obj["primary"])
        let secondary = parseWindow(obj["secondary"])
        let credits = parseCredits(obj["credits"])
        let planType = obj["planType"]?.stringValue ?? obj["plan_type"]?.stringValue

        var byLimitId: [RateLimitsEntry] = []
        if let map = obj["rateLimitsByLimitId"]?.objectValue ?? obj["rate_limits_by_limit_id"]?.objectValue {
            for (id, raw) in map {
                guard let entryObj = raw.objectValue else { continue }
                let entry = RateLimitsEntry(
                    limitId: id,
                    limitName: entryObj["limitName"]?.stringValue
                        ?? entryObj["limit_name"]?.stringValue,
                    primary: parseWindow(entryObj["primary"]),
                    secondary: parseWindow(entryObj["secondary"]),
                    credits: parseCredits(entryObj["credits"])
                )
                byLimitId.append(entry)
            }
        }

        // Sort by id so the popover's grid order is stable across refreshes.
        byLimitId.sort { $0.limitId < $1.limitId }

        if primary == nil, secondary == nil, credits == nil, byLimitId.isEmpty {
            return nil
        }
        return RateLimitsSnapshot(
            primary: primary,
            secondary: secondary,
            credits: credits,
            planType: planType,
            byLimitId: byLimitId,
            fetchedAt: Date()
        )
    }

    private static func parseWindow(_ value: JSONValue?) -> RateLimitWindow? {
        guard let obj = value?.objectValue else { return nil }
        let used = obj["usedPercent"]?.intOrBoolAsInt
            ?? obj["used_percent"]?.intOrBoolAsInt
            ?? 0
        let mins = obj["windowDurationMins"]?.intOrBoolAsInt
            ?? obj["window_duration_mins"]?.intOrBoolAsInt
            ?? 0
        let resetsRaw = obj["resetsAt"]?.intOrBoolAsInt
            ?? obj["resets_at"]?.intOrBoolAsInt
        let resets = resetsRaw.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        if used == 0, mins == 0, resets == nil { return nil }
        return RateLimitWindow(usedPercent: used, windowDurationMins: mins, resetsAt: resets)
    }

    private static func parseCredits(_ value: JSONValue?) -> RateLimitsCredits? {
        guard let obj = value?.objectValue else { return nil }
        let has = obj["hasCredits"]?.boolValue
            ?? obj["has_credits"]?.boolValue
            ?? false
        let unlimited = obj["unlimited"]?.boolValue ?? false
        let balance = obj["balance"]?.stringValue ?? ""
        if !has && !unlimited && balance.isEmpty { return nil }
        return RateLimitsCredits(hasCredits: has, unlimited: unlimited, balance: balance)
    }
}

// MARK: - Display formatting

extension RateLimitsSnapshot {
    /// Compact "X%" caption for the circular meter badge.
    /// Falls back to context% when no rate limits have been reported yet.
    public func badgeText(fallbackContextPercent: Int?) -> String {
        if let worst = worstUsedPercent {
            return "\(worst)%"
        }
        if let pct = fallbackContextPercent {
            return "\(pct)%"
        }
        return "—"
    }

    /// Human-readable reset countdown, e.g. "重置于 02:31".
    /// Returns `nil` when the harness didn't include `resetsAt`.
    public static func resetCaption(for window: RateLimitWindow?, now: Date = Date()) -> String? {
        guard let resetsAt = window?.resetsAt else { return nil }
        let interval = resetsAt.timeIntervalSince(now)
        if interval <= 0 { return "即将重置" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        let value = formatter.string(from: interval) ?? "\(Int(interval / 60)) 分"
        return "重置于 \(value)"
    }
}

// MARK: - MiniMax (Token Plan / Coding Plan) → RateLimitsSnapshot mapper
//
// The popover used to read `account/rateLimits/read` off the Codex app-server,
// but that JSON-RPC endpoint only carries Codex-side quotas — it has no
// concept of MiniMax-M3's Token Plan subscription. The official MiniMax
// quota endpoint (`GET /v1/api/openplatform/coding_plan/remains`, auth via
// `Authorization: Bearer <key>`) instead exposes per-model
// `model_remains` entries. Each entry looks like:
//
//   {
//     "model_name": "MiniMax-M3",
//     "current_interval_total_count": 4500,
//     "current_interval_usage_count": 404,           // ⚠️ this is REMAINING, not used
//     "current_weekly_total_count": 157500,
//     "current_weekly_usage_count": 155640,         // ⚠️ REMAINING
//     "end_time": 1756660800,
//     "plan_name": "Plus"
//   }
//
// Despite the `_usage_` suffix, both `_count` fields hold **remaining** quota;
// the "used" count must be derived as `total - remaining`. Centralising that
// here keeps the SwiftUI layer oblivious to MiniMax's inverted naming.
public enum MiniMaxQuotaSnapshotBuilder {
    /// Convert a single `model_remains` entry into a `RateLimitsSnapshot`
    /// matching the existing popover vocabulary. `now` is propagated as the
    /// snapshot's `fetchedAt` so the popover can show "重置于" countdowns
    /// relative to the same instant the data was pulled.
    public static func build(from entry: [String: Any], now: Date) -> RateLimitsSnapshot {
        let primary = makeWindow(
            total: intValue(entry["current_interval_total_count"]),
            remaining: intValue(entry["current_interval_usage_count"]),
            // MiniMax-M3 是文本模型，按 5 小时周期渲染。
            windowDurationMins: 300,
            resetsAt: dateValue(entry["end_time"])
        )
        let secondary = makeWindow(
            total: intValue(entry["current_weekly_total_count"]),
            remaining: intValue(entry["current_weekly_usage_count"]),
            windowDurationMins: 10080,
            resetsAt: nil  // 周配额没有具体 reset 时间，弹窗 caption 自动回落
        )
        let planType = (entry["plan_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Token Plan 没有 Credits 概念（按 token 扣费），隐藏 credits cell。
        return RateLimitsSnapshot(
            primary: primary,
            secondary: secondary,
            credits: nil,
            planType: planType?.isEmpty == false ? planType : nil,
            byLimitId: [],
            fetchedAt: now
        )
    }

    private static func makeWindow(
        total: Int?,
        remaining: Int?,
        windowDurationMins: Int,
        resetsAt: Date?
    ) -> RateLimitWindow? {
        guard let total, total > 0 else { return nil }
        let remaining = remaining ?? 0
        // used = total - remaining, 但要防御两类服务端异常:
        //   - remaining < 0   → 视为 100% 用尽
        //   - remaining > total → 视为 100% 用尽 (与负向越界同样处理)
        // 留 `remaining == total` 走常规路径 (代表未使用, 0% used)。
        let used: Int
        if remaining < 0 {
            used = total            // 负数 → 满
        } else if remaining > total {
            used = total            // 超过总额 → 满
        } else {
            used = total - remaining
        }
        let pct = Int((Double(used) / Double(total) * 100).rounded())
        return RateLimitWindow(
            usedPercent: max(0, min(100, pct)),
            windowDurationMins: windowDurationMins,
            resetsAt: resetsAt
        )
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let i = raw as? Int { return i }
        if let d = raw as? Double { return Int(d) }
        if let s = raw as? String { return Int(s) }
        if let n = raw as? NSNumber { return n.intValue }
        return nil
    }

    private static func dateValue(_ raw: Any?) -> Date? {
        guard let intVal = intValue(raw) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(intVal))
    }
}
