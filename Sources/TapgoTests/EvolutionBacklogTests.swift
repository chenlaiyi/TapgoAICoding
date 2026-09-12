import Foundation
import TapgoCore

@MainActor
func runEvolutionBacklog(_ t: TestRunner) {
    let text = """
    # Backlog
    ## P0 — high
    - [x] **EVO-001 done item**: old detail
    - [ ] **EVO-005 top item**：top detail
    ## P1 — medium
    - [ ] **EVO-006 second item**: second detail
    """
    let items = TapgoCore.EvolutionBacklog.parse(text)
    t.expectEqual(items.count, 3, "backlog: parses done + open items")
    t.expectEqual(items[1].id, "EVO-005", "backlog: id parsed")
    t.expectEqual(items[1].priority, "P0", "backlog: priority section tracked")
    t.expectEqual(items[1].title, "top item", "backlog: title parsed")
    t.expectEqual(items[1].detail, "top detail", "backlog: full-width colon detail parsed")
    t.expectEqual(items[1].done, false, "backlog: open flag")
    t.expectEqual(items[2].priority, "P1", "backlog: second priority section")
    t.expectEqual(TapgoCore.EvolutionBacklog.topOpen(in: items)?.id, "EVO-005",
                  "backlog: first open item wins")

    let doneOnly = TapgoCore.EvolutionBacklog.parse("- [x] **EVO-001 done**: d")
    t.expectNil(TapgoCore.EvolutionBacklog.topOpen(in: doneOnly), "backlog: no open item yields nil")

    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tapgo-backlog-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: tmp) }
    try? FileManager.default.createDirectory(at: tmp.appendingPathComponent("evolution"), withIntermediateDirectories: true)
    try? text.write(to: tmp.appendingPathComponent("evolution/BACKLOG.md"), atomically: true, encoding: .utf8)
    t.expectEqual(TapgoCore.EvolutionBacklog.topOpen(projectRoot: tmp)?.id ?? "nil", "EVO-005",
                  "backlog: loads from project root")

    let prompt = TapgoCore.EvolutionWorkspace.kickoffPrompt(topBacklogItem: items[1])
    t.expect(prompt.contains("EVO-005"), "backlog: prompt includes top item id")
    t.expect(prompt.contains("优先从 evolution/BACKLOG.md"), "backlog: prompt names backlog source")
}
