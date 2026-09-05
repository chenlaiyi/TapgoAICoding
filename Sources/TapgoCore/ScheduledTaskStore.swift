import Foundation

/// File-per-task JSON store mirroring `ThreadStore`'s pattern: each task
/// gets its own file under `state/v1/scheduled-tasks/<id>.json` so concurrent
/// writes from different actors don't corrupt each other. Atomic writes via
/// `tmp + rename` keep half-written files off disk.
public final class ScheduledTaskStore {
    public let baseDir: URL

    public init(baseDir: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Tapgo AICoding/state/v1/scheduled-tasks", isDirectory: true)) {
        self.baseDir = baseDir
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    /// Load every task file. Missing directory → empty array.
    public func loadAll() -> [ScheduledTask] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: baseDir,
            includingPropertiesForKeys: nil
        ) else { return [] }
        var out: [ScheduledTask] = []
        for url in entries where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let task = try? Self.decoder.decode(ScheduledTask.self, from: data) {
                out.append(task)
            }
        }
        return out.sorted { $0.createdAt < $1.createdAt }
    }

    public func save(_ task: ScheduledTask) throws {
        var stamped = task
        stamped.updatedAt = Date()
        if stamped.nextFireAt == nil {
            stamped.nextFireAt = stamped.schedule.nextFire(after: Date(), lastFired: stamped.lastFiredAt)
        }
        let data = try Self.encoder.encode(stamped)
        let url = baseDir.appendingPathComponent("\(task.id.uuidString).json")
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tmp, to: url)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func delete(id: UUID) {
        let url = baseDir.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
