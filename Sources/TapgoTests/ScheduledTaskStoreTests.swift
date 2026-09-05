import TapgoCore
#if canImport(Darwin)
import Foundation
import Darwin
#endif

func runScheduledTaskStoreTests(_ t: TestRunner) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-scheduled-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let store = ScheduledTaskStore(baseDir: tmp)

    t.expect(store.loadAll().isEmpty, "fresh dir loads 0 tasks")

    let a = ScheduledTask(
        name: "晨会提醒",
        prompt: "今天的 git diff 总结",
        schedule: .daily(hour: 9, minute: 30)
    )
    try? store.save(a)
    let loaded = store.loadAll()
    t.expectEqual(loaded.count, 1, "save+load yields 1 task")
    t.expectEqual(loaded.first?.name, "晨会提醒", "name round-trips")
    t.expectEqual(loaded.first?.prompt, "今天的 git diff 总结", "prompt round-trips")
    t.expectEqual(loaded.first?.schedule, .daily(hour: 9, minute: 30), "schedule round-trips")

    let b = ScheduledTask(name: "短任务", prompt: "ping", schedule: .interval(seconds: 600))
    try? store.save(b)
    let all = store.loadAll()
    t.expectEqual(all.count, 2, "two tasks persist")
    t.expect(all.allSatisfy { $0.nextFireAt != nil }, "nextFireAt auto-populated on save")

    store.delete(id: a.id)
    let after = store.loadAll()
    t.expectEqual(after.count, 1, "delete leaves one task")
    t.expectEqual(after.first?.id, b.id, "remaining task is the second one")

    let url = tmp.appendingPathComponent("\(b.id.uuidString).json")
    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    let raw = attrs?[.posixPermissions]
    let perms = (raw as? Int) ?? Int((raw as? UInt16) ?? 0)
    t.expectEqual(perms & 0o777, 0o600, "task file is owner-only 0600")

    let beforeUpdated = b.updatedAt
    #if canImport(Darwin)
    usleep(1_500_000)
    #endif
    try? store.save(b)
    let reloaded = store.loadAll().first!
    t.expect(reloaded.updatedAt >= beforeUpdated, "second save bumps updatedAt")
}
