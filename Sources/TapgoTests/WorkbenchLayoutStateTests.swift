import Foundation
@testable import TapgoCore

@MainActor
func runWorkbenchLayoutStateTests(_ t: TestRunner) {
    var state = WorkbenchLayoutState.default
    t.expectEqual(state.tabs.map(\.kind), [.review], "workbench: defaults to one review tab")
    t.expectEqual(state.selectedTabID, "review", "workbench: default review is selected")

    let reviewID = state.open(.review)
    t.expectEqual(reviewID, "review", "workbench: review is a singleton")
    t.expectEqual(state.tabs.filter { $0.kind == .review }.count, 1, "workbench: reopening review does not duplicate it")

    let terminal1 = state.open(.terminal)
    let terminal2 = state.open(.terminal)
    t.expect(terminal1 != terminal2, "workbench: terminal sessions have stable distinct ids")
    t.expectEqual(state.tabs.filter { $0.kind == .terminal }.count, 2, "workbench: terminal supports multiple sessions")
    t.expectEqual(state.selectedTabID, terminal2, "workbench: newest terminal becomes selected")

    let assistant1 = state.open(.assistant)
    let assistant2 = state.open(.assistant)
    t.expect(assistant1 != assistant2, "workbench: auxiliary conversations support multiple sessions")
    t.expectEqual(state.tabs.filter { $0.kind == .assistant }.count, 2, "workbench: auxiliary conversations coexist")
    state.linkThread("aux-thread-1", toTab: assistant1)
    t.expectEqual(state.tabs.first(where: { $0.id == assistant1 })?.linkedThreadID,
                  "aux-thread-1", "workbench: auxiliary tab persists its independent thread binding")

    state.close(assistant2)
    t.expectEqual(state.selectedTabID, assistant1, "workbench: closing selected tab selects its nearest sibling")
    state.closeOthers(keeping: terminal1)
    t.expectEqual(state.tabs.map(\.id), [terminal1], "workbench: close-others keeps only the requested tab")
    t.expectEqual(state.selectedTabID, terminal1, "workbench: close-others selects the kept tab")

    let encoded = try? JSONEncoder().encode(state)
    let restored = encoded.flatMap { try? JSONDecoder().decode(WorkbenchLayoutState.self, from: $0) }
    t.expectEqual(restored, state, "workbench: state round-trips for relaunch restoration")

    let auxiliary = TapgoCore.Thread(
        id: "aux-1", title: "辅助对话", createdAt: Date(), updatedAt: Date(),
        mode: TapgoCore.Thread.auxiliaryMode
    )
    t.expect(auxiliary.isAuxiliary, "workbench: auxiliary mode is recognized by persisted threads")
    t.expect(!auxiliary.isEvolution, "workbench: auxiliary mode remains distinct from evolution sessions")
}
