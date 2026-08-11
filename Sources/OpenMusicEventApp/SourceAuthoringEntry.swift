import ATProto
import ComposableAuthoring
import Dependencies
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
#if canImport(OSLog)
import OSLog
#endif
import SQLiteData
import TangledLexicon
import TangledXRPC
import XRPCClient

/// The live network boundary that answers whether an actor can write to a Tangled repository.
/// No cloned source data or application database state participates in authoring admission.
struct TangledRepositoryMembershipClient: Sendable {
    var role: @Sendable (
        _ repository: TangledRepositoryReference,
        _ actorID: DID
    ) async throws -> OME.WorkspaceRole?
}

extension TangledRepositoryMembershipClient: DependencyKey {
    static var liveValue: Self {
        Self { repository, actorID in
            let ownerID = try await repository.resolvedOwnerDID()
            if ownerID == actorID.description {
                return .owner
            }

            let target = try await repository.resolvedTangledRepositoryTarget()
            @Dependency(XRPC.Client.self) var xrpcClient
            guard try await xrpcClient.tangledContainsCollaborator(
                subject: target.repositoryDID,
                actorID: actorID,
                knotHost: target.knotHost
            ) else { return nil }
            return .collaborator([.propose, .merge])
        }
    }

    static var testValue: Self {
        Self { _, _ in nil }
    }
}

extension DependencyValues {
    var tangledRepositoryMembership: TangledRepositoryMembershipClient {
        get { self[TangledRepositoryMembershipClient.self] }
        set { self[TangledRepositoryMembershipClient.self] = newValue }
    }
}

extension AuthoringClient
where
    Context == SourceWorkspace,
    Eligibility == AuthoringEligibility,
    Grant == AuthoringGrant
{
    static var openMusicEvent: Self {
        @Dependency(WorkspaceAuthoringActivationClient.self) var activations

        return Self(
            admission: { workspace in
                guard let eligibility = try await authoringEligibility(for: workspace)
                else { return .unavailable }
                return .eligible(eligibility)
            },
            enter: { workspace, eligibility in
                guard try await authoringEligibility(for: workspace) == eligibility else {
                    throw OpenMusicEventAuthoringClientError.eligibilityChanged
                }
                @Dependency(\.oauthAuthorizationBroker) var authorizationBroker
                try await authorizationBroker.authorize(
                    OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement
                )

                try await activations.activate(
                    workspace.id,
                    eligibility.principal,
                    eligibility.role
                )
                return AuthoringGrant(
                    principal: eligibility.principal,
                    role: eligibility.role,
                    workspaceID: workspace.id
                )
            },
            exit: { workspace, grant in
                guard grant.workspaceID == workspace.id else {
                    throw OpenMusicEventAuthoringClientError.grantWorkspaceMismatch
                }
                try await restoreAttendeeInstallation(for: workspace)
            },
            restore: { workspace in
                guard let activation = try activations.current(workspace.id) else {
                    return nil
                }
                guard let eligibility = try await authoringEligibility(for: workspace),
                      eligibility.principal == activation.principal
                else {
                    try await activations.deactivate(workspace.id)
                    return nil
                }

                @Dependency(\.oauthAuthorizationBroker) var authorizationBroker
                try await authorizationBroker.authorize(
                    OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement
                )
                try await activations.activate(
                    workspace.id,
                    eligibility.principal,
                    eligibility.role
                )
                return AuthoringGrant(
                    principal: eligibility.principal,
                    role: eligibility.role,
                    workspaceID: workspace.id
                )
            }
        )
    }
}

private func authoringEligibility(
    for workspace: SourceWorkspace
) async throws -> AuthoringEligibility? {
    @Dependency(\.getOptionalDefaultSession) var getOptionalDefaultSession
    guard let session = getOptionalDefaultSession(),
          let actorID = DID(session.accountID.rawValue.description),
          let repository = try? TangledRepositoryReference(
              sourceReference: workspace.repository
          )
    else { return nil }

    @Dependency(\.tangledRepositoryMembership) var membership
    guard let role = try await membership.role(
        repository,
        actorID
    ) else { return nil }

    return AuthoringEligibility(
        principal: AuthoringPrincipal(actorID: actorID),
        role: role
    )
}

