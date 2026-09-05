import Foundation
import TapgoCore

func runScheduledTaskCommandTests(_ t: TestRunner) {
    let exact = ScheduledTaskCommands.parse("周一到周五每天早上7点33打开zoom app")
    t.expectEqual(exact?.schedule, .weekdays(hour: 7, minute: 33), "original request maps to weekdays 07:33")
    t.expectEqual(exact?.applicationName, "zoom", "app suffix removed")
    t.expectEqual(ScheduledTaskCommands.parse("每天晚上7点打开Zoom")?.schedule, .daily(hour: 19, minute: 0), "evening conversion")
    t.expectEqual(ScheduledTaskCommands.parse("请帮我每天7:33打开Zoom"), nil, "unsupported prefix not partially executed")
    for text in ["不要每天7:33打开Zoom", "每天7:33打开Zoom？", "例如：每天7:33打开Zoom", "每天25:33打开Zoom", "每天7:60打开Zoom", "周一到周五每天早上7点33打开zoom app\n这能实现吗？"] {
        t.expect(ScheduledTaskCommands.parse(text) == nil, "questions, quotes, negation and invalid times do not create: \(text)")
    }
    let cal = Calendar(identifier: .gregorian)
    let saturday = cal.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 10))!
    let monday = cal.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 7, minute: 33))!
    let spec = ScheduleSpec.weekdays(hour: 7, minute: 33)
    t.expectEqual(spec.nextFire(after: saturday, lastFired: nil), monday, "weekdays skips weekend")
    let friday = cal.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 7, minute: 33))!
    t.expectEqual(spec.nextFire(after: friday, lastFired: friday), monday, "Friday fire advances to Monday")
    t.expectEqual(spec.nextFire(after: monday.addingTimeInterval(-1), lastFired: nil), monday, "one second before weekday fire")
    t.expect(ScheduleSpec.weekdays(hour: 24, minute: 0).nextFire(after: saturday, lastFired: nil) == nil, "invalid weekdays rejected")
    do {
        t.expectEqual(try JSONDecoder().decode(ScheduleSpec.self, from: JSONEncoder().encode(spec)), spec, "weekdays Codable")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tapgo-scheduler-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ScheduledTaskStore(baseDir: dir)
        let service = ScheduledTaskMCP(store: store, applicationExists: { $0 == "us.zoom.xos" })
        let created = try service.create(name: "Zoom", prompt: "打开 Zoom", schedule: spec, bundleID: "us.zoom.xos", now: saturday)
        t.expect(created.created, "native task created")
        t.expectEqual(created.task.nextFireAt, monday, "persisted next run correct")
        t.expectEqual(store.loadAll().first?.applicationBundleIdentifier, "us.zoom.xos", "native app identity persisted")
        let duplicate = try service.create(name: "重复命名", prompt: "open Zoom", schedule: spec, bundleID: "us.zoom.xos", now: saturday)
        t.expect(!duplicate.created && duplicate.task.id == created.task.id, "duplicate native request returns same ID")
        let cancelled = try service.cancel(id: created.task.id)
        t.expect(!cancelled.enabled && cancelled.nextFireAt == nil, "cancel persists disabled with no next fire")
        do { _ = try service.create(name: "Missing", prompt: "打开", schedule: spec, bundleID: "missing.app"); t.expect(false, "missing app rejected") }
        catch { t.expect(true, "missing app rejected") }
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(created.task)) as! [String: Any]
        legacy.removeValue(forKey: "applicationBundleIdentifier")
        t.expect(try JSONDecoder().decode(ScheduledTask.self, from: JSONSerialization.data(withJSONObject: legacy)).applicationBundleIdentifier == nil, "legacy task remains prompt based")
        func call(_ tool: String, _ args: [String: Any] = [:]) throws -> [String: Any] {
            let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": tool, "arguments": args]])
            return (try JSONSerialization.jsonObject(with: service.handle(data)!) as! [String: Any])["result"] as! [String: Any]
        }
        let valid: [String: Any] = ["name": "Zoom", "prompt": "打开 Zoom", "frequency": "weekdays", "hour": 7, "minute": 33, "application_bundle_id": "us.zoom.xos"]
        t.expectEqual(try call("create_scheduled_task", valid)["isError"] as? Bool, false, "MCP creates task")
        t.expectEqual(try call("list_scheduled_tasks")["isError"] as? Bool, false, "MCP lists durable tasks")
        for bad in [["hour": true], ["hour": 24], ["minute": 60], ["application_bundle_id": 12], ["frequency": "unknown"]] as [[String: Any]] {
            var args = valid; args.merge(bad) { _, new in new }
            t.expectEqual(try call("create_scheduled_task", args)["isError"] as? Bool, true, "MCP rejects malformed argument")
        }
        t.expectEqual(try call("cancel_scheduled_task", ["id": "invalid"])["isError"] as? Bool, true, "MCP invalid cancel rejected")
        let enabled = store.loadAll().first(where: { $0.enabled })!
        t.expectEqual(try call("cancel_scheduled_task", ["id": enabled.id.uuidString])["isError"] as? Bool, false, "MCP cancels by ID")
        t.expectEqual(ScheduledTaskMCP.tools.count, 3, "three scheduler tools available")
        let config = "model = \"test\"\n[mcp_servers.tapgo_computer_use]\ncommand = \"/cu\"\n"
        let updated = ScheduledTaskMCP.upsertConfig(config, commandPath: "/path with spaces/helper")
        t.expect(updated.hasPrefix(config), "scheduler registration preserves computer use config")
        t.expectEqual(ScheduledTaskMCP.upsertConfig(updated, commandPath: "/path with spaces/helper"), updated, "scheduler registration idempotent")
        t.expect(updated.contains("args = [\"--scheduled-tasks\"]"), "scheduler separate executable mode")
    } catch { t.expect(false, "scheduler tests unexpected error: \(error)") }
}
