import ComposableArchitecture2
import ComposableAuthoring
import ComposableWorkspace
import Dependencies
import OpenMusicEventAppEventViewer
import OpenMusicEventSourceEditing
import SourceEditing

/// OME's integration of the package-owned authoring workspace with `EventDetail`.
///
/// This feature adds no state machine. It installs OME's eligibility-aware authoring client and
/// workspace client, then translates application requests into the package's actions.
public struct OpenMusicEventWorkspace: FeatureProtocol {
    public typealias Composition = OpenMusicEventAuthoringWorkspace<EventDetail>
    public typealias State = Composition.State
    public typealias Action = Composition.Action

    public init() {}

    public var body: some FeatureProtocol<State, Action> {
        Composition {
            EventDetail()
        }
            .modifier(OpenMusicEventWorkspaceLifecycle())
            .dependency(
                ComposableAuthoring.AuthoringClient<
                    SourceWorkspace,
                    AuthoringEligibility,
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
    typealias WorkspaceAuthoring = OpenMusicEventAuthoringWorkspace<EventDetail>
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
                    var canRequestEntry = false
                    let check = try store.modify { state in
                        canRequestEntry = state.authoring.phase.canRequestEntry
                    }
                    await check?.value
                    guard requestsEntry, canRequestEntry else { return }
                    let entry = try store.send(
                        .authoring(.entryRequested)
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
                        .authoring(.entryRequested)
                    )
                    await entry?.value
                }
            }
            .onEvent(AuthoringExitRequested.self) { _, state in
                let workspaceID = state.authoring.context.id
                store.addTask {
                    let exit = try store.send(
                        .authoring(.exitButtonTapped)
                    )
                    await exit?.value
                    let reset = try store.modify { state in
                        guard state.authoring.grant == nil else { return }
                        // Published content is already committed to SQLite. Preserve the mounted
                        // EventDetail read model, but discard the authorized source/phase so a
                        // later authoring entry must restore the selected branch.
                        let content = state.authoring.content.content
                        state.authoring.content = WorkspaceAuthoring.WorkspaceFeature.State(
                            workspaceID: WorkspaceID(rawValue: workspaceID.rawValue),
                            makeContentState: { content }
                        )
                    }
                    await reset?.value
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
            .transformDependency(\.self) {
                $0.defaultEventID = store.id
            }
    }
}
