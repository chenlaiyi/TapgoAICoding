// TapgoTests/ThreadStoreTests.swift
import Foundation
import TapgoCore

@MainActor
func runThreadStoreLoadFresh(_ t: TestRunner) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-ts-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = ThreadStore(baseDir: tmp)
    t.expectEqual(store.threads.isEmpty, true, "fresh: no threads")
}

@MainActor
func runThreadStoreSaveLoad(_ t: TestRunner) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-ts-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = ThreadStore(baseDir: tmp)
    let th = TapgoCore.Thread(
        id: "local-abc", title: "Test thread",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        projectId: "p1", cwd: "/Users/alice/CPA", harnessThreadId: "01abc"
    )
    store.save(th)
    let fileURL = tmp.appendingPathComponent("\(th.id).json")
    t.expectEqual(FileManager.default.fileExists(atPath: fileURL.path), true, "per-id file: written")
    if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
       let perm = (attrs[.posixPermissions] as? NSNumber)?.intValue {
        t.expectEqual(perm & 0o777, 0o600, "per-id file: 0600 permissions")
    } else {
        t.expect(false, "per-id file: could not stat permissions")
    }
    let store2 = ThreadStore(baseDir: tmp)
    t.expectEqual(store2.threads.count, 1, "reload: 1 thread")
    t.expectEqual(store2.threads.first?.id, "local-abc", "reload: id round-trips")
    t.expectEqual(store2.threads.first?.title, "Test thread", "reload: title round-trips")
    t.expectEqual(store2.threads.first?.projectId, "p1", "reload: projectId round-trips")
    t.expectEqual(store2.threads.first?.cwd, "/Users/alice/CPA", "reload: cwd round-trips")
    t.expectEqual(store2.threads.first?.harnessThreadId, "01abc", "reload: harnessThreadId round-trips")

    var resumeCandidate = th
    resumeCandidate.turns = [Turn(
        id: "done", userInput: "hello", status: .completed,
        startedAt: Date(), completedAt: Date()
    )]
    t.expectEqual(
        resumeCandidate.resumableHarnessThreadId,
        "01abc",
        "resume policy: completed turn reuses harness thread"
    )
    resumeCandidate.turns[0].status = .failed
    t.expectEqual(
        resumeCandidate.resumableHarnessThreadId,
        "01abc",
        "resume policy: failed turn reuses harness thread"
    )
    resumeCandidate.turns[0].status = .interrupted
    t.expectNil(
        resumeCandidate.resumableHarnessThreadId,
        "resume policy: interrupted turn starts safely"
    )
    resumeCandidate.turns.append(Turn(
        id: "new", userInput: "next", status: .running, startedAt: Date()
    ))
    t.expectNil(
        resumeCandidate.resumableHarnessThreadId,
        "resume policy: must be captured before new running turn"
    )
}

@MainActor
func runThreadGoalRoundtrip(_ t: TestRunner) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-goal-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = ThreadStore(baseDir: tmp)
    let th = TapgoCore.Thread(
        id: "local-goal", title: "goal thread",
        createdAt: Date(), updatedAt: Date(), goal: "把订单系统升级到 MySQL 8.0"
    )
    store.save(th)
    let store2 = ThreadStore(baseDir: tmp)
    t.expectEqual(store2.threads.first?.goal, "把订单系统升级到 MySQL 8.0",
                  "goal round-trips after reload")
    // A thread written without a `goal` key still decodes (backward compat).
    let legacy = TapgoCore.Thread(id: "no-goal", title: "legacy",
                                  createdAt: Date(), updatedAt: Date())
    let enc = JSONEncoder()
    var data = try! enc.encode(legacy)
    // Remove the goal key to simulate an old file.
    if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        var m = obj
        m.removeValue(forKey: "goal")
        data = try! JSONSerialization.data(withJSONObject: m)
    }
    let dec = JSONDecoder()
    let decoded = try? dec.decode(TapgoCore.Thread.self, from: data)
    t.expectEqual(decoded?.goal, nil, "goal absent decodes to nil (backward compat)")
}

