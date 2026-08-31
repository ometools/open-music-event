import ComposableArchitecture2
import Dependencies
import ErrorHandling
import OpenMusicEventAuthentication
import TCATProtoAuthentication
import ComposableNotifications

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
    State == OpenMusicEventApplication.State,
    Action == OpenMusicEventApplication.Action
{
    func presentAuthorizationFailures() -> some Feature {
        self.modifier(OAuthAuthorizationFailurePresentationModifier())
    }
}

public extension FeatureProtocol
where
    State == OpenMusicEventApplication.State,
    Action == OpenMusicEventApplication.Action
{
    func deliverAuthoringAuthorizationChanges() -> some Feature {
        self.modifier(AuthoringAuthorizationDeliveryModifier())
    }
}

struct AuthoringAuthorizationDeliveryModifier: FeatureModifier {
    typealias State = OpenMusicEventApplication.State
    typealias Action = OpenMusicEventApplication.Action

    let store = FeatureStore<State, Action>()

    func body(content: Content) -> some FeatureProtocol<State, Action> {
        content
            .onEvent(OpenMusicEventSelectedAccountChanged.self) { _, state in
                let invalidation = state.content.destination?.eventViewer?
                    .authoring.content.content
                    .authoringAuthorizationInvalidated
                store.addTask {
                    let reaction = try invalidation?()
                    await reaction?.value
                }
            }
            .onEvent(OAuthAuthorizationInvalidated.self) { _, state in
                let invalidation = state.content.destination?.eventViewer?
                    .authoring.content.content
                    .authoringAuthorizationInvalidated
                store.addTask {
                    let reaction = try invalidation?()
                    await reaction?.value
                }
            }
    }
}

private struct OAuthAuthorizationFailurePresentationModifier: FeatureModifier {
    typealias State = OpenMusicEventApplication.State
    typealias Action = OpenMusicEventApplication.Action

    @Dependency(\.continuousClock) var clock
    @Dependency(\.errorNotificationPresentation) var errorNotificationPresentation

    let store = FeatureStore<State, Action>()

    func body(content: Content) -> some FeatureProtocol<State, Action> {
        content
            .onEvent(OAuthAuthorizationFailed.self) { failure, state -> FeatureEventPropagation in
                guard let error = resolvedHandledError(
                    from: failure.originalError,
                    fallbackMessage: .authenticationAuthorizationFailed,
                    operation: .authenticationAuthorization
                ) else {
                    return .stop
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
                return .stop
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
