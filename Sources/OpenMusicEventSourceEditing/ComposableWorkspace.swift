public import ComposableAuthoring
public import ComposableAuthoringWorkspace
public import ComposableWorkspace

import ComposableArchitecture2
import Dependencies
import OpenMusicEventLexicon
import Sharing
import SourceEditing

public protocol OpenMusicEventWorkspaceContentState: ValueObservable {
    var authoringAuthorizationInvalidated: Trigger<()> { get }
    var workspaceBaselineSelectionFailed: Trigger<WorkspaceFailure> { get }
    var workspaceChangesPublicationFailed: Trigger<WorkspaceFailure> { get }
    var workspaceChangesPublished: Trigger<WorkspaceBranchReference> { get }
    var workspaceChangesPublishing: Trigger<()> { get }
    var workspaceProposalPublicationFailed: Trigger<WorkspaceFailure> { get }
    var workspaceProposalPublishing: Trigger<()> { get }
    var workspaceProposalRecorded: Trigger<WorkspaceProposal> { get }
    var workspaceSourcePrepared: Trigger<()> { get }
}

/// The sole OME composition of authorization, source preparation, editing, and publication.
public struct OpenMusicEventAuthoringWorkspace<Content: FeatureProtocol>: FeatureProtocol
where Content.State: OpenMusicEventWorkspaceContentState {
    public typealias Feature = ComposableAuthoringWorkspace.AuthoringWorkspace<
        OpenMusicEventWorkspaceContent<Content>,
        SourceWorkspace,
        AuthoringEligibility,
        AuthoringGrant,
        SourceWorkspaceResource,
        SourcePatch
    >
    public typealias State = Feature.State
    public typealias Action = Feature.Action
    public typealias AuthoringFeature = Feature.AuthoringFeature
    public typealias WorkspaceFeature = Feature.WorkspaceFeature

    public init(makeContent: @escaping () -> Content) {
        self.makeContent = makeContent
    }

    let makeContent: () -> Content

    public static func state(
        workspace: SourceWorkspace,
        grant: Shared<AuthoringGrant?> = Shared(value: nil),
        makeContentState: () -> Content.State
    ) -> State {
        State(context: workspace, grant: grant) {
            WorkspaceFeature.State(
                workspaceID: WorkspaceID(rawValue: workspace.id.rawValue),
                makeContentState: makeContentState
            )
        }
    }

    public var body: some FeatureProtocol<State, Action> {
        Feature(
            sourcePreparedTrigger: \.workspaceSourcePrepared,
            proposalPublishingTrigger: \.workspaceProposalPublishing,
            proposalRecordedTrigger: \.workspaceProposalRecorded,
            proposalPublicationFailedTrigger: \.workspaceProposalPublicationFailed,
            changesPublishingTrigger: \.workspaceChangesPublishing,
            changesPublishedTrigger: \.workspaceChangesPublished,
            changesPublicationFailedTrigger: \.workspaceChangesPublicationFailed,
            contextSelectionFailedTrigger: \.workspaceBaselineSelectionFailed
        ) {
            OpenMusicEventWorkspaceContent(makeContent: makeContent)
        }
    }
}

public struct OpenMusicEventWorkspaceContent<Content: FeatureProtocol>: FeatureProtocol {
    public typealias State = Content.State
    public typealias Action = Content.Action

    let makeContent: () -> Content

    public var body: some FeatureProtocol<State, Action> {
        makeContent()
    }
}

public extension ComposableWorkspace.WorkspaceClient
where Source == SourceWorkspaceResource, ChangeSet == SourcePatch {
    static var openMusicEvent: Self {
        @Dependency(\.defaultDatabase) var database
        @Dependency(SourcePatchGeneratorKey<SourceWorkspacePatchRequest>.self) var patchGenerator
        @Dependency(SourceWorkspacePreparationClient.self) var preparation
        @Dependency(WorkspaceReferenceUpdateClient.self) var referenceUpdate
        let persistence = WorkspacePublicationPersistence(database: database)
        let publisher = TangledWorkspacePublisher()

        return Self(
            prepareSource: { workspaceID in
                let sourceWorkspaceID = SourceWorkspace.ID(rawValue: workspaceID.rawValue)
                return try await preparation.prepare(
                    SourceWorkspace(id: sourceWorkspaceID)
                )
            },
            captureChanges: { source, workspaceID in
                let sourceWorkspaceID = SourceWorkspace.ID(rawValue: workspaceID.rawValue)
                precondition(source.workspace.id == sourceWorkspaceID)
                let capture = try await patchGenerator.generate(
                    SourceWorkspacePatchRequest(workspace: source.workspace)
                )
                return capture.isEmpty ? .noChanges : .changes(capture)
            },
            publishProposal: { source, workspaceID, attempt in
                let sourceWorkspaceID = SourceWorkspace.ID(rawValue: workspaceID.rawValue)
                precondition(source.workspace.id == sourceWorkspaceID)
                let proposal = try await publisher.publishProposal(
                    source: source,
                    workspaceID: sourceWorkspaceID,
                    attempt: attempt,
                    persistence: persistence
                )
                return WorkspaceProposalPublication(proposal: proposal)
            },
            publishChanges: { source, workspaceID, attempt in
                let sourceWorkspaceID = SourceWorkspace.ID(rawValue: workspaceID.rawValue)
                precondition(source.workspace.id == sourceWorkspaceID)
                let update = try await referenceUpdate.preparePublishedUpdate(
                    source,
                    sourceWorkspaceID,
                    attempt
                )
                let published = try await publisher.publishChanges(
                    source: source,
                    workspaceID: sourceWorkspaceID,
                    attempt: attempt
                )
                let baseline: WorkspaceBranchReference
                do {
                    baseline = try await update.apply(published)
                } catch let incomplete as WorkspaceReferenceUpdateIncomplete {
                    TangledWorkspacePublisherDiagnostics.log(
                        operation: "published-reference.install",
                        status: .failed,
                        details: [
                            "workspace: \(sourceWorkspaceID.rawValue)",
                            "branch: \(published.branch.rawValue)",
                            "merge: complete; metadata refresh remains available",
                        ],
                        error: incomplete
                    )
                    baseline = incomplete.mountedBaseline
                }
                return WorkspacePublishedChanges(
                    published: published,
                    session: WorkspaceSession(source: source, baseline: baseline)
                )
            },
            refreshBaseline: { source, workspaceID, current in
                try await referenceUpdate.refresh(
                    source,
                    SourceWorkspace.ID(rawValue: workspaceID.rawValue),
                    current
                )
            },
            selectBranch: { source, workspaceID, branch in
                try await referenceUpdate.select(
                    source,
                    SourceWorkspace.ID(rawValue: workspaceID.rawValue),
                    branch
                )
            }
        )
    }
}

private enum OpenMusicEventAuthoringIntegrationError: Error {
    case grantWorkspaceMismatch
}
