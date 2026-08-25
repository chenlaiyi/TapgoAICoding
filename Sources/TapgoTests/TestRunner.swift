import Foundation

public final class TestRunner {
    public private(set) var passed = 0
    public private(set) var failed = 0
    public private(set) var currentSection = "(no section)"

    /// Tests run by section name. Used by the `--filter` CLI flag
    /// so we can target the slow SSH integration test (or any one
    /// section) without re-running the whole suite.
    public let allSections: [String]
    public let filter: String?
    private var inScope: Bool = true

    public init(filter: String? = nil, allSections: [String] = []) {
        self.filter = filter
        self.allSections = allSections
        if let filter {
            inScope = (filter == "all") || allSections.contains(filter)
        }
    }

    public func section(_ name: String) {
        currentSection = name
        if let filter, filter != "all", filter != name {
            inScope = false
            return
        }
        inScope = true
        // Each test section starts with a header that includes
        // a "START" tag. A hung test is very visible in the log
        // even with stdout buffering because the [end] line never
        // appears.
        print("")
        print("[run] \(name)  [START]")
        stdoutFlush()
    }

    /// Mark the current section as PASS/FAIL. Pair with `section(_:)`.
    public func endSection() {
        if !inScope { return }
        let status = (failed == 0) ? "PASS" : "FAIL"
        print("[end] \(currentSection)  [\(status)]  passed=\(passed) failed=\(failed)")
        stdoutFlush()
    }

    public func expect(_ cond: Bool, _ name: String, file: StaticString = #file, line: UInt = #line) {
        if !inScope { return }
        if cond {
            passed += 1
            print("  ✓ \(name)")
        } else {
            failed += 1
            print("  ✗ \(name)  (\(file):\(line))")
        }
        stdoutFlush()
    }

    public func expectEqual<T: Equatable>(_ a: T, _ b: T, _ name: String, file: StaticString = #file, line: UInt = #line) {
        if !inScope { return }
        if a == b {
            passed += 1
            print("  ✓ \(name)")
        } else {
            failed += 1
            print("  ✗ \(name)  expected \(b), got \(a)  (\(file):\(line))")
        }
        stdoutFlush()
    }

    public func expectNotEqual<T: Equatable>(_ a: T, _ b: T, _ name: String, file: StaticString = #file, line: UInt = #line) {
        if !inScope { return }
        if a != b {
            passed += 1
            print("  ✓ \(name)")
        } else {
            failed += 1
            print("  ✗ \(name)  expected NOT \(b), got \(a)  (\(file):\(line))")
        }
        stdoutFlush()
    }

    public func expectThrows(_ body: () throws -> Void, _ name: String, file: StaticString = #file, line: UInt = #line) {
        if !inScope { return }
        do {
            try body()
            failed += 1
            print("  ✗ \(name)  expected throw, got nothing  (\(file):\(line))")
        } catch {
            passed += 1
            print("  ✓ \(name)")
        }
        stdoutFlush()
    }

    public func expectNoThrow(_ body: () throws -> Void, _ name: String, file: StaticString = #file, line: UInt = #line) {
        if !inScope { return }
        do {
            try body()
            passed += 1
            print("  ✓ \(name)")
        } catch {
            failed += 1
            print("  ✗ \(name)  unexpected throw: \(error)  (\(file):\(line))")
        }
        stdoutFlush()
    }

    public func expectNil<T>(_ value: T?, _ name: String, file: StaticString = #file, line: UInt = #line) {
        if !inScope { return }
        if value == nil {
            passed += 1
            print("  ✓ \(name)")
        } else {
            failed += 1
            print("  ✗ \(name)  expected nil, got \(String(describing: value!))  (\(file):\(line))")
        }
        stdoutFlush()
    }

    public func expectNotNil<T>(_ value: T?, _ name: String, file: StaticString = #file, line: UInt = #line) {
        if !inScope { return }
        if value != nil {
            passed += 1
            print("  ✓ \(name)")
        } else {
            failed += 1
            print("  ✗ \(name)  expected non-nil  (\(file):\(line))")
        }
        stdoutFlush()
    }

    @discardableResult
    public func summary() -> Int {
        print("")
        print("— \(passed) passed, \(failed) failed —")
        stdoutFlush()
        return failed == 0 ? 0 : 1
    }

    /// Force stdout to flush. Without this, prints can sit in
    /// userspace buffers for seconds — fatal for "is the test
    /// hung or just slow?" diagnostics.
    private func stdoutFlush() {
        // fflush on stdout isn't directly exposed in Swift; use the
        // C runtime. We don't want to depend on file descriptors
        // because of TTY redirection (no, ...).
        fflush(stdout)
    }
}
