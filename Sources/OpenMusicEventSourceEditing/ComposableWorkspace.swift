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

    @FeatureEnvironment(WorkspaceContext<SourceWorkspaceResource, SourcePatch>.self)
    var workspace

    let makeContent: () -> Content

    public var body: some FeatureProtocol<State, Action> {
        makeContent()
            .transformDependency(\.defaultDatabase) { database in
                guard let source = workspace.source.wrappedValue else { return }
                database = source.database
            }
    }
}

public extension ComposableAuthoring.AuthoringClient
where Context == SourceWorkspace, Grant == AuthoringGrant {
    static var openMusicEvent: Self {
        @Dependency(AuthoringPolicyClient.self) var policy
        @Dependency(WorkspaceAuthoringActivationClient.self) var activations

        return Self(
            admission: { workspace in
                switch try await policy.admission(workspace) {
                case .granted, .signInRequired:
                    return .available
                case .denied:
                    return .unavailable
                }
            },
            enter: { workspace in
                var admission = try await policy.admission(workspace)
                if case .signInRequired = admission {
                    try await policy.requestSignIn()
                    admission = try await policy.admission(workspace)
                }

                let principal: AuthoringPrincipal
                let role: OME.WorkspaceRole
                switch admission {
                case let .granted(grantedPrincipal, grantedRole):
                    principal = grantedPrincipal
                    role = grantedRole
                case .signInRequired:
                    throw AuthoringPolicyError.authorizationRequired
                case .denied:
                    throw AuthoringPolicyError.admissionDenied
                }

                try await policy.authorizeEntry(workspace, principal)
                try await activations.activate(workspace.id, principal, role)
                return AuthoringGrant(
                    principal: principal,
                    role: role,
                    workspaceID: workspace.id
                )
            },
            exit: { workspace, grant in
                guard grant.workspaceID == workspace.id else {
                    throw OpenMusicEventAuthoringIntegrationError.grantWorkspaceMismatch
                }
                try await activations.deactivate(workspace.id)
            },
            restore: { workspace in
                guard let activation = try activations.current(workspace.id) else {
                    return nil
                }

                switch try await policy.admission(workspace) {
                case let .granted(principal, role)
                    where principal == activation.principal:
                    try await policy.authorizeEntry(workspace, principal)
                    try await activations.activate(workspace.id, principal, role)
                    return AuthoringGrant(
                        principal: principal,
                        role: role,
                        workspaceID: workspace.id
                    )

                case .granted, .signInRequired, .denied:
                    try await activations.deactivate(workspace.id)
                    return nil
                }
            }
        )
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
                return .proposal(proposal)
            },
            captureChanges: { source, workspaceID, request in
                let sourceWorkspaceID = SourceWorkspace.ID(rawValue: workspaceID.rawValue)
                precondition(source.workspace.id == sourceWorkspaceID)
                if let capture = try persistence.capture(
                    workspaceID: sourceWorkspaceID,
                    requestID: request.id
                ) {
                    return capture.isEmpty ? .noChanges : .changes(capture)
                }
                let capture = try await withDependencies {
                    $0.defaultDatabase = source.database
                } operation: {
                    try await patchGenerator.generate(
                        SourceWorkspacePatchRequest(workspace: source.workspace)
                    )
                }
                try await persistence.saveCapture(
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
                guard let proposal = try persistence.openProposal(sourceWorkspaceID) else {
                    return prepared
                }
                guard prepared.line.editingReference.revision == proposal.source.revision else {
                    throw OpenMusicEventAuthoringIntegrationError.openProposalRevisionMismatch
                }
                return WorkspacePreparation(line: .proposal(proposal), source: prepared.source)
            },
            pushCommit: { workspaceID, submission in
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
            recordProposal: { workspaceID, submission, commit in
                try await publisher.recordProposal(
                    workspaceID: SourceWorkspace.ID(rawValue: workspaceID.rawValue),
                    submission: submission,
                    commit: commit,
                    persistence: persistence
                )
            },
            removeSubmission: { workspaceID, submissionID in
                try await persistence.removeSubmission(
                    workspaceID: SourceWorkspace.ID(rawValue: workspaceID.rawValue),
                    submissionID: submissionID
                )
            },
            saveSubmission: { workspaceID, submission in
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
    case openProposalRevisionMismatch
}
