import Foundation

/// A user-defined scheduled task: when fired, injects `prompt` into either
/// a freshly-created thread or a pinned thread. Persisted as one JSON file
/// per task under `~/Library/Application Support/Tapgo AICoding/state/v1/scheduled-tasks/<id>.json`.
public struct ScheduledTask: Codable, Identifiable, Equatable {
    public var id: UUID
    /// Human-friendly label shown in the sidebar list.
    public var name: String
    /// Prompt text to inject. Required.
    public var prompt: String
    /// When the task fires.
    public var schedule: ScheduleSpec
    /// nil → always spawn a new thread per fire; non-nil → inject into this thread.
    public var targetThreadId: UUID?
    /// nil preserves legacy prompt-based execution; opening an app runs natively.
    public var applicationBundleIdentifier: String?
    /// Soft kill-switch without deleting the task.
    public var enabled: Bool
    /// Last time the runner fired this task. nil = never.
    public var lastFiredAt: Date?
    /// Cached "next time to fire" computed at load and after each fire.
    public var nextFireAt: Date?
    /// Bounded ring of recent fire outcomes (capped at 5). Optional so legacy
    /// task files written before v0.5.105 decode without a custom init(from:).
    public var executionHistory: [ExecutionRecord]?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        schedule: ScheduleSpec,
        targetThreadId: UUID? = nil,
        applicationBundleIdentifier: String? = nil,
        enabled: Bool = true,
        lastFiredAt: Date? = nil,
        nextFireAt: Date? = nil,
        executionHistory: [ExecutionRecord]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.schedule = schedule
        self.targetThreadId = targetThreadId
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.enabled = enabled
        self.lastFiredAt = lastFiredAt
        self.nextFireAt = nextFireAt
        self.executionHistory = executionHistory
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Resolved history with legacy tasks (no field) treated as empty.
    public var resolvedHistory: [ExecutionRecord] { executionHistory ?? [] }
}

/// One fire outcome. Capped to 5 per task by `ScheduledTaskBridge.recordOutcome`.
public struct ExecutionRecord: Codable, Equatable {
    public var firedAt: Date
    public var outcome: Outcome
    /// How long the inject call took. nil for manual "立即运行" where we don't measure.
    public var durationMs: Int?
    /// Free-form error message when outcome == .failure.
    public var errorMessage: String?

    public enum Outcome: String, Codable, Equatable { case success, failure, skipped }

    public init(firedAt: Date, outcome: Outcome, durationMs: Int? = nil, errorMessage: String? = nil) {
        self.firedAt = firedAt
        self.outcome = outcome
        self.durationMs = durationMs
        self.errorMessage = errorMessage
    }
}

/// When the task fires. Stored as a discriminated Codable enum so future
/// kinds (cron, weekday windows, etc.) don't break existing files.
public enum ScheduleSpec: Codable, Equatable {
    /// Fire once at the given wall-clock time.
    case oneShot(Date)
    /// Fire every day at hour:minute (local time).
    case daily(hour: Int, minute: Int)
    /// Fire every `seconds` from `lastFiredAt` (or `createdAt`).
    case interval(seconds: TimeInterval)
    /// Fire on the given weekday (1=Sun, 7=Sat per Calendar) at hour:minute local.
    case weekly(weekday: Int, hour: Int, minute: Int)
    /// Monday through Friday, excluding Saturday and Sunday (not public holidays).
    case weekdays(hour: Int, minute: Int)

    private enum Kind: String, Codable { case oneShot, daily, interval, weekly, weekdays }

