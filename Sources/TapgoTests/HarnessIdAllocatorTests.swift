import Foundation
import TapgoCore

// MARK: - Per-section wrappers (called by TestMain dispatch)

@MainActor
func runHarnessIdAllocatorMonotonic(_ t: TestRunner) {
    t.section("HarnessIdAllocator: monotonic allocation")
    var a = HarnessIdAllocator()
    t.expectEqual(a.allocate(), 1, "first allocate → 1")
    t.expectEqual(a.allocate(), 2, "second allocate → 2")
    t.expectEqual(a.allocate(), 3, "third allocate → 3")
    t.expectEqual(a.lastIssued, 3, "lastIssued tracks max")
}

@MainActor
func runHarnessIdAllocatorReleaseReuse(_ t: TestRunner) {
    t.section("HarnessIdAllocator: release + reuse")
    var a = HarnessIdAllocator()
    _ = a.allocate(); _ = a.allocate()   // 1, 2
    a.release(2)
    t.expect(!a.live.contains(2), "released id 2 is no longer live")
    t.expect(a.issued.contains(2), "released id 2 is still in issued (no reuse)")
    t.expectEqual(a.allocate(), 3, "next allocate skips past 2 → 3")
    t.expectEqual(a.allocate(), 4, "next allocate → 4")
}

@MainActor
func runHarnessIdAllocatorServerClaim(_ t: TestRunner) {
    t.section("HarnessIdAllocator: server id claim")
    var b = HarnessIdAllocator()
    _ = b.allocate(); _ = b.allocate()   // 1, 2
    do {
        try b.claim(100)
        t.expectEqual(b.lastIssued, 100, "claim bumps lastIssued past server id")
        t.expectEqual(b.allocate(), 101, "next allocate is strictly above server id")
        t.expect(b.issued.contains(100), "claimed server id is in issued")
    } catch {
        t.expect(false, "claim(100) threw: \(error)")
    }
}

@MainActor
func runHarnessIdAllocatorCollision(_ t: TestRunner) {
    t.section("HarnessIdAllocator: collision detection")
    var c = HarnessIdAllocator()
    let first = c.allocate()  // 1
    do {
        try c.claim(first)
        t.expect(false, "claim(our-own-id) should throw")
    } catch HarnessIdError.collision(let id) {
        t.expectEqual(id, first, "collision error carries the id")
    } catch {
        t.expect(false, "unexpected error: \(error)")
    }
}

@MainActor
func runHarnessIdAllocatorReset(_ t: TestRunner) {
    t.section("HarnessIdAllocator: reset")
    var d = HarnessIdAllocator()
    for _ in 0..<10 { _ = d.allocate() }
    t.expect(!d.isEmpty, "allocator has live ids before reset")
    d.reset()
    t.expect(d.isEmpty, "reset clears live")
    t.expect(d.issued.isEmpty, "reset clears issued")
    t.expectEqual(d.lastIssued, 0, "reset zeroes lastIssued")
    t.expectEqual(d.allocate(), 1, "post-reset allocate starts over from 1")
}

@MainActor
func runHarnessIdAllocatorRepeatReleases(_ t: TestRunner) {
    t.section("HarnessIdAllocator: idempotence / repeat releases")
    var e = HarnessIdAllocator()
    let id = e.allocate()
    e.release(id); e.release(id); e.release(id)
    t.expect(!e.live.contains(id), "id is gone after multiple releases")
    t.expect(e.issued.contains(id), "id remains in issued")
}

@MainActor
func runHarnessIdAllocatorStress(_ t: TestRunner) {
    t.section("HarnessIdAllocator: 1000 allocations are strictly increasing")
    var f = HarnessIdAllocator()
    var prev = 0
    var strictly = true
    var unique = Set<Int>()
    for _ in 0..<1000 {
        let id = f.allocate()
        if id <= prev { strictly = false }
        unique.insert(id)
        prev = id
    }
    t.expect(strictly, "1000 ids are strictly increasing")
    t.expectEqual(unique.count, 1000, "1000 ids are all unique")
}
