import TapgoCore

func runSidebarPresentationTests(_ t: TestRunner) {
    let ids: Set<String> = ["项目一", "server/project", "a"]
    t.expectEqual(SidebarPresentation.collapsedIDs(SidebarPresentation.encodeCollapsedIDs(ids)), ids, "sidebar: collapsed projects persist across launches")
    t.expectEqual(SidebarPresentation.encodeCollapsedIDs(["b", "a"]), "[\"a\",\"b\"]", "sidebar: persistence is deterministic")
    t.expectEqual(SidebarPresentation.collapsedIDs("broken"), [], "sidebar: damaged preference falls back to expanded")
    t.expectEqual(SidebarPresentation.collapsedIDs("[1]"), [], "sidebar: invalid preference types are ignored")
    t.expectEqual(SidebarPresentation.projectIDs(["b", "a", "c"], pinned: []), ["b", "a", "c"], "sidebar: saved order never follows active selection")
    t.expectEqual(SidebarPresentation.projectIDs(["b", "a", "c"], pinned: ["c", "b", "missing"]), ["b", "c", "a"], "sidebar: pinned tiers preserve saved order and ignore removed projects")
    t.expectEqual(SidebarPresentation.statusText(.awaitingApproval), "待批准", "sidebar: approval stays distinguishable from running")
    t.expectEqual(SidebarPresentation.statusText(.interrupted), "已中断", "sidebar: interruption remains accessible")
    t.expectNil(SidebarPresentation.statusText(.completed), "sidebar: completed tasks show recency")
}
