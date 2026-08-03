import ATProto
import Dependencies
import OpenMusicEventAuthentication
import OpenMusicEventLexicon
import OpenMusicEventSourceClone
import OpenMusicEventSourceEditing
import TangledLexicon
import TangledXRPC
import XRPCClient

/// The live network boundary that answers whether an actor can write to a Tangled repository.
/// No cloned source data or application database state participates in authoring admission.
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
            admission: { workspace in
                @Dependency(\.getOptionalDefaultSession) var getOptionalDefaultSession
                guard let session = getOptionalDefaultSession() else {
                    return .signInRequired
                }
                guard let actorID = DID(session.accountID.rawValue.description),
                      let repository = try? TangledRepositoryReference(
                          sourceReference: workspace.repository
                      )
                else {
                    return .denied
                }

                @Dependency(\.tangledRepositoryMembership) var membership
                guard try await membership.contains(
                    repository,
                    workspace.organizerID,
                    actorID
                ) else {
                    return .denied
                }

                let role: OME.WorkspaceRole = workspace.organizerID == actorID
                    ? .owner
                    : .collaborator([.propose])
                return .granted(
                    principal: AuthoringPrincipal(actorID: actorID),
                    role: role
                )
            },
            authorizeEntry: { _, _ in
                @Dependency(\.oauthAuthorizationBroker) var authorizationBroker
                try await authorizationBroker.authorize(
                    OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement
                )
            },
            requestSignIn: {
                @Dependency(\.oauthAuthorizationBroker) var authorizationBroker
                try await authorizationBroker.authorize(
                    OpenMusicEventOAuth.tangledPullRequestWorkflowAuthRequirement
                )
            }
        )
    }
}