    private enum CodingKeys: String, CodingKey { case kind, fireAt, hour, minute, seconds, weekday }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .oneShot:
            self = .oneShot(try c.decode(Date.self, forKey: .fireAt))
        case .weekdays:
            self = .weekdays(hour: try c.decode(Int.self, forKey: .hour), minute: try c.decode(Int.self, forKey: .minute))
        case .daily:
            self = .daily(hour: try c.decode(Int.self, forKey: .hour),
                          minute: try c.decode(Int.self, forKey: .minute))
        case .interval:
            self = .interval(seconds: try c.decode(TimeInterval.self, forKey: .seconds))
        case .weekly:
            self = .weekly(weekday: try c.decode(Int.self, forKey: .weekday),
                           hour: try c.decode(Int.self, forKey: .hour),
                           minute: try c.decode(Int.self, forKey: .minute))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .oneShot(let d):
            try c.encode(Kind.oneShot, forKey: .kind); try c.encode(d, forKey: .fireAt)
        case .weekdays(let h, let m):
            try c.encode(Kind.weekdays, forKey: .kind); try c.encode(h, forKey: .hour); try c.encode(m, forKey: .minute)
        case .daily(let h, let m):
            try c.encode(Kind.daily, forKey: .kind); try c.encode(h, forKey: .hour); try c.encode(m, forKey: .minute)
        case .interval(let s):
            try c.encode(Kind.interval, forKey: .kind); try c.encode(s, forKey: .seconds)
        case .weekly(let wd, let h, let m):
            try c.encode(Kind.weekly, forKey: .kind)
            try c.encode(wd, forKey: .weekday); try c.encode(h, forKey: .hour); try c.encode(m, forKey: .minute)
        }
    }

    /// Human-readable description (used in list rows + ScheduleSpecTests).
    public var label: String {
        switch self {
        case .oneShot(let d):
            let f = DateFormatter()
            f.dateStyle = .short; f.timeStyle = .short
            return "一次性 · \(f.string(from: d))"
        case .weekdays(let h, let m):
            return String(format: "周一至周五 %02d:%02d", h, m)
        case .daily(let h, let m):
            return String(format: "每天 %02d:%02d", h, m)
        case .interval(let s):
            if s < 60 { return "每 \(Int(s)) 秒" }
            if s < 3600 { return "每 \(Int(s / 60)) 分钟" }
            return "每 \(Int(s / 3600)) 小时"
        case .weekly(let wd, let h, let m):
            let names = ["日","一","二","三","四","五","六"]
            let idx = max(0, min(6, wd - 1))
            // String interpolation (not String(format:%s)) because %s needs a C string.
            return "每\(names[idx]) \(String(format: "%02d:%02d", h, m))"
        }
    }

    /// Compute the next wall-clock time at which this spec should fire,
    /// given a reference "now" and a "from" origin (lastFiredAt or createdAt
    /// for interval-style). Returns nil if the spec is expired (oneShot in
    /// the past) or never (oneShot in the past and we should disable).
    public func nextFire(after now: Date, lastFired: Date?) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        switch self {
        case .oneShot(let d):
            return d > now ? d : nil
        case .weekdays(let h, let m):
            guard (0...23).contains(h), (0...59).contains(m) else { return nil }
            return (2...6).compactMap { weekday in
                cal.nextDate(after: now, matching: DateComponents(hour: h, minute: m, second: 0, weekday: weekday), matchingPolicy: .nextTime)
            }.min()
        case .daily(let h, let m):
            guard (0...23).contains(h), (0...59).contains(m) else { return nil }
            // Today at h:m, else tomorrow at h:m
            var comp = cal.dateComponents([.year, .month, .day], from: now)
            comp.hour = h; comp.minute = m; comp.second = 0
            if let today = cal.date(from: comp), today > now { return today }
            return cal.date(byAdding: .day, value: 1, to: cal.date(from: comp)!)
        case .weekly(let wd, let h, let m):
            guard (1...7).contains(wd), (0...23).contains(h), (0...59).contains(m) else { return nil }
            var comp = cal.dateComponents([.year, .month, .day], from: now)
            comp.hour = h; comp.minute = m; comp.second = 0
            let today = cal.date(from: comp)!
            let curWd = cal.component(.weekday, from: now)
            var delta = (wd - curWd + 7) % 7
            if delta == 0 && today <= now { delta = 7 }
            return cal.date(byAdding: .day, value: delta, to: today)
        case .interval(let s):
            guard s > 0 else { return nil }
            let origin = lastFired ?? now
            let next = origin.addingTimeInterval(s)
            return next > now ? next : now.addingTimeInterval(s)
        }
    }
}
