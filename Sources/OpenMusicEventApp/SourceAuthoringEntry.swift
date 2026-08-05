import ATProto
import ComposableAuthoring
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
            return .collaborator([.propose])
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
                try await activations.deactivate(workspace.id)
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

private enum OpenMusicEventAuthoringClientError: Error {
    case eligibilityChanged
    case grantWorkspaceMismatch
}
