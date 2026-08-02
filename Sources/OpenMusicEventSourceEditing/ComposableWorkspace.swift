public import ComposableAuthoring
public import ComposableAuthoringWorkspace
public import ComposableWorkspace

import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventLexicon
import Sharing
import SourceEditing
import SQLiteData

/// The parent-to-child trigger used when OME's prepared workspace source becomes available.
public protocol OpenMusicEventWorkspaceContentState {
    var workspaceProposalRecorded: Trigger<WorkspaceProposal> { get }
    var workspaceSourcePrepared: Trigger<()> { get }
}

/// Composes OME authoring and workspace behavior without adding another state or action layer.
public struct OpenMusicEventAuthoringWorkspace<Content: FeatureProtocol>: FeatureProtocol
where Content.State: OpenMusicEventWorkspaceContentState {
    public typealias Feature = ComposableAuthoringWorkspace.AuthoringWorkspace<
        OpenMusicEventWorkspaceContent<Content>,
        EditingWorkspaceRecord.ID,
        AuthoringGrant,
        SourceWorkspaceDatabase,
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
        workspaceID: EditingWorkspaceRecord.ID,
        grant: Shared<AuthoringGrant?> = Shared(value: nil),
        makeContentState: () -> Content.State
    ) -> State {
        State(context: workspaceID, grant: grant) {
            WorkspaceFeature.State(
                workspaceID: WorkspaceID(rawValue: workspaceID.rawValue),
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

    @FeatureEnvironment(WorkspaceContext<SourceWorkspaceDatabase, SourcePatch>.self)
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
where Context == EditingWorkspaceRecord.ID, Grant == AuthoringGrant {
    static var openMusicEvent: Self {
        @Dependency(AuthoringPolicyClient.self) var policy
        @Dependency(WorkspaceAuthoringActivationClient.self) var activations

        return Self(
            admission: { workspaceID in
                switch try await policy.admission(workspaceID) {
                case .granted, .signInRequired:
                    return .available
                case .denied:
                    return .unavailable
                }
            },
            enter: { workspaceID in
                var admission = try await policy.admission(workspaceID)
                if case .signInRequired = admission {
                    try await policy.requestSignIn()
                    admission = try await policy.admission(workspaceID)
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

                try await policy.authorizeEntry(workspaceID, principal)
                try await activations.activate(workspaceID, principal, role)
                return AuthoringGrant(
                    principal: principal,
                    role: role,
                    workspaceID: workspaceID
                )
            },
            exit: { workspaceID, grant in
                guard grant.workspaceID == workspaceID else {
                    throw OpenMusicEventAuthoringIntegrationError.grantWorkspaceMismatch
                }
                try await activations.deactivate(workspaceID)
            },
            restore: { workspaceID in
                guard let activation = try activations.current(workspaceID) else {
                    return nil
                }

                switch try await policy.admission(workspaceID) {
                case let .granted(principal, role)
                    where principal == activation.principal:
                    try await policy.authorizeEntry(workspaceID, principal)
                    try await activations.activate(workspaceID, principal, role)
                    return AuthoringGrant(
                        principal: principal,
                        role: role,
                        workspaceID: workspaceID
                    )

                case .granted, .signInRequired, .denied:
                    try await activations.deactivate(workspaceID)
                    return nil
                }
            }
        )
    }
}

public extension ComposableWorkspace.WorkspaceClient
where Source == SourceWorkspaceDatabase, ChangeSet == SourcePatch {
    static var openMusicEvent: Self {
        @Dependency(\.defaultDatabase) var database
        @Dependency(
            SourcePatchGeneratorKey<OpenMusicEventCalendarSourcePatchRequest>.self
        ) var patchGenerator
        @Dependency(WorkspacePreparationClient.self) var preparation
        @Dependency(WorkspaceReferenceUpdateClient.self) var referenceUpdate
        @Dependency(\.workspaceReferenceDatabase) var workspaceReferenceDatabase
        let persistence = WorkspacePublicationPersistence(database: database)
        let publisher = TangledWorkspacePublisher()

        return Self(
            updateReference: { source, workspaceID, submission, proposal in
                let editingWorkspaceID = EditingWorkspaceRecord.ID(
                    rawValue: workspaceID.rawValue
                )
                try await referenceUpdate.advance(
                    source,
                    editingWorkspaceID,
                    submission,
                    proposal
                )
                let line = WorkspaceEditingLine.proposal(proposal)
                try await persistence.advance(to: line, workspaceID: editingWorkspaceID)
                return line
            },
            captureChanges: { source, workspaceID, request in
                let editingWorkspaceID = EditingWorkspaceRecord.ID(
                    rawValue: workspaceID.rawValue
                )
                if let capture = try persistence.capture(
                    workspaceID: editingWorkspaceID,
                    requestID: request.id
                ) {
                    return capture.isEmpty ? .noChanges : .changes(capture)
                }
                let patchRequest = try await workspacePatchRequest(
                    editingWorkspaceID,
                    database: database
                )
                let capture = try await withDependencies {
                    $0.defaultDatabase = source.database
                } operation: {
                    try await patchGenerator.generate(patchRequest)
                }
                try await persistence.saveCapture(
                    capture,
                    workspaceID: editingWorkspaceID,
                    requestID: request.id
                )
                return capture.isEmpty ? .noChanges : .changes(capture)
            },
            loadSubmission: { workspaceID in
                try persistence.submission(
                    EditingWorkspaceRecord.ID(rawValue: workspaceID.rawValue)
                )
            },
            prepareSource: { workspaceID in
                let editingWorkspaceID = EditingWorkspaceRecord.ID(
                    rawValue: workspaceID.rawValue
                )
                try await preparation.prepareSource(editingWorkspaceID)

                let (workspace, sourceBaseline) = try await database.read { db in
                    let workspace = try EditingWorkspaceRecord
                        .where { $0.id.eq(editingWorkspaceID) }
                        .fetchOne(db)
                    let sourceBaseline = try workspace?.sourceBaselineID.flatMap {
                        sourceBaselineID in
                        try SourceBaselineRecord
                            .where { $0.id.eq(sourceBaselineID) }
                            .fetchOne(db)
                    }
                    return (workspace, sourceBaseline)
                }
                guard let workspace else {
                    throw WorkspacePreparationError.workspaceNotFound(editingWorkspaceID)
                }
                guard let referenceDatabase = try workspaceReferenceDatabase.existing(
                    workspace,
                    sourceBaseline: sourceBaseline
                ) else {
                    throw OpenMusicEventWorkspaceIntegrationError.referenceNotPrepared
                }

                let source = try SourceWorkspaceDatabase(
                    workspaceID: editingWorkspaceID,
                    mainDatabase: database,
                    referenceDatabase: referenceDatabase
                )

                let branch: String
                let snapshotDate: Date
                switch workspace.kind {
                case .local:
                    branch = "local"
                    snapshotDate = workspace.updatedAt

                case .team:
                    guard let sourceBaseline else {
                        throw WorkspacePreparationError.workspaceMissingSourceBaseline(
                            editingWorkspaceID
                        )
                    }
                    let ref = sourceBaseline.ref?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if ref.isEmpty || ref == "HEAD" {
                        branch = "main"
                    } else if ref.hasPrefix("refs/heads/") {
                        branch = String(ref.dropFirst("refs/heads/".count))
                    } else {
                        branch = ref
                    }
                    snapshotDate = sourceBaseline.importedAt
                }

                let snapshotMilliseconds = Int64(
                    snapshotDate.timeIntervalSince1970 * 1_000
                )
                let line = try await persistence.establish(
                    .canonical(
                        WorkspaceBranchReference(
                            branch: WorkspaceBranch(rawValue: branch),
                            revision: WorkspaceRevision(
                                rawValue: "\(editingWorkspaceID.rawValue)@\(snapshotMilliseconds)"
                            )
                        )
                    ),
                    for: editingWorkspaceID
                )
                return WorkspacePreparation(
                    line: line,
                    source: source
                )
            },
            pushCommit: { workspaceID, submission in
                try await publisher.pushCommit(
                    workspaceID: EditingWorkspaceRecord.ID(rawValue: workspaceID.rawValue),
                    submission: submission,
                    persistence: persistence
                )
            },
            reconcileSource: { source, workspaceID, reconciliation in
                let editingWorkspaceID = EditingWorkspaceRecord.ID(
                    rawValue: workspaceID.rawValue
                )
                let line = try await referenceUpdate.reconcile(
                    source,
                    editingWorkspaceID,
                    reconciliation
                )
                try await persistence.advance(to: line, workspaceID: editingWorkspaceID)
                return line
            },
            recordProposal: { workspaceID, submission, commit in
                try await publisher.recordProposal(
                    workspaceID: EditingWorkspaceRecord.ID(rawValue: workspaceID.rawValue),
                    submission: submission,
                    commit: commit,
                    persistence: persistence
                )
            },
            removeSubmission: { workspaceID, submissionID in
                try await persistence.removeSubmission(
                    workspaceID: EditingWorkspaceRecord.ID(rawValue: workspaceID.rawValue),
                    submissionID: submissionID
                )
            },
            saveSubmission: { workspaceID, submission in
                try await persistence.save(
                    submission,
                    workspaceID: EditingWorkspaceRecord.ID(rawValue: workspaceID.rawValue)
                )
            }
        )
    }
}

private func workspacePatchRequest(
    _ workspaceID: EditingWorkspaceRecord.ID,
    database: any DatabaseReader
) async throws -> OpenMusicEventCalendarSourcePatchRequest {
    try await database.read { db in
        guard let workspace = try EditingWorkspaceRecord.find(workspaceID).fetchOne(db),
              let sourceBaselineID = workspace.sourceBaselineID
        else { throw WorkspacePreparationError.workspaceNotFound(workspaceID) }
        let organizerID = try workspace.publicRecord?.author
            ?? EventSourceProvenanceRecord
                .where { $0.sourceBaselineID.eq(sourceBaselineID) }
                .fetchOne(db)?
                .id
                .organizerID
        guard let organizerID else {
            throw OpenMusicEventWorkspaceIntegrationError.organizerNotFound(workspaceID)
        }
        return OpenMusicEventCalendarSourcePatchRequest(
            calendarID: OME.Calendar.ID(
                ownerID: organizerID,
                calendarID: OME.Calendar.defaultID
            ),
            sourceBaselineID: sourceBaselineID
        )
    }
}

private enum OpenMusicEventAuthoringIntegrationError: Error {
    case grantWorkspaceMismatch
}

private enum OpenMusicEventWorkspaceIntegrationError: Error {
    case organizerNotFound(EditingWorkspaceRecord.ID)
    case referenceNotPrepared
}