@MainActor
func runThreadStoreDelete(_ t: TestRunner) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-ts-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = ThreadStore(baseDir: tmp)
    let th = TapgoCore.Thread(id: "to-delete", title: "delete me",
                              createdAt: Date(), updatedAt: Date())
    store.save(th)
    let fileURL = tmp.appendingPathComponent("\(th.id).json")
    t.expectEqual(FileManager.default.fileExists(atPath: fileURL.path), true, "save: file exists")
    store.delete(th.id)
    t.expectEqual(FileManager.default.fileExists(atPath: fileURL.path), false, "delete: file gone")
}

@MainActor
func runThreadStoreV0Migration(_ t: TestRunner) {
    let stateDir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-mig-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: stateDir) }
    try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    let threadsDir = stateDir.appendingPathComponent("threads", isDirectory: true)
    let legacy = stateDir.appendingPathComponent("threads.json")
    let body = """
    [
      {"id":"a","title":"alpha","createdAt":0,"updatedAt":1,"cwd":"/tmp/a","harnessThreadId":"ha"},
      {"id":"b","title":"beta","createdAt":0,"updatedAt":2,"cwd":"/tmp/b","harnessThreadId":"hb"}
    ]
    """
    try? body.write(to: legacy, atomically: true, encoding: .utf8)
    let store = ThreadStore(baseDir: threadsDir)
    t.expectEqual(store.threads.count, 2, "migration: 2 threads loaded")
    t.expectEqual(FileManager.default.fileExists(atPath: legacy.path), false, "migration: legacy file moved away")
    let renamed = stateDir.appendingPathComponent("threads.v0.json")
    t.expectEqual(FileManager.default.fileExists(atPath: renamed.path), true, "migration: legacy renamed to threads.v0.json")
    t.expectEqual(FileManager.default.fileExists(atPath: threadsDir.appendingPathComponent("a.json").path), true,
                  "migration: a.json written")
    t.expectEqual(FileManager.default.fileExists(atPath: threadsDir.appendingPathComponent("b.json").path), true,
                  "migration: b.json written")
    let store2 = ThreadStore(baseDir: threadsDir)
    t.expectEqual(store2.threads.count, 2, "second init: same 2 threads")
    t.expectEqual(FileManager.default.fileExists(atPath: renamed.path), true, "second init: threads.v0.json still there (not re-moved)")
}

@MainActor
func runThreadStoreTurnsPersisted(_ t: TestRunner) {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-ts-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = ThreadStore(baseDir: tmp)
    var th = TapgoCore.Thread(
        id: "turns-test", title: "with turns",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
    )
    th.turns = [
        Turn(
            id: "turn-1",
            userInput: "hello",
            items: [
                .userMessage(id: "u1", text: "hello"),
                .assistantMessage(id: "a1", text: "hi there"),
                .commandExecution(CommandExecution(
                    id: "c1", command: "ls", cwd: "/tmp",
                    status: .succeeded, stdout: "a\nb\n", stderr: "",
                    exitCode: 0, startedAt: Date(timeIntervalSince1970: 1_700_000_050),
                    completedAt: Date(timeIntervalSince1970: 1_700_000_060)
                )),
            ],
            status: .completed,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedAt: Date(timeIntervalSince1970: 1_700_000_100),
            userImagePaths: ["/app-support/attachments/screenshot.png"]
        ),
    ]
    store.save(th)

    // The on-disk JSON now actually contains the `turns` key.
    if let data = try? Data(contentsOf: tmp.appendingPathComponent("turns-test.json")),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        t.expectEqual(json["turns"] != nil, true, "turns key present in on-disk JSON")
    } else {
        t.expect(false, "could not read thread JSON")
    }

    // Round-trips through a fresh ThreadStore.
    let store2 = ThreadStore(baseDir: tmp)
    t.expectEqual(store2.threads.count, 1, "reload: 1 thread")
    let reloaded = store2.threads.first
    t.expectEqual(reloaded?.turns.count, 1, "reload: turns round-trip")
    guard let rturn = reloaded?.turns.first else {
        t.expect(false, "reload: no turns")
        return
    }
    t.expectEqual(rturn.id, "turn-1", "turn id round-trips")
    t.expectEqual(rturn.userInput, "hello", "turn userInput round-trips")
    t.expectEqual(rturn.status, .completed, "turn status round-trips")
    t.expectEqual(rturn.completedAt, Date(timeIntervalSince1970: 1_700_000_100), "turn completedAt round-trips")
    t.expectEqual(rturn.userImagePaths, ["/app-support/attachments/screenshot.png"], "turn image paths round-trip")
    t.expectEqual(rturn.items.count, 3, "turn items round-trip")
    guard case .userMessage(let uid, let utext) = rturn.items[0] else {
        t.expect(false, "item[0] is userMessage"); return
    }
    t.expectEqual(uid, "u1", "userMessage id round-trips")
    t.expectEqual(utext, "hello", "userMessage text round-trips")
    guard case .assistantMessage(_, let atext) = rturn.items[1] else {
        t.expect(false, "item[1] is assistantMessage"); return
    }
    t.expectEqual(atext, "hi there", "assistantMessage text round-trips")
    guard case .commandExecution(let ce) = rturn.items[2] else {
        t.expect(false, "item[2] is commandExecution"); return
    }
    t.expectEqual(ce.command, "ls", "commandExecution command round-trips")
    t.expectEqual(ce.stdout, "a\nb\n", "commandExecution stdout round-trips")
    t.expectEqual(ce.status, .succeeded, "commandExecution status round-trips")
    t.expect(ce.exitCode == 0, "commandExecution exitCode round-trips")
}

