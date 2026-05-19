import ComposableArchitecture2
import Dependencies
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
        try await withDependencies {
            $0.exhaustivity = exhaustivity
        } operation: {
            try await function()
        }
    }
}
