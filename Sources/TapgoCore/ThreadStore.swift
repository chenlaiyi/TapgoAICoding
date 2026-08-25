import Foundation

/// Per-thread JSON persistence (under
/// `~/Library/Application Support/Tapgo AICoding/state/v1/threads/<id>.json`).
/// Persists only the thread metadata (no `turns` — those are
/// in-memory only; we don't have to roundtrip a full chat history
/// to disk right now, but the file is shaped so we can add that
/// later without breaking v1 readers).
///
/// Legacy migration: if v0 lives in `state/threads.json` we read
/// it once, write per-id files, then move v0 to `state/threads.v0.json`
/// so we never re-run the migration.
@MainActor
public final class ThreadStore: ObservableObject {
    public let baseDir: URL
    private let fileManager = FileManager.default
    public private(set) var threads: [Thread] = []

    public init(baseDir: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Tapgo AICoding/state/v1/threads", isDirectory: true))
    {
        self.baseDir = baseDir
        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        load()
    }

    // MARK: - Load / save

    public func load() {
        // Try the legacy v0 blob first (one-time migration).
        let legacy = legacyV0File()
        if fileManager.fileExists(atPath: legacy.path) {
            migrateV0ToV1(legacy: legacy)
        }
        // Read v1 per-id files.
        guard let entries = try? fileManager.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil) else {
            threads = []
            return
        }
        let decoder = JSONDecoder()
        var loaded: [Thread] = []
        for url in entries where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            if let t = try? decoder.decode(Thread.self, from: data) {
                loaded.append(t)
            }
        }
        threads = loaded.sorted { $0.updatedAt > $1.updatedAt }
        normalizeStaleStatuses()
    }

    /// A fresh app-server cannot resume a turn that was mid-flight when the
    /// app quit, so any turn still marked `.running` / `.awaitingApproval`
    /// is flipped to `.interrupted`. Otherwise the app would try to resume a
    /// harness thread that still holds an active writer, producing
    /// "thread already has an active writer", and stale turns would keep
    /// rendering as "运行中".
    private func normalizeStaleStatuses() {
        for i in threads.indices {
            var changes = false
            for j in threads[i].turns.indices {
                let s = threads[i].turns[j].status
                if s == .running || s == .awaitingApproval {
                    threads[i].turns[j].status = .interrupted
                    changes = true
                }
            }
            if changes { save(threads[i]) }
        }
    }

    public func save(_ thread: Thread) {
        let url = baseDir.appendingPathComponent("\(thread.id).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(thread)
            try data.write(to: url, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("[ThreadStore] save failed: \(error.localizedDescription)")
        }
    }

    public func delete(_ id: String) {
        let url = baseDir.appendingPathComponent("\(id).json")
        try? fileManager.removeItem(at: url)
    }

    // MARK: - v0 → v1 migration

    private func legacyV0File() -> URL {
        // Production layout is <stateDir>/threads/  (v1 baseDir)
        // and <stateDir>/threads.json  (v0 legacy). One
        // deletingLastPathComponent is enough to walk from
        // <stateDir>/threads/ up to <stateDir>/.
        baseDir
            .deletingLastPathComponent()
            .appendingPathComponent("threads.json")
    }

    /// One-time migration: read `state/threads.json` (v0), split
    /// into per-id files, and rename the original to
    /// `threads.v0.json` so it never re-runs.
    private func migrateV0ToV1(legacy: URL) {
        struct LegacyThread: Decodable {
            let id: String
            let title: String
            let createdAt: Date
            let updatedAt: Date
            let cwd: String?
            let harnessThreadId: String?
        }
        guard let data = try? Data(contentsOf: legacy),
              let legacyThreads = try? JSONDecoder().decode([LegacyThread].self, from: data)
        else { return }
        for lt in legacyThreads {
            let t = Thread(
                id: lt.id,
                title: lt.title,
                createdAt: lt.createdAt,
                updatedAt: lt.updatedAt,
                projectId: nil,         // legacy threads have no project binding
                cwd: lt.cwd,
                harnessThreadId: lt.harnessThreadId
            )
            save(t)
        }
        // Rename so we never re-migrate.
        let renamed = legacy.deletingLastPathComponent()
            .appendingPathComponent("threads.v0.json")
        try? fileManager.moveItem(at: legacy, to: renamed)
        NSLog("[ThreadStore] migrated \(legacyThreads.count) legacy threads to v1")
    }
}
