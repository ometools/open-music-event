import ComposableArchitecture2
import ErrorHandling
import Foundation
import IssueReporting
import Testing

@MainActor
struct ErrorHandlingTests {
    @Test
    func fallbackHandlingWhenNoParserMatches() throws {
        let id = UUID(0)
        let date = Date(timeIntervalSince1970: 1)
        let handledError = try #require(
            resolvedHandledError(
                from: TestError(),
                fallbackMessage: .fallbackMessage,
                operation: .test,
                id: id,
                date: date
            )
        )

        #expect(handledError.id == id)
        #expect(handledError.date == date)
        #expect(handledError.kind == .unhandled)
        #expect(handledError.message.fallback == "Fallback")
        #expect(handledError.operation == .test)
        #expect(handledError.debugDescription == "TestError()")
    }

    @Test
    func parserOverridesFallback() throws {
        let handledError = try #require(
            resolvedHandledError(
                from: TestError(),
                fallbackMessage: .fallbackMessage,
                operation: .test
            ) {
                ErrorParser { _, _ in
                    ParsedError(
                        message: .parsed,
                        kind: .parsed,
                        debugDescription: "parsed error"
                    )
                }
            }
        )

        #expect(handledError.kind == .parsed)
        #expect(handledError.message.fallback == "Parsed")
        #expect(handledError.debugDescription == "parsed error")
    }

    @Test
    func definitionSiteUserFacingErrorIsUsed() throws {
        let handledError = try #require(
            resolvedHandledError(
                from: FriendlyError(),
                fallbackMessage: .fallbackMessage,
                operation: .test
            )
        )

        #expect(handledError.kind == .friendly)
        #expect(handledError.message.fallback == "Friendly")
        #expect(handledError.debugDescription == "friendly error")
    }

    @Test
    func cancellationErrorDoesNotBecomeHandledError() {
        let handledError = resolvedHandledError(
            from: CancellationError(),
            fallbackMessage: .fallbackMessage,
            operation: .test
        )

        #expect(handledError == nil)
    }

    @Test
    func cleanupRunsOnFailure() async {
        let store = TestStore(initialState: CleanupFeature.State()) {
            CleanupFeature()
        }

        await withIssueReporters([]) {
            await store.send(.buttonTapped) {
                $0.isRunning = true
            }?.value
        }

        #expect(store.state.isRunning == false)
        let latestError = store.state.errorNotifications.state.latestError
        #expect(latestError?.kind == .unhandled)
        #expect(latestError?.message.fallback == "Fallback")
        #expect(latestError?.operation == .test)
    }
}

@Feature
private struct CleanupFeature {
    struct State {
        var errorNotifications = Spawn(ErrorNotifications.State())
        var isRunning = false
    }

    enum Action {
        case buttonTapped
    }

    var body: some Feature {
        Update { state, action in
            switch action {
            case .buttonTapped:
                state.isRunning = true
                store.addTask {
                    await store.withErrorHandling(
                        fallbackMessage: .fallbackMessage,
                        operation: .test
                    ) {
                        throw TestError()
                    } cleanup: {
                        $0.isRunning = false
                    }
                }
            }
        }
        .spawn(\.errorNotifications) {
            ErrorNotifications()
        }
        .onEvent(ErrorReported.self) { error, state in
            state.errorNotifications.state.report(error)
        }
    }
}

private struct TestError: Error {}

private struct FriendlyError: UserFacingErrorConvertible {
    func userFacingError(in context: ErrorHandlingContext) -> ParsedError {
        ParsedError(
            message: .friendly,
            kind: .friendly,
            debugDescription: "friendly error"
        )
    }
}

private extension UserFacingText {
    static let fallbackMessage = Self("Fallback", fallback: "Fallback")
    static let friendly = Self("Friendly", fallback: "Friendly")
    static let parsed = Self("Parsed", fallback: "Parsed")
}

private extension ErrorOperation {
    static let test = Self("test")
}

private extension ErrorKind {
    static let friendly = Self("friendly")
    static let parsed = Self("parsed")
}
