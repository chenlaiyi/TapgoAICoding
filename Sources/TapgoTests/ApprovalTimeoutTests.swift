import Foundation
import TapgoCore

// MARK: - Per-section wrappers (called by TestMain dispatch)

@MainActor
func runApprovalTimeoutArmDisarm(_ t: TestRunner) {
    t.section("ApprovalTimeoutTracker: arm / disarm basics")
    var tr = ApprovalTimeoutTracker()
    t.expect(tr.isEmpty, "starts empty")
    let arm = tr.arm(rpcRequestId: "rpc-1", now: Date(timeIntervalSince1970: 100), deadline: 60)
    t.expectEqual(arm.rpcRequestId, "rpc-1", "arm carries the rpcRequestId")
    t.expectEqual(arm.deadline, Date(timeIntervalSince1970: 160), "deadline = now + 60s")
    t.expect(!tr.isEmpty, "not empty after arm")
    t.expectEqual(tr.arms["rpc-1"]?.deadline, Date(timeIntervalSince1970: 160), "lookup by id")
    tr.disarm(rpcRequestId: "rpc-1")
    t.expect(tr.isEmpty, "empty after disarm")
}

@MainActor
func runApprovalTimeoutRearm(_ t: TestRunner) {
    t.section("ApprovalTimeoutTracker: re-arm resets deadline")
    var tr = ApprovalTimeoutTracker()
    tr.arm(rpcRequestId: "x", now: Date(timeIntervalSince1970: 0), deadline: 60)
    tr.arm(rpcRequestId: "x", now: Date(timeIntervalSince1970: 30), deadline: 60)
    t.expectEqual(
        tr.arms["x"]?.deadline, Date(timeIntervalSince1970: 90),
        "re-arm resets deadline (0+60=60 → 30+60=90)"
    )
}

@MainActor
func runApprovalTimeoutSweepFires(_ t: TestRunner) {
    t.section("ApprovalTimeoutTracker: sweep fires onExpire")
    var tr = ApprovalTimeoutTracker()
    var expired: [String] = []
    tr.onExpire = { id in expired.append(id) }

    let t0 = Date(timeIntervalSince1970: 1000)
    tr.arm(rpcRequestId: "a", now: t0, deadline: 30)
    tr.arm(rpcRequestId: "b", now: t0, deadline: 60)
    tr.arm(rpcRequestId: "c", now: t0, deadline: 90)

    var fired = tr.sweep(now: Date(timeIntervalSince1970: 1050))
    t.expectEqual(fired.sorted(), ["a"], "sweep at 1050 expires only a")
    t.expectEqual(expired, ["a"], "onExpire fired for a")

    fired = tr.sweep(now: Date(timeIntervalSince1970: 1070))
    t.expectEqual(fired, ["b"], "sweep at 1070 expires b")
    t.expectEqual(expired.sorted(), ["a", "b"], "onExpire cumulative")

    fired = tr.sweep(now: Date(timeIntervalSince1970: 2000))
    t.expectEqual(fired, ["c"], "sweep at 2000 expires c (no double-fire)")
    t.expectEqual(expired.sorted(), ["a", "b", "c"], "no double-fire")
    t.expect(tr.isEmpty, "empty after all expired")
}

@MainActor
func runApprovalTimeoutDisarmPrevents(_ t: TestRunner) {
    t.section("ApprovalTimeoutTracker: disarm prevents expire")
    var tr = ApprovalTimeoutTracker()
    var expired: [String] = []
    tr.onExpire = { id in expired.append(id) }
    tr.arm(rpcRequestId: "x", now: Date(timeIntervalSince1970: 0), deadline: 30)
    tr.disarm(rpcRequestId: "x")
    _ = tr.sweep(now: Date(timeIntervalSince1970: 1000))
    t.expectEqual(expired, [], "disarmed id never fires onExpire")
}

@MainActor
func runApprovalTimeoutDisarmAll(_ t: TestRunner) {
    t.section("ApprovalTimeoutTracker: disarmAll on shutdown")
    var tr = ApprovalTimeoutTracker()
    tr.arm(rpcRequestId: "a", deadline: 1)
    tr.arm(rpcRequestId: "b", deadline: 1)
    tr.arm(rpcRequestId: "c", deadline: 1)
    t.expectEqual(tr.arms.count, 3, "3 arms before shutdown")
    tr.disarmAll()
    t.expect(tr.isEmpty, "disarmAll clears every id")
}

@MainActor
func runApprovalTimeoutDefaultDeadline(_ t: TestRunner) {
    t.section("ApprovalTimeoutTracker: default deadline matches config")
    t.expectEqual(ApprovalTimeoutTracker.defaultDeadline, 60.0,
                  "default deadline = 60s (longer than 30s RPC timeout)")
    var tr = ApprovalTimeoutTracker()
    let now = Date(timeIntervalSince1970: 0)
    let a = tr.arm(rpcRequestId: "x", now: now)
    t.expectEqual(a.deadline, now.addingTimeInterval(60), "default deadline applied")
}
