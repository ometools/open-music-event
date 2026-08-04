import ComposableArchitecture2
import ComposableAuthoring
import ComposableWorkspace
import Dependencies
import OpenMusicEventAppEventViewer
import OpenMusicEventSourceEditing
import SourceEditing

/// OME's integration of the package-owned authoring workspace with `EventViewer`.
///
/// This feature adds no state machine. It installs OME's live policy and workspace clients and
/// translates application requests and authorization changes into the package's actions.
public struct OpenMusicEventWorkspace: FeatureProtocol {
    public typealias Composition = OpenMusicEventAuthoringWorkspace<EventViewer>
    public typealias State = Composition.State
    public typealias Action = Composition.Action

    public init() {}

    public var body: some FeatureProtocol<State, Action> {
        Composition {
            EventViewer()
        }
            .modifier(OpenMusicEventWorkspaceLifecycle())
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

struct OpenMusicEventWorkspaceLifecycle: FeatureModifier {
    typealias WorkspaceAuthoring = OpenMusicEventAuthoringWorkspace<EventViewer>
    typealias State = WorkspaceAuthoring.State
    typealias Action = WorkspaceAuthoring.Action

    @Dependency(WorkspaceAuthoringActivationClient.self) var activations
    let store = FeatureStore<State, Action>()

    func body(content: Content) -> some FeatureProtocol<State, Action> {
        content
            .onMount { state in
                let requestsEntry = state
                    .authoring
                    .content
                    .content
                    .pendingAuthoringEntry != nil
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