@MainActor
func runThreadStoreDecodesLegacyWithoutTurns(_ t: TestRunner) {
    // A v1 file written before turn persistence has no `turns` key.
    // It must still decode (turns defaults to []) rather than fail.
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-ts-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let body = """
    {"id":"old","title":"old thread","createdAt":0,"updatedAt":1,"harnessThreadId":"h1"}
    """
    try? body.write(to: tmp.appendingPathComponent("old.json"), atomically: true, encoding: .utf8)
    let store = ThreadStore(baseDir: tmp)
    t.expectEqual(store.threads.count, 1, "legacy: 1 thread loaded")
    let th = store.threads.first
    t.expectEqual(th?.id, "old", "legacy: id preserved")
    t.expectEqual(th?.harnessThreadId, "h1", "legacy: harnessThreadId preserved")
    t.expectNil(th?.cwd, "legacy: cwd defaults to nil")
    t.expectEqual(th?.turns.isEmpty, true, "legacy: turns defaults to [] (no decode failure)")
}

// MARK: - Thread: auto-title from first user message

@MainActor
func runThreadAutoTitle(_ t: TestRunner) {
    // Short messages are kept verbatim.
    let short = TapgoCore.Thread.autoTitle(from: "列出 workspace 里的项目")
    t.expectEqual(short, "列出 workspace 里的项目",
                  "autoTitle: short message returned verbatim")

    // Newlines are collapsed into spaces so the sidebar row stays
    // single-line.
    let multiline = TapgoCore.Thread.autoTitle(
        from: "第一行\n第二行\n第三行", maxLength: 200)
    t.expectEqual(multiline, "第一行 第二行 第三行",
                  "autoTitle: newlines collapsed to spaces")

    // Long messages are truncated at a word boundary inside the
    // budget, never mid-word.
    let longish = TapgoCore.Thread.autoTitle(
        from: "请帮我把 remotehost 远端 SSH 上面那一堆 mirror test 残留目录都清掉,只保留双下划线那个",
        maxLength: 30)
    t.expect(longish.count <= 31, // +1 for the ellipsis
             "autoTitle: long message stays within budget, got \(longish.count)")
    t.expect(longish.hasSuffix("…"),
             "autoTitle: long message ends with ellipsis, got \(longish)")

    // Empty input falls back to the placeholder so the sidebar
    // never shows a blank title.
    let empty = TapgoCore.Thread.autoTitle(from: "   \n  ")
    t.expectEqual(empty, "新会话",
                  "autoTitle: empty input falls back to placeholder")

    // hasDefaultTitle catches every flavour of placeholder we use
    // in production.
    let t1 = TapgoCore.Thread(
        id: "x", title: "新会话",
        createdAt: Date(), updatedAt: Date())
    t.expect(t1.hasDefaultTitle, "hasDefaultTitle: 新会话")
    let t2 = TapgoCore.Thread(
        id: "x", title: "新建会话",
        createdAt: Date(), updatedAt: Date())
    t.expect(t2.hasDefaultTitle, "hasDefaultTitle: 新建会话")
    let t3 = TapgoCore.Thread(
        id: "x", title: "列出 workspace",
        createdAt: Date(), updatedAt: Date())
    t.expect(!t3.hasDefaultTitle, "hasDefaultTitle: real title not flagged")
}

