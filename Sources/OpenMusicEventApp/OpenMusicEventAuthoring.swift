import ComposableArchitecture2
import ComposableAuthoring
import ComposableAuthoringWorkspace
import ComposableWorkspace
import Dependencies
import Foundation
import OpenMusicEventAppEventViewer
import OpenMusicEventAuthentication
import OpenMusicEventSourceEditing
import SourceEditing
import SQLiteData
import TCATProtoAuthentication

public typealias OpenMusicEventWorkspaceAuthoring<Content: FeatureProtocol> =
    OAuthAuthorization<OpenMusicEventAuthoringWorkspace<Content>>
where Content.State: OpenMusicEventWorkspaceContentState

/// The application composition used whenever an event is opened.
///
/// This adds no state or action layer. Its only job is to mount the live OAuth, authoring, and
/// workspace adapters at the application's ownership boundary.
public struct OpenMusicEventEventAuthoring: FeatureProtocol {
    public typealias State = OpenMusicEventWorkspaceAuthoring<EventViewer>.State
    public typealias Action = OpenMusicEventWorkspaceAuthoring<EventViewer>.Action

    public init() {}

    public var body: some FeatureProtocol<State, Action> {
        OpenMusicEventWorkspaceAuthoring<EventViewer>(
            storage: OpenMusicEventOAuth.storage
        ) {
            OpenMusicEventAuthoringWorkspace<EventViewer> {
                EventViewer()
            }
        }
        .openMusicEventWorkspaceLifecycle { state in
            state.pendingAuthoringEntry != nil
        }
    }
}

extension OAuthAuthorization {
    func openMusicEventWorkspaceLifecycle<WorkspaceContent>(
        requestsEntry: @escaping (WorkspaceContent.State) -> Bool = { _ in false }
    ) -> some FeatureProtocol<State, Action>
    where
        WorkspaceContent: FeatureProtocol,
        WorkspaceContent.State: OpenMusicEventWorkspaceContentState,
        Content == OpenMusicEventAuthoringWorkspace<WorkspaceContent>
    {
        self
            .modifier(
                OpenMusicEventWorkspaceLifecycleModifier(
                    requestsEntry: requestsEntry
                )
            )
            .dependency(
                ComposableAuthoring.AuthoringClient<
                    SourceWorkspace,
                    AuthoringGrant
                >.openMusicEvent
            )
            .dependency(
                ComposableWorkspace.WorkspaceClient<
                    SourceWorkspaceResource,
                    SourcePatch
                >.openMusicEvent
            )
    }
}

extension OpenMusicEventAuthoringWorkspace {
    func openMusicEventWorkspaceLifecycle(
        requestsEntry: @escaping (Content.State) -> Bool = { _ in false }
    ) -> some FeatureProtocol<State, Action> {
        self
            .modifier(
                OpenMusicEventBareWorkspaceLifecycleModifier(
                    requestsEntry: requestsEntry
                )
            )
            .dependency(
                ComposableAuthoring.AuthoringClient<
                    SourceWorkspace,
                    AuthoringGrant
                >.openMusicEvent
            )
            .dependency(
                ComposableWorkspace.WorkspaceClient<
                    SourceWorkspaceResource,
                    SourcePatch
                >.openMusicEvent
            )
    }
}

struct OpenMusicEventBareWorkspaceLifecycleModifier<WorkspaceContent: FeatureProtocol>:
    FeatureModifier
where WorkspaceContent.State: OpenMusicEventWorkspaceContentState {
    typealias WorkspaceAuthoring = OpenMusicEventAuthoringWorkspace<WorkspaceContent>
    typealias State = WorkspaceAuthoring.State
    typealias Action = WorkspaceAuthoring.Action

    @Dependency(WorkspaceAuthoringActivationClient.self) var activations
    @FeatureEnvironment(OpenMusicEventAuthorizationContext.self) var authorization
    let store = FeatureStore<State, Action>()
    let requestsEntry: (WorkspaceContent.State) -> Bool

    func body(content: Content) -> some FeatureProtocol<State, Action> {
        content
            .transformDependency(\.oauthAuthorizationBroker) {
                $0 = authorization.broker
            }
            .onMount { state in
                let requestsEntry = requestsEntry(
                    state.authoring.content.content
                )
                store.addTask {
                    let restoration = try store.send(
                        .authoring(.restoreAuthorization)
                    )
                    await restoration?.value
                    guard requestsEntry,
                          store.state.authoring.grant == nil,
                          store.state.authoring.canEnter
                    else { return }
                    let entry = try store.send(
                        .authoring(.enterButtonTapped)
                    )
                    await entry?.value
                }
            }
            .onTrigger(
                store.authoring.content.content.authoringAuthorizationInvalidated
            ) { state in
                let workspaceID = state.authoring.context
                let activations = activations
                store.addTask {
                    let invalidation = try store.send(
                        .authoring(.authorizationInvalidated)
                    )
                    await invalidation?.value
                    try await activations.deactivate(workspaceID.id)
                    let admission = try store.send(
                        .authoring(.refreshAdmission)
                    )
                    await admission?.value
                }
            }
            .onEvent(AuthoringRequested.self) { _, _ in
                store.addTask {
                    let entry = try store.send(
                        .authoring(.enterButtonTapped)
                    )
                    await entry?.value
                }
            }
            .onEvent(AuthoringExitRequested.self) { _, _ in
                store.addTask {
                    let exit = try store.send(
                        .authoring(.exitButtonTapped)
                    )
                    await exit?.value
                }
            }
            .onEvent(SourceWorkspacePreparationRetryRequested.self) { _, _ in
                store.addTask {
                    let retry = try store.send(
                        .authoring(.content(.sourcePreparationRetryButtonTapped))
                    )
                    await retry?.value
                }
            }
            .onEvent(AuthoringAccessRevoked.self) { _, state in
                let workspaceID = state.authoring.context
                let activations = activations
                store.addTask {
                    let invalidation = try store.send(
                        .authoring(.authorizationInvalidated)
                    )
                    await invalidation?.value
                    try await activations.deactivate(workspaceID.id)
                    let admission = try store.send(
                        .authoring(.refreshAdmission)
                    )
                    await admission?.value
                }
            }
    }
}

