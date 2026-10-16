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
        #if os(Android)
        await AndroidTCATestSerialExecutor.shared.acquire()
        do {
            try await TestExhaustivity.$current.withValue(exhaustivity) {
                try await function()
            }
            await AndroidTCATestSerialExecutor.shared.release()
        } catch {
            await AndroidTCATestSerialExecutor.shared.release()
            throw error
        }
        #else
        try await TestExhaustivity.$current.withValue(exhaustivity) {
            try await function()
        }
        #endif
    }
}

#if os(Android)
private actor AndroidTCATestSerialExecutor {
    static let shared = AndroidTCATestSerialExecutor()

    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isRunning {
            isRunning = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            isRunning = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
#endif
