import ComposableArchitecture2
import Dependencies
import ErrorHandling

public protocol ErrorNotificationRootState {
    var errorNotifications: Spawn<ErrorNotifications> { get set }
}

public extension FeatureProtocol where State: ErrorNotificationRootState {
    func presentReportedErrors() -> some Feature {
        self.modifier(ReportedErrorPresentationModifier())
    }
}

private struct ReportedErrorPresentationModifier<State: ErrorNotificationRootState, Action>: FeatureModifier {
    @Dependency(\.continuousClock) var clock
    @Dependency(\.errorNotificationPresentation) var errorNotificationPresentation

    let store = FeatureStore<State, Action>()

    func body(content: Content) -> some FeatureProtocol<State, Action> {
        content
            .onMount { _ in
                store.addTask {
                    let selections = await errorNotificationPresentation.selections()
                    for await error in selections {
                        try store.post(
                            key: ErrorNotificationSelected.self,
                            value: error
                        )
                    }
                }
            }
            .onEvent(ErrorReported.self) { error, state in
                state.errorNotifications.state.report(error)
                store.addTask {
                    await errorNotificationPresentation.show(.error(error))
                }
                store.addTask {
                    try await clock.sleep(for: ErrorNotifications.automaticDismissDelay)
                    try store.modify {
                        $0.errorNotifications.state.dismiss(id: error.id)
                    }
                }
            }
    }
}
