import Foundation

/// Five-second polling loop that watches `ScheduledTaskStore` and fires any
/// task whose `nextFireAt` is in the past. Decoupled from the UI: it just
/// invokes `onFire` (a closure set by the App) which is responsible for
/// routing the prompt to the right `SessionStore`/thread.
///
/// On fire:
/// - mark `lastFiredAt = now`, recompute `nextFireAt`, persist
/// - call `onFire(task)`; the caller can show notifications / log
///
/// A five-second tick keeps minute-level schedules close to their specified
/// time without pinning a thread. A oneShot
/// fired late still fires — better late than silently dropped.
public final class ScheduledTaskRunner {
    public typealias OnFire = @MainActor (ScheduledTask) -> Void

    private let store: ScheduledTaskStore
    private let onFire: OnFire
    private let tickInterval: TimeInterval
    private var timer: Timer?
    /// Most recent error surfaced by `tick()` — callers can show this in UI.
    public private(set) var lastError: String?

    public init(
        store: ScheduledTaskStore = ScheduledTaskStore(),
        tickInterval: TimeInterval = 5,
        onFire: @escaping OnFire
    ) {
        self.store = store
        self.tickInterval = tickInterval
        self.onFire = onFire
    }

    /// Start the polling loop. Safe to call once per instance; subsequent
    /// calls restart the timer.
    public func start() {
        stop()
        let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // First tick immediately so a freshly-created task with a near-future
        // fire time doesn't wait a full minute.
        Task { @MainActor [weak self] in self?.tick() }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { stop() }

    /// Single scan pass: load → fire any due → recompute nextFireAt → save.
    /// Public so tests can drive it deterministically without a real timer.
    @MainActor
    public func tick(now: Date = Date()) {
        do {
            let tasks = store.loadAll()
            for var task in tasks {
                guard task.enabled else { continue }
                let due: Date? = {
                    if let nf = task.nextFireAt { return nf }
                    return task.schedule.nextFire(after: now, lastFired: task.lastFiredAt)
                }()
                guard let due, due <= now else { continue }
                // Fire.
                task.lastFiredAt = now
                if case .oneShot = task.schedule {
                    // oneShot is single-use; after firing disable and clear nextFire.
                    task.enabled = false
                    task.nextFireAt = nil
                } else {
                    task.nextFireAt = task.schedule.nextFire(after: now, lastFired: now)
                }
                do { try store.save(task) } catch { lastError = "save: \(error)"; continue }
                onFire(task)
            }
        }
    }

    /// Recompute nextFireAt for every enabled task. Called by the editor
    /// after the user edits `schedule`, so the list view shows an updated
    /// "下次触发" timestamp without waiting for the next tick.
    public func refreshNextFireDates() {
        let now = Date()
        for task in store.loadAll() where task.enabled {
            var t = task
            t.nextFireAt = t.schedule.nextFire(after: now, lastFired: t.lastFiredAt)
            try? store.save(t)
        }
    }
}
