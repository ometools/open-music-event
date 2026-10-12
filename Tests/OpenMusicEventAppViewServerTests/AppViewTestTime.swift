import Clocks
import Dependencies
import Foundation
import Testing

struct AppViewTestTime: TestTrait, SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await withDependencies {
            $0.date.now = Date(timeIntervalSince1970: 1_800_000_000)
            $0.continuousClock = TestClock()
        } operation: {
            try await function()
        }
    }
}
