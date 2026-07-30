import ATProto
import Dependencies
import OpenMusicEventAuthentication
import OpenMusicEventLexicon
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import SQLiteData
import TangledLexicon
import TangledXRPC
import XRPCClient

struct TangledRepositoryMembershipClient: Sendable {
    var contains: @Sendable (
        _ repository: TangledRepositoryReference,
        _ expectedOwnerID: DID,
        _ actorID: DID
    ) async throws -> Bool
}

extension TangledRepositoryMembershipClient: DependencyKey {
    static var liveValue: Self {
        Self { repository, expectedOwnerID, actorID in
            let ownerID = try await repository.resolvedOwnerDID()
            guard ownerID == expectedOwnerID.description else {
                return false
            }
            if expectedOwnerID == actorID {
                return true
            }

            let target = try await repository.resolvedTangledRepositoryTarget()
            @Dependency(XRPC.Client.self) var xrpcClient
            return try await xrpcClient.tangledContainsCollaborator(
                subject: target.repositoryDID,
                actorID: actorID,
                knotHost: target.knotHost
            )
        }
    }

    static var testValue: Self {
        Self { _, _, _ in false }
    }
}

extension DependencyValues {
    var tangledRepositoryMembership: TangledRepositoryMembershipClient {
        get { self[TangledRepositoryMembershipClient.self] }
        set { self[TangledRepositoryMembershipClient.self] = newValue }
    }
}

extension OpenMusicEventSourceEditing.AuthoringPolicyClient {
    static var openMusicEvent: Self {
        Self(
            admission: { workspaceID in
                @Dependency(\.defaultDatabase) var database

                let workspace = try await database.read { db in
                    try EditingWorkspaceRecord
                        .where { $0.id.eq(workspaceID) }
                        .fetchOne(db)
                }
                guard let workspace else {
                    throw WorkspacePreparationError.workspaceNotFound(workspaceID)
                }

                switch workspace.kind {
                case .local:
                    return .granted(principal: .local, role: .owner)

                case .team:
                    guard let workspaceRecord = workspace.publicRecord else {
                        return .denied
                    }
                    @Dependency(\.getOptionalDefaultSession) var getOptionalDefaultSession
                    guard let session = getOptionalDefaultSession() else {
                        return .signInRequired
                    }
                    guard let actorID = DID(session.accountID.rawValue.description) else {
                        return .denied
                    }
                    guard let workspaceOwnerID = workspaceRecord.author else {
                        return .denied
                    }

                    guard let sourceBaselineID = workspace.sourceBaselineID else {
                        return .denied
                    }
                    let sourceBaseline = try await database.read { db in
                        try SourceBaselineRecord
                            .where { $0.id.eq(sourceBaselineID) }
                            .fetchOne(db)
                    }
                    guard let sourceBaseline,
                          sourceBaseline.sourceKind == .tangled
                    else {
                        return .denied
                    }
                    guard let repository = try? TangledRepositoryReference(
                        sourceReference: sourceBaseline.sourceReference
                    ) else {
                        return .denied
                    }
                    @Dependency(\.tangledRepositoryMembership) var membership
                    guard try await membership.contains(
                        repository,
                        workspaceOwnerID,
                        actorID
                    ) else {
                        return .denied
                    }

                    return .granted(
                        principal: .actor(actorID),
                        role: workspaceOwnerID == actorID
                            ? .owner
                            : .collaborator([.propose, .merge])
                    )
                }
            },
            requestSignIn: {
                @Dependency(\.oauthAuthorizationBroker) var authorizationBroker
                try await authorizationBroker.authorize(
                    OpenMusicEventOAuth.baseAuthRequirement
                )
            }
        )
    }
}
