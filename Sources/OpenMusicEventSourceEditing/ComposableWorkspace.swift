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
            proposalRecordedTrigger: \.workspaceProposalRecorded
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
            updateReference: { source, workspaceID, submission, proposal in
                let sourceWorkspaceID = SourceWorkspace.ID(rawValue: workspaceID.rawValue)
                try await referenceUpdate.advance(
                    source,
                    sourceWorkspaceID,
                    submission,
                    proposal
                )
                return proposal.source
            },
            captureChanges: { source, workspaceID, request in
                let sourceWorkspaceID = SourceWorkspace.ID(rawValue: workspaceID.rawValue)
                precondition(source.workspace.id == sourceWorkspaceID)
                let sourcePersistence = persistence
                if let capture = try sourcePersistence.capture(
                    workspaceID: sourceWorkspaceID,
                    requestID: request.id
                ) {
                    return capture.isEmpty ? .noChanges : .changes(capture)
                }
                let capture = try await patchGenerator.generate(
                    SourceWorkspacePatchRequest(workspace: source.workspace)
                )
                try await sourcePersistence.saveCapture(
                    capture,
                    workspaceID: sourceWorkspaceID,
                    requestID: request.id
                )
                return capture.isEmpty ? .noChanges : .changes(capture)
            },
            loadSubmission: { workspaceID in
                try persistence.submission(
                    SourceWorkspace.ID(rawValue: workspaceID.rawValue)
                )
            },
            prepareSource: { workspaceID in
                let sourceWorkspaceID = SourceWorkspace.ID(rawValue: workspaceID.rawValue)
                let prepared = try await preparation.prepare(
                    SourceWorkspace(id: sourceWorkspaceID)
                )
                return prepared
            },
            pushCommit: { source, workspaceID, submission in
                try await publisher.pushCommit(
                    workspaceID: SourceWorkspace.ID(rawValue: workspaceID.rawValue),
                    submission: submission,
                    persistence: persistence
                )
            },
            reconcileSource: { source, workspaceID, reconciliation in
                try await referenceUpdate.reconcile(
                    source,
                    SourceWorkspace.ID(rawValue: workspaceID.rawValue),
                    reconciliation
                )
            },
            recordProposal: { source, workspaceID, submission, commit in
                try await publisher.recordProposal(
                    workspaceID: SourceWorkspace.ID(rawValue: workspaceID.rawValue),
                    submission: submission,
                    commit: commit,
                    persistence: persistence
                )
            },
            removeSubmission: { source, workspaceID, submissionID in
                try await persistence.removeSubmission(
                    workspaceID: SourceWorkspace.ID(rawValue: workspaceID.rawValue),
                    submissionID: submissionID
                )
            },
            saveSubmission: { source, workspaceID, submission in
                try await persistence.save(
                    submission,
                    workspaceID: SourceWorkspace.ID(rawValue: workspaceID.rawValue)
                )
            }
        )
    }
}

private enum OpenMusicEventAuthoringIntegrationError: Error {
    case grantWorkspaceMismatch
}