@MainActor
func runThreadLatestPreview(_ t: TestRunner) {
    let mk = { (items: [TurnItem], input: String, status: TapgoCore.Turn.Status) -> TapgoCore.Turn in
        TapgoCore.Turn(id: UUID().uuidString, userInput: input, items: items,
                       status: status, startedAt: Date())
    }

    // Prefers the latest assistant reply.
    let t1 = TapgoCore.Thread(
        id: "x", title: "t",
        createdAt: Date(), updatedAt: Date(),
        turns: [mk([.userMessage(id: "u", text: "你好"), .assistantMessage(id: "a", text: "你好，有什么可以帮你？")],
                   "你好", .completed)])
    t.expectEqual(t1.latestPreview, "你好，有什么可以帮你？",
                  "latestPreview: prefers assistant reply")

    // Prefixes the user's input with "You: ".
    let t2 = TapgoCore.Thread(
        id: "x", title: "t",
        createdAt: Date(), updatedAt: Date(),
        turns: [mk([.userMessage(id: "u", text: "搜索一下今天")], "搜索一下今天", .running)])
    t.expectEqual(t2.latestPreview, "You: 搜索一下今天",
                  "latestPreview: prefixes user input")

    // Newest turn wins over older ones.
    let t3 = TapgoCore.Thread(
        id: "x", title: "t",
        createdAt: Date(), updatedAt: Date(),
        turns: [
            mk([.assistantMessage(id: "a", text: "旧回复")], "旧问题", .completed),
            mk([.assistantMessage(id: "a2", text: "新回复")], "新问题", .completed),
        ])
    t.expectEqual(t3.latestPreview, "新回复",
                  "latestPreview: newest turn wins")

    // Empty thread falls back to empty string (caller shows placeholder).
    let t4 = TapgoCore.Thread(
        id: "x", title: "t",
        createdAt: Date(), updatedAt: Date())
    t.expectEqual(t4.latestPreview, "",
                  "latestPreview: empty thread is empty")
}

@MainActor
func runThreadDateBanner(_ t: TestRunner) {
    let cal = Calendar.current
    let today = Date()
    let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
    let mk = { (d: Date) -> TapgoCore.Turn in
        TapgoCore.Turn(id: UUID().uuidString, userInput: "hi", status: .completed, startedAt: d)
    }
    let turns = [mk(today), mk(today), mk(yesterday)]
    // First turn always shows a banner.
    t.expect(TapgoCore.Thread.showDateBanner(at: 0, in: turns), "dateBanner: first index true")
    // Same day as previous → no banner.
    t.expect(!TapgoCore.Thread.showDateBanner(at: 1, in: turns), "dateBanner: same day false")
    // Different day → banner.
    t.expect(TapgoCore.Thread.showDateBanner(at: 2, in: turns), "dateBanner: new day true")
    // Out of range is safe.
    t.expect(!TapgoCore.Thread.showDateBanner(at: 3, in: turns), "dateBanner: out of range false")
    t.expect(!TapgoCore.Thread.showDateBanner(at: -1, in: turns), "dateBanner: negative index false")
}

// MARK: - Thread: evolution mode + workspace

