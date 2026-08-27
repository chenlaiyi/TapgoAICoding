import TapgoCore

@MainActor
func runConversationRunRegistryTests(_ t: TestRunner) {
    var registry = ConversationRunRegistry()

    t.expectEqual(registry.count, 0, "registry starts empty")
    t.expect(registry.markStarted("thread-a"), "thread A starts")
    t.expect(!registry.markStarted("thread-a"), "duplicate start for thread A is rejected")
    t.expect(registry.markStarted("thread-b"), "thread B starts while thread A is running")
    t.expectEqual(registry.count, 2, "two conversations can run in parallel")
    t.expectEqual(registry.runningThreadIds, Set(["thread-a", "thread-b"]), "running ids include A and B")

    t.expect(registry.requestStop("thread-a"), "stop request is accepted for running thread A")
    t.expect(registry.isRunning("thread-a"), "thread A remains registered until completion")
    t.expectEqual(registry.markFinished("thread-b"), true, "thread B still auto-drains after thread A stops")
    t.expect(registry.isRunning("thread-a"), "finishing thread B does not finish thread A")
    t.expectEqual(registry.markFinished("thread-a"), false, "stopped thread A does not auto-drain")
    t.expectEqual(registry.count, 0, "both completed conversations are removed")

    t.expect(registry.markStarted("thread-a"), "thread A can start a new lifecycle")
    t.expect(registry.markStarted("thread-b"), "thread B can start a new lifecycle")
    t.expect(registry.requestStop("thread-a"), "thread A stop is isolated in the new lifecycle")
    t.expectNil(registry.markFinished("thread-unknown"), "finishing an unknown thread returns nil")
    t.expectEqual(registry.count, 2, "unknown finish does not remove any active run")
    t.expect(registry.isRunning("thread-a"), "unknown finish preserves thread A")
    t.expect(registry.isRunning("thread-b"), "unknown finish preserves thread B")
    t.expectEqual(registry.markFinished("thread-b"), true, "thread B finish identity remains isolated")
    t.expectEqual(registry.markFinished("thread-a"), false, "thread A retains only its own suppression")

    t.expect(registry.markStarted("thread-a"), "thread A starts after a suppressed finish")
    t.expectEqual(registry.markFinished("thread-a"), true, "successful restart clears old suppression")

    t.expect(registry.markStarted("thread-a"), "thread A starts for explicit allowAutoDrain")
    t.expect(registry.requestStop("thread-a"), "thread A is suppressed before override")
    registry.allowAutoDrain("thread-a")
    t.expectEqual(registry.markFinished("thread-a"), true, "allowAutoDrain re-enables draining for thread A")

    t.expect(!registry.requestStop("thread-unknown"), "unknown thread stop is rejected")
    t.expect(registry.markStarted("thread-unknown"), "unknown thread can later start normally")
    t.expectEqual(registry.markFinished("thread-unknown"), true, "rejected stop leaves no stale suppression")

    t.expect(registry.markStarted("thread-a"), "thread A starts for duplicate-start suppression check")
    t.expect(registry.requestStop("thread-a"), "thread A is suppressed")
    t.expect(!registry.markStarted("thread-a"), "duplicate start remains rejected while suppressed")
    t.expectEqual(registry.markFinished("thread-a"), false, "rejected duplicate start does not clear suppression")
}
