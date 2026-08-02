import Foundation

public func expect(
    _ condition: Bool,
    _ message: @autoclosure () -> String = "expected true",
    file: String = #filePath,
    line: UInt = #line
) throws {
    guard condition else {
        throw TestFailure(message: message(), file: file, line: line)
    }
}

public func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ label: String = "",
    file: String = #filePath,
    line: UInt = #line
) throws {
    guard actual == expected else {
        let prefix = label.isEmpty ? "" : "\(label): "
        throw TestFailure(
            message: "\(prefix)expected \(expected), got \(actual)",
            file: file,
            line: line
        )
    }
}

public func expectNil<T>(
    _ value: T?,
    _ label: String = "value",
    file: String = #filePath,
    line: UInt = #line
) throws {
    guard value == nil else {
        throw TestFailure(message: "\(label) should be nil, got \(value!)", file: file, line: line)
    }
}

public func expectNotNil<T>(
    _ value: T?,
    _ label: String = "value",
    file: String = #filePath,
    line: UInt = #line
) throws -> T {
    guard let value else {
        throw TestFailure(message: "\(label) should not be nil", file: file, line: line)
    }
    return value
}

/// Asserts that `body` throws, and hands the error back for further checks.
@discardableResult
public func expectThrows(
    _ body: () async throws -> Void,
    file: String = #filePath,
    line: UInt = #line
) async throws -> Error {
    do {
        try await body()
    } catch {
        return error
    }
    throw TestFailure(message: "expected an error, none thrown", file: file, line: line)
}