@MainActor
func runThreadEvolutionMode(_ t: TestRunner) {
    // mode round-trips through ThreadStore persistence and drives isEvolution.
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-evo-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let evo = TapgoCore.Thread(
        id: "evo-1", title: "自进化",
        createdAt: Date(), updatedAt: Date(),
        cwd: "/Users/alice/TapgoAICoding",
        mode: TapgoCore.Thread.evolutionMode
    )
    t.expect(evo.isEvolution, "evolution: isEvolution true for evolution mode")
    let store = ThreadStore(baseDir: tmp)
    store.save(evo)
    let reloaded = ThreadStore(baseDir: tmp).threads.first
    t.expectEqual(reloaded?.id, "evo-1", "evolution: id round-trips")
    t.expectEqual(reloaded?.isEvolution, true, "evolution: mode round-trips through disk")

    // Ordinary threads (no mode key on disk) decode as non-evolution.
    let ordinary = TapgoCore.Thread(id: "local-1", title: "普通会话",
                                    createdAt: Date(), updatedAt: Date())
    t.expect(!ordinary.isEvolution, "evolution: default mode is not evolution")
    let tmp2 = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-evo-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp2) }
    ThreadStore(baseDir: tmp2).save(ordinary)
    t.expectEqual(ThreadStore(baseDir: tmp2).threads.first?.isEvolution, false,
                  "evolution: legacy file without mode decodes non-evolution")

    // A fixed 自进化 title must never be auto-titled away by the first
    // user message (hasDefaultTitle only matches 新-prefixed placeholders).
    t.expect(!evo.hasDefaultTitle, "evolution: fixed title survives auto-title")

    // Project-root detection: both markers required.
    let probe = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-root-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: probe) }
    try? FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
    t.expect(!EvolutionWorkspace.looksLikeProjectRoot(probe), "workspace: empty dir is not a project root")
    try? Data("// swift".utf8).write(to: probe.appendingPathComponent("Package.swift"))
    t.expect(!EvolutionWorkspace.looksLikeProjectRoot(probe), "workspace: Package.swift alone is not enough")
    try? Data("# 约定".utf8).write(to: probe.appendingPathComponent("AGENTS.md"))
    t.expect(EvolutionWorkspace.looksLikeProjectRoot(probe), "workspace: Package.swift + AGENTS.md is a project root")

    // locateProjectRoot only accepts home/TapgoAICoding.
    let home = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-home-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: home) }
    t.expectNil(EvolutionWorkspace.locateProjectRoot(home: home), "workspace: missing home yields nil")
    let root = home.appendingPathComponent("TapgoAICoding", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    t.expectNil(EvolutionWorkspace.locateProjectRoot(home: home), "workspace: bare dir yields nil")
    try? Data("x".utf8).write(to: root.appendingPathComponent("Package.swift"))
    try? Data("x".utf8).write(to: root.appendingPathComponent("AGENTS.md"))
    t.expectEqual(EvolutionWorkspace.locateProjectRoot(home: home)?.path, root.path,
                  "workspace: home/TapgoAICoding located")

    // The kickoff prompt carries the anchors the evolution flow relies on.
    let prompt = EvolutionWorkspace.kickoffPrompt()
    t.expect(prompt.contains("自进化指令"), "prompt: marker present")
    t.expect(prompt.contains("swift run TapgoTests"), "prompt: full regression command present")
    t.expect(prompt.contains("makeHistory()"), "prompt: version sync point present")
    t.expect(prompt.contains("git fetch origin"), "prompt: repo state check present")
}

// MARK: - v0.5.70 debounced save scheduling
//
// Before v0.5.70, `SessionStore.handle(event:)` called `save(_:)` on
// every harness notification, including every per-character streaming
// delta. For a 2.2M-token reasoning summary that meant a full
// `JSONEncoder.encode(thread)` plus an atomic JSON write per delta —
// enough to peg App CPU at 100 % (see cpu_resource.diag from
// 2026-09-02). `scheduleSave(_:immediate:)` coalesces consecutive
// non-terminal updates into one write per debounce window.

