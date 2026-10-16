import Foundation
import XCTest

#if os(macOS)
import SkipTest

@available(macOS 13, macCatalyst 16, *)
final class XCSkipTests: XCTestCase, XCGradleHarness {
    func testSkipModule() async throws {
        try await runGradleTests()
    }
}
#endif