private func restoreAttendeeInstallation(for workspace: SourceWorkspace) async throws {
    AuthoringExitDiagnostics.notice("""
    Authoring exit canonical restoration started
    workspace: \(workspace.id.rawValue)
    repository: \(workspace.repository)
    ref: \(workspace.branch)
    """)
    do {
        try await performAttendeeInstallationRestoration(for: workspace)
        AuthoringExitDiagnostics.notice("""
        Authoring exit canonical restoration completed
        workspace: \(workspace.id.rawValue)
        """)
    } catch {
        AuthoringExitDiagnostics.failure("""
        Authoring exit canonical restoration failed
        workspace: \(workspace.id.rawValue)
        error: \(String(describing: error))
        """)
        throw error
    }
}

private func performAttendeeInstallationRestoration(
    for workspace: SourceWorkspace
) async throws {
    @Dependency(\.defaultDatabase) var database
    let installedEventIDs = try await database.read { db in
        try InstalledEventRecord.all
            .fetchAll(db)
            .filter { $0.workspace?.id == workspace.id }
            .map(\.id)
            .sorted { $0.eventID.rawValue < $1.eventID.rawValue }
    }
    guard !installedEventIDs.isEmpty else {
        throw OpenMusicEventAuthoringClientError.noInstalledEvents(workspace.id)
    }
    AuthoringExitDiagnostics.notice("""
    Authoring exit attendee installations resolved
    workspace: \(workspace.id.rawValue)
    eventCount: \(installedEventIDs.count)
    """)

    @Dependency(\.uuid) var uuid
    let outputURL = TangledSourceCloner.temporaryOutputURL(uuid: uuid())
    defer { try? FileManager.default.removeItem(at: outputURL) }

    let downloaded = try await OpenMusicEventSourceValidator(
        OpenMusicEventSourceValidationRequest(
            source: workspace.repository,
            organizerID: workspace.organizerID,
            ref: workspace.branch,
            outputURL: outputURL
        )
    )
    .validate()
    guard downloaded.organizerID == workspace.organizerID else {
        throw OpenMusicEventAuthoringClientError.canonicalSourceMismatch(workspace.id)
    }
    AuthoringExitDiagnostics.notice("""
    Authoring exit canonical source downloaded
    workspace: \(workspace.id.rawValue)
    """)

    var canonicalEvents: [OME.SourceDatabaseInsertion] = []
    canonicalEvents.reserveCapacity(installedEventIDs.count)
    for eventID in installedEventIDs {
        var insertion = try await OpenMusicEventSourceValidator(
            OpenMusicEventSourceValidationRequest(
                source: downloaded.repositoryURL.path(percentEncoded: false),
                organizerID: workspace.organizerID,
                ref: workspace.branch
            )
        )
        .validate(eventID: eventID)
        .insertion
        for index in insertion.eventSourceProvenances.indices {
            insertion.eventSourceProvenances[index].source = workspace.sourceProvenance
        }
        canonicalEvents.append(insertion)
    }
    AuthoringExitDiagnostics.notice("""
    Authoring exit canonical attendee events validated
    workspace: \(workspace.id.rawValue)
    eventCount: \(canonicalEvents.count)
    """)

    try await OME.SourceDatabaseInsertion.restoreCanonicalEvents(
        canonicalEvents,
        from: workspace,
        in: database
    )
}

private enum AuthoringExitDiagnostics {
    #if canImport(OSLog)
    static let logger = Logger(
        subsystem: "app.openmusicevent",
        category: "authoring"
    )
    #endif

    static func notice(_ message: String) {
        #if canImport(OSLog)
        logger.notice("\(message, privacy: .public)")
        #else
        print(message)
        #endif
    }

    static func failure(_ message: String) {
        #if canImport(OSLog)
        logger.error("\(message, privacy: .public)")
        #else
        print(message)
        #endif
    }
}

private enum OpenMusicEventAuthoringClientError: Error {
    case canonicalSourceMismatch(SourceWorkspace.ID)
    case eligibilityChanged
    case grantWorkspaceMismatch
    case noInstalledEvents(SourceWorkspace.ID)
}
