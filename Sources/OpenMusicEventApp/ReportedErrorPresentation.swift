import ComposableArchitecture2
import Dependencies
import ErrorHandling
import TCATProtoAuthentication

public protocol ErrorNotificationRootState {
    var errorNotifications: Spawn<ErrorNotifications> { get set }
}

public extension FeatureProtocol where State: ErrorNotificationRootState {
    func presentReportedErrors() -> some Feature {
        self.modifier(ReportedErrorPresentationModifier())
    }
}

public extension FeatureProtocol
where
    State == OAuthAuthorization<OpenMusicEventAppRoot>.State,
    Action == OAuthAuthorization<OpenMusicEventAppRoot>.Action
{
    func presentAuthorizationFailures() -> some Feature {
        self.modifier(OAuthAuthorizationFailurePresentationModifier())
    }
}

public extension FeatureProtocol
where
    State == OAuthAuthorization<OpenMusicEventAppRoot>.State,
    Action == OAuthAuthorization<OpenMusicEventAppRoot>.Action
{
    func deliverAuthoringAuthorizationChanges() -> some Feature {
        self.modifier(AuthoringAuthorizationDeliveryModifier())
    }
}

struct AuthoringAuthorizationDeliveryModifier: FeatureModifier {
    typealias State = OAuthAuthorization<OpenMusicEventAppRoot>.State
    typealias Action = OAuthAuthorization<OpenMusicEventAppRoot>.Action

    let store = FeatureStore<State, Action>()

    func body(content: Content) -> some FeatureProtocol<State, Action> {
        content
            .onChange(of: store.authentication.session?.accountID) {
                oldAccountID,
                accountID,
                _ in
                guard oldAccountID == nil, accountID != nil else { return }
                store.addTask {
                    try store.content.eventViewer?
                        .authoring.content.content
                        .authoringAuthorizationInvalidated()
                }
            }
            .onEvent(OAuthAuthorizationInvalidated.self) { _, _ in
                store.addTask {
                    try store.content.eventViewer?
                        .authoring.content.content
                        .authoringAuthorizationInvalidated()
                }
            }
    }
}

private struct OAuthAuthorizationFailurePresentationModifier: FeatureModifier {
    typealias State = OAuthAuthorization<OpenMusicEventAppRoot>.State
    typealias Action = OAuthAuthorization<OpenMusicEventAppRoot>.Action

    @Dependency(\.continuousClock) var clock
    @Dependency(\.errorNotificationPresentation) var errorNotificationPresentation

    let store = FeatureStore<State, Action>()

    func body(content: Content) -> some FeatureProtocol<State, Action> {
        content
            .onEvent(OAuthAuthorizationFailed.self) { failure, state in
                guard let error = resolvedHandledError(
                    from: failure.originalError,
                    fallbackMessage: .authenticationAuthorizationFailed,
                    operation: .authenticationAuthorization
                ) else {
                    return
                }
                state.content.errorNotifications.state.report(error)
                store.addTask {
                    await errorNotificationPresentation.show(.error(error))
                }
                store.addTask {
                    try await clock.sleep(for: ErrorNotifications.automaticDismissDelay)
                    try store.modify {
                        $0.content.errorNotifications.state.dismiss(id: error.id)
                    }
                }
            }
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
