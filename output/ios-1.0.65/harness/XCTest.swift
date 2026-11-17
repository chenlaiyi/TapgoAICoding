import Foundation

public var harnessFailures = 0
public var harnessChecks = 0

public func harnessRecord(_ ok: Bool, _ text: @autoclosure () -> String,
                          file: String = #file, line: Int = #line) {
    harnessChecks += 1
    if !ok {
        harnessFailures += 1
        print("FAIL \(text()) [\(file):\(line)]")
    }
}

public func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "",
                                         file: String = #file, line: Int = #line) {
    harnessRecord(a == b, "\(message) expected \(b), got \(a)", file: file, line: line)
}

public func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double, _ message: String = "",
                           file: String = #file, line: Int = #line) {
    harnessRecord(abs(a - b) <= accuracy, "\(message) expected \(b) +/- \(accuracy), got \(a)", file: file, line: line)
}

public func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "",
                                            file: String = #file, line: Int = #line) {
    harnessRecord(a != b, "\(message) expected values to differ", file: file, line: line)
}

public func XCTAssertTrue(_ value: Bool, _ message: String = "",
                          file: String = #file, line: Int = #line) {
    harnessRecord(value, "\(message) expected true", file: file, line: line)
}

public func XCTAssertFalse(_ value: Bool, _ message: String = "",
                           file: String = #file, line: Int = #line) {
    harnessRecord(!value, "\(message) expected false", file: file, line: line)
}

public func XCTAssertNil<T>(_ value: T?, _ message: String = "",
                            file: String = #file, line: Int = #line) {
    harnessRecord(value == nil, "\(message) expected nil, got \(String(describing: value))", file: file, line: line)
}

public func XCTAssertNotNil<T>(_ value: T?, _ message: String = "",
                               file: String = #file, line: Int = #line) {
    harnessRecord(value != nil, "\(message) expected a value", file: file, line: line)
}

public enum XCTestUnwrapFailure: Error { case missing }

public func XCTUnwrap<T>(_ value: T?, _ message: String = "",
                         file: String = #file, line: Int = #line) throws -> T {
    guard let value else {
        harnessRecord(false, "\(message) expected a value", file: file, line: line)
        throw XCTestUnwrapFailure.missing
    }
    return value
}

public func XCTFail(_ message: String = "",
                    file: String = #file, line: Int = #line) {
    harnessRecord(false, message, file: file, line: line)
}

open class XCTestCase {
    public init() {}
    open func setUp() {}
    open func tearDown() {}
}

public func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T,
                                    _ message: String = "",
                                    file: String = #file, line: Int = #line,
                                    _ handler: (Error) -> Void = { _ in }) {
    do {
        _ = try expression()
        harnessRecord(false, "\(message) expected an error", file: file, line: line)
    } catch {
        harnessRecord(true, "", file: file, line: line)
        handler(error)
    }
}
