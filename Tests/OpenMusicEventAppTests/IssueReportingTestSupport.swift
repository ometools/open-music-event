import Foundation
import IssueReporting
import Testing

@discardableResult
@MainActor
func expectReportedIssue(
    containing expectedMessage: String,
    _ operation: @MainActor () async throws -> Void
) async throws -> [String] {
    let reporter = AppTestIssueRecordingReporter()

    try await withIssueReporters([reporter]) {
        try await operation()
    }

    let messages = reporter.messages
    #expect(messages.count == 1)
    #expect(messages.first?.contains(expectedMessage) == true)
    return messages
}

final class AppTestIssueRecordingReporter: @unchecked Sendable, IssueReporter {
    private let lock = NSLock()
    private var recordedMessages: [String] = []

    var messages: [String] {
        lock.withLock { recordedMessages }
    }

    func reportIssue(
        _ message: @autoclosure () -> String?,
        severity: IssueSeverity,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        lock.withLock {
            recordedMessages.append(message() ?? "")
        }
    }

    func reportIssue(
        _ error: any Error,
        _ message: @autoclosure () -> String?,
        fileID: StaticString,
        filePath: StaticString,
        line: UInt,
        column: UInt
    ) {
        lock.withLock {
            recordedMessages.append(
                "Caught error: \(error)"
                    + (message().map { ": \($0)" } ?? "")
            )
        }
    }
}
