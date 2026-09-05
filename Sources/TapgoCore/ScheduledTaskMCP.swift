import Foundation
import CoreFoundation
import Darwin

/// Local scheduler tools are independent of computer-control TCC and model vendor.
public final class ScheduledTaskMCP {
    public static let serverKey = "tapgo_scheduled_tasks"
    public static let instructions = """
    【定时任务】需要创建、查询或取消 Tapgo 定时任务时使用 tapgo_scheduled_tasks 的 create_scheduled_task/list_scheduled_tasks/cancel_scheduled_task；不要假设工具不可用，也不要自行改写 launchd。周一至周五使用 frequency=weekdays。打开已安装应用时传 application_bundle_id（Zoom 为 us.zoom.xos），直接执行原生打开应用，不再把它发回模型。工具返回落盘 ID、下次运行时间和本机时区后才可宣称已创建。任务只在当前机器的 Tapgo 开启且电脑未休眠时执行；不得承诺自动唤醒。重复的同一任务会返回已有记录。取消需明确目标 ID。
    """
    public let store: ScheduledTaskStore
    private let applicationExists: (String) -> Bool
    public init(store: ScheduledTaskStore = ScheduledTaskStore(), applicationExists: @escaping (String) -> Bool = { _ in true }) {
        self.store = store
        self.applicationExists = applicationExists
    }
    public struct Failure: LocalizedError {
        public let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
    private func locked<T>(_ action: () throws -> T) throws -> T {
        let path = store.baseDir.appendingPathComponent(".scheduler.lock").path
        let fd = Darwin.open(path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Failure("无法锁定任务存储") }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw Failure("任务存储正在使用中") }
        defer { flock(fd, LOCK_UN) }
        return try action()
    }
    public func create(name: String, prompt: String, schedule: ScheduleSpec, bundleID: String?, now: Date = Date()) throws -> (task: ScheduledTask, created: Bool) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt.count <= 10000,
              let next = schedule.nextFire(after: now, lastFired: now) else { throw Failure("任务名称、内容或运行时间无效") }
        if let bundleID {
            guard bundleID.range(of: #"^[A-Za-z0-9][A-Za-z0-9.-]{1,199}$"#, options: .regularExpression) != nil,
                  applicationExists(bundleID) else { throw Failure("目标应用未安装或标识无效：\(bundleID)") }
        }
        return try locked {
            if let existing = store.loadAll().first(where: {
                $0.enabled && $0.schedule == schedule && $0.applicationBundleIdentifier == bundleID && (bundleID != nil || $0.prompt == prompt)
            }) { return (existing, false) }
            let task = ScheduledTask(name: name, prompt: prompt, schedule: schedule,
                applicationBundleIdentifier: bundleID, nextFireAt: next, createdAt: now, updatedAt: now)
            try store.save(task)
            guard let saved = store.loadAll().first(where: { $0.id == task.id }) else { throw Failure("任务写入后未能读回") }
            return (saved, true)
        }
    }
    public func cancel(id: UUID) throws -> ScheduledTask {
        try locked {
            guard var task = store.loadAll().first(where: { $0.id == id }) else { throw Failure("未找到该任务") }
            task.enabled = false
            task.nextFireAt = nil
            try store.save(task)
            guard let saved = store.loadAll().first(where: { $0.id == id }), !saved.enabled else { throw Failure("取消状态未能读回") }
            return saved
        }
    }
    public static var tools: [[String: Any]] {
        let string: [String: Any] = ["type": "string"]
        let hour: [String: Any] = ["type": "integer", "minimum": 0, "maximum": 23]
        let minute: [String: Any] = ["type": "integer", "minimum": 0, "maximum": 59]
        func tool(_ name: String, _ description: String, _ properties: [String: Any], _ required: [String], readOnly: Bool = false) -> [String: Any] {
            ["name": name, "description": description, "inputSchema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false],
             "annotations": ["readOnlyHint": readOnly, "destructiveHint": false, "idempotentHint": true]]
        }
        return [
            tool("create_scheduled_task", "创建并落盘本机定时任务，返回 ID、下次时间和时区。同一有效任务不重复创建。", ["name": string, "prompt": string,
                "frequency": ["type": "string", "enum": ["daily", "weekdays", "weekly", "interval", "once"]], "hour": hour, "minute": minute,
                "weekday": ["type": "integer", "minimum": 1, "maximum": 7], "interval_minutes": ["type": "integer", "minimum": 1, "maximum": 1440], "fire_at": string, "application_bundle_id": string], ["name", "prompt", "frequency"]),
            tool("list_scheduled_tasks", "查询本机已持久化的定时任务及运行条件。", [:], [], readOnly: true),
            tool("cancel_scheduled_task", "按明确 ID 停用任务，保留历史，可在面板重新开启。", ["id": string], ["id"])
        ]
    }
    public func handle(_ data: Data) -> Data? {
        guard let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let id = request["id"] else { return nil }
        func reply(_ result: Any) -> Data? { try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "result": result], options: .sortedKeys) }
        switch request["method"] as? String {
        case "initialize": return reply(["protocolVersion": ComputerUseMCP.protocolVersion, "capabilities": ["tools": [:]], "serverInfo": ["name": "tapgo-scheduled-tasks", "version": "1.0.0"], "instructions": Self.instructions])
        case "ping": return reply([:])
        case "tools/list": return reply(["tools": Self.tools])
        case "tools/call":
            do {
                let params = request["params"] as? [String: Any] ?? [:]
                let args = params["arguments"] as? [String: Any] ?? [:]
                let value: Any
                switch params["name"] as? String {
                case "list_scheduled_tasks": value = ["tasks": try jsonTasks(store.loadAll()), "time_zone": TimeZone.current.identifier, "requires_app_running": true] as [String: Any]
                case "cancel_scheduled_task":
                    guard let raw = args["id"] as? String, let id = UUID(uuidString: raw) else { throw Failure("需要有效任务 ID") }
                    value = ["cancelled": true, "task": try jsonTasks([cancel(id: id)])[0]] as [String: Any]
                case "create_scheduled_task":
                    func integer(_ key: String, _ range: ClosedRange<Int>) throws -> Int {
                        guard let n = args[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue == Double(n.intValue), range.contains(n.intValue) else { throw Failure("参数 \(key) 无效") }
                        return n.intValue
                    }
                    let spec: ScheduleSpec
                    switch args["frequency"] as? String {
                    case "daily": spec = .daily(hour: try integer("hour", 0...23), minute: try integer("minute", 0...59))
                    case "weekdays": spec = .weekdays(hour: try integer("hour", 0...23), minute: try integer("minute", 0...59))
                    case "weekly": spec = .weekly(weekday: try integer("weekday", 1...7), hour: try integer("hour", 0...23), minute: try integer("minute", 0...59))
                    case "interval": spec = .interval(seconds: Double(try integer("interval_minutes", 1...1440)) * 60)
                    case "once":
                        guard let raw = args["fire_at"] as? String, let date = ISO8601DateFormatter().date(from: raw) else { throw Failure("fire_at 需要带时区的 ISO8601 时间") }; spec = .oneShot(date)
                    default: throw Failure("frequency 无效")
                    }
                    if let supplied = args["application_bundle_id"], !(supplied is String) { throw Failure("application_bundle_id 必须是字符串") }
                    let saved = try create(name: args["name"] as? String ?? "", prompt: args["prompt"] as? String ?? "", schedule: spec, bundleID: args["application_bundle_id"] as? String)
                    value = ["created": saved.created, "task": try jsonTasks([saved.task])[0], "time_zone": TimeZone.current.identifier, "requires_app_running": true] as [String: Any]
                default: throw Failure("未知定时任务工具")
                }
                let encoded = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
                return reply(["content": [["type": "text", "text": String(decoding: encoded, as: UTF8.self)]], "isError": false])
            } catch { return reply(["content": [["type": "text", "text": error.localizedDescription]], "isError": true]) }
        default: return try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found"]])
        }
    }
    private func jsonTasks(_ tasks: [ScheduledTask]) throws -> [Any] {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try JSONSerialization.jsonObject(with: encoder.encode(tasks)) as! [Any]
    }
    public static func upsertConfig(_ config: String, commandPath: String) -> String {
        let escaped = commandPath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let header = "[mcp_servers.\(serverKey)]"
        let fields = ["command = \"\(escaped)\"", "args = [\"--scheduled-tasks\"]"]
        var lines = config.components(separatedBy: "\n")
        if let start = lines.firstIndex(of: header) {
            for field in fields {
                let key = String(field.prefix(while: { $0 != " " }))
                let end = lines[(start + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") }) ?? lines.endIndex
                if let index = (start + 1..<end).first(where: { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix(key + " =") }) { lines[index] = field }
                else { lines.insert(field, at: start + 1) }
            }
            return lines.joined(separator: "\n")
        }
        return config + (config.hasSuffix("\n") ? "" : "\n") + header + "\n" + fields.joined(separator: "\n") + "\n"
    }
}
