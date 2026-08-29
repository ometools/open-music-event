public import ComposableAuthoring
public import ComposableAuthoringWorkspace
public import ComposableWorkspace

import ComposableArchitecture2
import Dependencies
import OpenMusicEventLexicon
import Sharing
import SourceEditing

public protocol OpenMusicEventWorkspaceContentState {
    var authoringAuthorizationInvalidated: Trigger<()> { get }
    var workspaceContextSelectionFailed: Trigger<WorkspaceFailure> { get }
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
            contextSelectionFailedTrigger: \.workspaceContextSelectionFailed
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

public extension WorkspaceEditingContext {
    var revision: WorkspaceRevision {
        switch self {
        case let .branch(reference), let .published(reference):
            reference.revision
        case let .proposal(proposal):
            proposal.revision
        }
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
                let update = try await referenceUpdate.preparePublication(
                    source,
                    sourceWorkspaceID,
                    attempt
                )
                let proposal = try await publisher.publishProposal(
                    source: source,
                    workspaceID: sourceWorkspaceID,
                    attempt: attempt,
                    persistence: persistence
                )
                let context: WorkspaceEditingContext
                let referenceUpdateIsComplete: Bool
                do {
                    context = try await update.apply(proposal)
                    referenceUpdateIsComplete = true
                } catch let incomplete as WorkspaceReferenceUpdateIncomplete {
                    TangledWorkspacePublisherDiagnostics.log(
                        operation: "reference.install",
                        status: .failed,
                        details: [
                            "workspace: \(sourceWorkspaceID.rawValue)",
                            "proposal: \(proposal.id.rawValue)",
                            "publication: recorded; proposal snapshot is mounted; metadata repair remains pending",
                        ],
                        error: incomplete
                    )
                    context = incomplete.mountedContext
                    referenceUpdateIsComplete = false
                } catch {
                    TangledWorkspacePublisherDiagnostics.log(
                        operation: "reference.install",
                        status: .failed,
                        details: [
                            "workspace: \(sourceWorkspaceID.rawValue)",
                            "proposal: \(proposal.id.rawValue)",
                            "publication: recorded; proposal snapshot repair remains pending",
                        ],
                        error: error
                    )
                    context = (try? persistence.context(sourceWorkspaceID))
                        ?? attempt.target.editingContext
                    referenceUpdateIsComplete = false
                }
                if referenceUpdateIsComplete {
                    do {
                        try await persistence.completeRepair(workspaceID: sourceWorkspaceID)
                    } catch {
                        TangledWorkspacePublisherDiagnostics.log(
                            operation: "reference.repair-cleanup",
                            status: .failed,
                            details: [
                                "workspace: \(sourceWorkspaceID.rawValue)",
                                "proposal: \(proposal.id.rawValue)",
                                "publication: recorded; cleanup will retry during preparation",
                            ],
                            error: error
                        )
                    }
                }
                return WorkspaceProposalPublication(
                    proposal: proposal,
                    session: WorkspaceSession(source: source, selectedContext: context)
                )
            },
            refreshContext: { source, workspaceID, current in
                try await referenceUpdate.refresh(
                    source,
                    SourceWorkspace.ID(rawValue: workspaceID.rawValue),
                    current
                )
            },
            selectContext: { source, workspaceID, selection in
                try await referenceUpdate.select(
                    source,
                    SourceWorkspace.ID(rawValue: workspaceID.rawValue),
                    selection
                )
            }
        )
    }
}

private enum OpenMusicEventAuthoringIntegrationError: Error {
    case grantWorkspaceMismatch
}