struct OpenMusicEventWorkspaceLifecycleModifier<WorkspaceContent: FeatureProtocol>:
    FeatureModifier
where WorkspaceContent.State: OpenMusicEventWorkspaceContentState {
    typealias WorkspaceAuthoring = OpenMusicEventAuthoringWorkspace<WorkspaceContent>
    typealias State = OAuthAuthorization<WorkspaceAuthoring>.State
    typealias Action = OAuthAuthorization<WorkspaceAuthoring>.Action

    @Dependency(WorkspaceAuthoringActivationClient.self) var activations
    let store = FeatureStore<State, Action>()
    let requestsEntry: (WorkspaceContent.State) -> Bool

    func body(content: Content) -> some FeatureProtocol<State, Action> {
        content
            .onMount { state in
                let requestsEntry = requestsEntry(
                    state.content.authoring.content.content
                )
                store.addTask {
                    let restoration = try store.send(
                        .content(.authoring(.restoreAuthorization))
                    )
                    await restoration?.value
                    guard requestsEntry,
                          store.state.content.authoring.grant == nil,
                          store.state.content.authoring.canEnter
                    else { return }
                    let entry = try store.send(
                        .content(.authoring(.enterButtonTapped))
                    )
                    await entry?.value
                }
            }
            .onChange(of: store.authentication.session?.accountID) {
                oldAccountID,
                accountID,
                state in
                guard oldAccountID == nil, accountID != nil else { return }
                let workspaceID = state.content.authoring.context
                let activations = activations
                store.addTask {
                    let invalidation = try store.send(
                        .content(.authoring(.authorizationInvalidated))
                    )
                    await invalidation?.value
                    try await activations.deactivate(workspaceID.id)
                    let admission = try store.send(
                        .content(.authoring(.refreshAdmission))
                    )
                    await admission?.value
                }
            }
            .onEvent(AuthoringRequested.self) { _, _ in
                store.addTask {
                    let entry = try store.send(
                        .content(.authoring(.enterButtonTapped))
                    )
                    await entry?.value
                }
            }
            .onEvent(AuthoringExitRequested.self) { _, _ in
                store.addTask {
                    let exit = try store.send(
                        .content(.authoring(.exitButtonTapped))
                    )
                    await exit?.value
                }
            }
            .onEvent(SourceWorkspacePreparationRetryRequested.self) { _, _ in
                store.addTask {
                    let retry = try store.send(
                        .content(
                            .authoring(.content(.sourcePreparationRetryButtonTapped))
                        )
                    )
                    await retry?.value
                }
            }
            .onEvent(AuthoringAccessRevoked.self) { _, state in
                let workspaceID = state.content.authoring.context
                let activations = activations
                store.addTask {
                    let invalidation = try store.send(
                        .content(.authoring(.authorizationInvalidated))
                    )
                    await invalidation?.value
                    try await activations.deactivate(workspaceID.id)
                    let admission = try store.send(
                        .content(.authoring(.refreshAdmission))
                    )
                    await admission?.value
                }
            }
            .onEvent(OAuthAuthorizationInvalidated.self) { _, state in
                let workspaceID = state.content.authoring.context
                let activations = activations
                store.addTask {
                    let invalidation = try store.send(
                        .content(.authoring(.authorizationInvalidated))
                    )
                    await invalidation?.value
                    try await activations.deactivate(workspaceID.id)
                    let admission = try store.send(
                        .content(.authoring(.refreshAdmission))
                    )
                    await admission?.value
                }
            }
    }
}
