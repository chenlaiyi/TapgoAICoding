import Foundation
import TapgoCore
import UserNotifications

/// Error types thrown by `ScheduledTaskBridge.inject` so the runner can
/// record failures into `ExecutionRecord.errorMessage`.
public enum ScheduledTaskError: LocalizedError {
    /// The pinned target thread no longer exists in the session store.
    case threadMissing(UUID)
    /// The new-thread path failed before any message could be injected.
    case newThreadFailed(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .threadMissing(let id):
            return "目标会话不存在（id 前缀 \(id.uuidString.prefix(8))）"
        case .newThreadFailed(let msg):
            return "新建会话失败：\(msg)"
        }
    }
}

/// Bridge between `ScheduledTaskRunner` (TapgoCore) and the AppKit-y bits
/// it needs to actually do work: UNUserNotificationCenter (macOS banner)
/// and a closure into the running `SessionStore` to inject the prompt.
///
/// On fire the bridge:
/// - posts a macOS notification so the user sees something happened
/// - awaits the `inject` closure (set by `App` after `SessionStore` exists)
/// - records the outcome into `ScheduledTask.executionHistory` (capped 5)
public final class ScheduledTaskBridge: ObservableObject {
    public let taskStore = ScheduledTaskStore()
    public let runner: ScheduledTaskRunner
    @Published public var lastError: String? = nil

    /// Closure invoked when a scheduled task fires. Set by `App` after the
    /// `SessionStore` exists. Throw → the bridge records the failure into
    /// `executionHistory` so the UI can show a "上次失败" badge.
    public var inject: ((ScheduledTask) async throws -> Void)? = nil

    /// Max number of ExecutionRecord entries kept per task. Older ones are
    /// dropped from the head. Keeps JSON files small (5 × ~120 bytes ≈ 600B).
    public static let maxHistoryCount = 5

    public init() {
        // Build the runner with a placeholder closure first; assign it for
        // real after `self` is fully initialized. The placeholder just
        // returns so the @MainActor invariant holds while init runs.
        var placeholder: ScheduledTaskRunner.OnFire = { _ in }
        let r = ScheduledTaskRunner(store: taskStore) { task in
            placeholder(task)
        }
        self.runner = r
        placeholder = { [weak self] task in self?.handleFire(task) }
    }

    public func start() { runner.start() }
    public func stop() { runner.stop() }

    @MainActor
    public func refresh() { runner.refreshNextFireDates() }

    /// Fire a task immediately, bypassing the schedule. Used by the list's
    /// "play" button so the user can sanity-check the prompt without waiting
    /// for the next tick. Does NOT mutate lastFiredAt / nextFireAt and does
    /// NOT post a notification (the user just clicked it). Records the
    /// outcome into executionHistory like a normal fire would.
    @MainActor
    public func runNow(_ task: ScheduledTask) async {
        let started = Date()
        let record: ExecutionRecord
        do {
            try await inject?(task)
            record = ExecutionRecord(firedAt: started, outcome: .success, durationMs: nil)
        } catch {
            record = ExecutionRecord(
                firedAt: started,
                outcome: .failure,
                durationMs: nil,
                errorMessage: String(describing: error)
            )
        }
        appendHistory(taskID: task.id, record: record)
    }

    /// MainActor because UNUserNotificationCenter + SessionStore calls both
    /// expect main-actor isolation. Force the runner's onFire to land here.
    @MainActor
    private func handleFire(_ task: ScheduledTask) {
        let started = Date()
        // Notifications are async; fire-and-forget on the MainActor.
        Task { await self.postNotification(task: task) }
        // Inject is set by App after the SessionStore exists. If it's nil,
        // we still posted the notification — record the skipped outcome so
        // the user can see "配置未完成" in the history column.
        Task {
            let record: ExecutionRecord
            do {
                guard let inject = self.inject else {
                    record = ExecutionRecord(
                        firedAt: started,
                        outcome: .skipped,
                        durationMs: nil,
                        errorMessage: "inject 未配置（SessionStore 尚未就绪）"
                    )
                    self.appendHistory(taskID: task.id, record: record)
                    return
                }
                try await inject(task)
                let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
                record = ExecutionRecord(
                    firedAt: started,
                    outcome: .success,
                    durationMs: elapsedMs
                )
            } catch {
                record = ExecutionRecord(
                    firedAt: started,
                    outcome: .failure,
                    durationMs: Int(Date().timeIntervalSince(started) * 1000),
                    errorMessage: String(describing: error)
                )
            }
            self.appendHistory(taskID: task.id, record: record)
        }
    }

    /// Append a record to the task's history and persist. Bounded at
    /// `maxHistoryCount`. Reloads from disk first so we don't clobber a
    /// record written by a concurrent path.
    @MainActor
    private func appendHistory(taskID: UUID, record: ExecutionRecord) {
        var tasks = taskStore.loadAll()
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        var history = tasks[idx].executionHistory ?? []
        history.append(record)
        if history.count > Self.maxHistoryCount {
            history = Array(history.suffix(Self.maxHistoryCount))
        }
        tasks[idx].executionHistory = history
        do {
            try taskStore.save(tasks[idx])
        } catch {
            lastError = "history save: \(error)"
        }
    }

    @MainActor
    private func postNotification(task: ScheduledTask) async {
        let center = UNUserNotificationCenter.current()
        do { try await center.requestAuthorization(options: [.alert, .sound]) } catch { /* denied — fine */ }
        let content = UNMutableNotificationContent()
        content.title = "定时任务：\(task.name)"
        content.body = String(task.prompt.prefix(140))
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "scheduled.\(task.id.uuidString).\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        try? await center.add(req)
    }
}