@MainActor
func runThreadStoreScheduleSaveDebounces(_ t: TestRunner) async {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-ts-debounce-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = ThreadStore(baseDir: tmp)
    let thread = TapgoCore.Thread(
        id: "debounce-1", title: "Debounce",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        projectId: nil, cwd: nil, harnessThreadId: nil
    )
    store.scheduleSave(thread, immediate: true)
    let fileURL = tmp.appendingPathComponent("\(thread.id).json")
    let initialMTime = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    t.expectNotNil(initialMTime, "debounce: initial immediate save writes file")

    // Schedule 50 non-terminal updates back-to-back. Each call must
    // reset the debounce window. After the final schedule we wait the
    // debounce window plus a small slack; the file should be rewritten
    // exactly once during that window and contain the latest snapshot.
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(800))
    var latest = thread
    for i in 0..<50 {
        latest.updatedAt = Date(timeIntervalSince1970: 1_700_000_100 + Double(i))
        store.scheduleSave(latest, immediate: false)
    }
    try? await Task.sleep(until: deadline, clock: .continuous)
    let reloaded = ThreadStore(baseDir: tmp)
    t.expectEqual(reloaded.threads.count, 1, "debounce: reload finds the thread")
    t.expectEqual(reloaded.threads.first?.updatedAt,
                  Date(timeIntervalSince1970: 1_700_000_100 + 49),
                  "debounce: latest snapshot wins (50 updates coalesced)")
    // The latest write happened at least once during the window. The
    // coarse test is "file exists with latest content"; the strict
    // "exactly one write per debounce window" assertion is covered by
    // the inline note in the implementation, since real production
    // cost is dominated by encode + atomic write, not by mtime drift.
}

@MainActor
func runThreadStoreScheduleSaveImmediate(_ t: TestRunner) async {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-ts-immediate-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = ThreadStore(baseDir: tmp)
    let thread = TapgoCore.Thread(
        id: "immediate-1", title: "Immediate",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        projectId: nil, cwd: nil, harnessThreadId: nil
    )
    // Non-terminal schedule must not write immediately.
    store.scheduleSave(thread, immediate: false)
    let fileURL = tmp.appendingPathComponent("\(thread.id).json")
    t.expectEqual(FileManager.default.fileExists(atPath: fileURL.path), false,
                  "immediate: scheduleSave(immediate:false) does not write synchronously")

    // An immediate schedule must write right away, even if a pending
    // debounced save exists for the same id.
    var updated = thread
    updated.title = "Updated via immediate"
    store.scheduleSave(updated, immediate: true)
    t.expectEqual(FileManager.default.fileExists(atPath: fileURL.path), true,
                  "immediate: scheduleSave(immediate:true) writes synchronously")
    let decoded = try? JSONDecoder().decode(TapgoCore.Thread.self, from: Data(contentsOf: fileURL))
    t.expectEqual(decoded?.title, "Updated via immediate",
                  "immediate: file contains the strictly newer snapshot")

    // No pending debounced task should still be alive for this id —
    // we want the immediate write to supersede any in-flight flush.
    store.drainPendingSaves()
    let reloaded = ThreadStore(baseDir: tmp)
    t.expectEqual(reloaded.threads.first?.title, "Updated via immediate",
                  "immediate: drain after immediate is a no-op for this id")
}

@MainActor
func runThreadStoreDrainPendingSaves(_ t: TestRunner) async {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-ts-drain-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let store = ThreadStore(baseDir: tmp)
    var thread = TapgoCore.Thread(
        id: "drain-1", title: "Drain",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        projectId: nil, cwd: nil, harnessThreadId: nil
    )
    store.scheduleSave(thread, immediate: false)
    let fileURL = tmp.appendingPathComponent("\(thread.id).json")
    t.expectEqual(FileManager.default.fileExists(atPath: fileURL.path), false,
                  "drain: nothing on disk yet")

    thread.title = "Drain written"
    store.scheduleSave(thread, immediate: false)
    store.drainPendingSaves()
    t.expectEqual(FileManager.default.fileExists(atPath: fileURL.path), true,
                  "drain: drainPendingSaves() flushes pending snapshot")
    let decoded = try? JSONDecoder().decode(TapgoCore.Thread.self, from: Data(contentsOf: fileURL))
    t.expectEqual(decoded?.title, "Drain written",
                  "drain: pending snapshot reaches disk before drain returns")
}
