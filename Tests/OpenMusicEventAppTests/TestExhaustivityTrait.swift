import ComposableArchitecture2
import Testing

extension Trait where Self == OpenMusicEventTestExhaustivityTrait {
    static func tcaExhaustivity(_ exhaustivity: TestExhaustivity) -> Self {
        OpenMusicEventTestExhaustivityTrait(exhaustivity: exhaustivity)
    }
}

struct OpenMusicEventTestExhaustivityTrait: SuiteTrait, TestScoping, TestTrait {
    let exhaustivity: TestExhaustivity

    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent () async throws -> Void
    ) async throws {
        try await TestExhaustivity.$current.withValue(exhaustivity) {
            try await function()
        }
    }
}
