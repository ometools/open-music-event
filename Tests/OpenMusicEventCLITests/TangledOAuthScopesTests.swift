import ATProto
import ATProtoOAuth
import CustomDump
import Foundation
import OpenMusicEventSourceClone
import Testing

struct TangledOAuthScopesTests {
    @Test
    func hostedScopeStringsCoverTangledWorkspaceManagement() {
        expectNoDifference(
            Tangled.OAuth.Scopes.openMusicEventRegisteredTangledScopeStrings,
            [
                "blob:application/gzip",
                "blob:text/x-patch",
                "repo:sh.tangled.publicKey?action=create",
                "repo:sh.tangled.repo.pull.status?action=create",
                "repo:sh.tangled.repo.pull.status?action=delete",
                "repo:sh.tangled.repo.pull.status?action=update",
                "repo:sh.tangled.repo.pull?action=create",
                "repo:sh.tangled.repo.pull?action=delete",
                "repo:sh.tangled.repo.pull?action=update",
                "repo:sh.tangled.repo?action=create",
                "repo:sh.tangled.repo?action=delete",
                "repo:sh.tangled.repo?action=update",
                "rpc:sh.tangled.repo.create?aud=*",
                "rpc:sh.tangled.repo.merge?aud=*",
                "rpc:sh.tangled.repo.setContributors",
            ]
        )
    }

    @Test
    func scopesAreTypedOAuthPermissions() {
        typealias Scopes = Tangled.OAuth.Scopes

        let patchGzipMIMEType: ATProto.MIMEType = Scopes.Blob.patchGzipMIMEType
        let publicKeyCollection: ATProto.NSID = Scopes.PublicKey.collection
        let repositoryCollection: ATProto.NSID = Scopes.Repository.collection
        let pullCollection: ATProto.NSID = Scopes.Pull.collection
        let pullStatusCollection: ATProto.NSID = Scopes.PullStatus.collection
        let createRepositoryNSID: ATProto.NSID = Scopes.RPC.createRepositoryNSID
        let setContributorsNSID: ATProto.NSID = Scopes.RPC.setContributorsNSID
        let mergeNSID: ATProto.NSID = Scopes.RPC.mergeNSID

        expectNoDifference(patchGzipMIMEType.rawValue, "application/gzip")
        expectNoDifference(publicKeyCollection.rawValue, "sh.tangled.publicKey")
        expectNoDifference(repositoryCollection.rawValue, "sh.tangled.repo")
        expectNoDifference(pullCollection.rawValue, "sh.tangled.repo.pull")
        expectNoDifference(pullStatusCollection.rawValue, "sh.tangled.repo.pull.status")
        expectNoDifference(createRepositoryNSID.rawValue, "sh.tangled.repo.create")
        expectNoDifference(setContributorsNSID.rawValue, "sh.tangled.repo.setContributors")
        expectNoDifference(mergeNSID.rawValue, "sh.tangled.repo.merge")

        expectNoDifference(
            Scopes.PublicKey.create,
            ATProto.OAuth.Permission.repo(publicKeyCollection, actions: [.create])
        )
        expectNoDifference(
            Scopes.Pull.create,
            ATProto.OAuth.Permission.repo(pullCollection, actions: [.create])
        )
        expectNoDifference(
            Scopes.PullStatus.create,
            ATProto.OAuth.Permission.repo(pullStatusCollection, actions: [.create])
        )
        expectNoDifference(
            Scopes.Repository.createRecord,
            ATProto.OAuth.Permission.repo(repositoryCollection, actions: [.create])
        )
        expectNoDifference(
            Scopes.RPC.createRepository,
            ATProto.OAuth.Permission.rpc(createRepositoryNSID, audience: "*")
        )
        expectNoDifference(
            Scopes.RPC.setContributors,
            ATProto.OAuth.Permission.rpc(setContributorsNSID)
        )
        expectNoDifference(
            Scopes.RPC.merge,
            ATProto.OAuth.Permission.rpc(mergeNSID, audience: "*")
        )
    }

    @Test
    func oauthRequirementsUseHostedScopeStrings() {
        typealias Scopes = Tangled.OAuth.Scopes

        expectNoDifference(TangledOAuthRequirements.patchBlobPermission, Scopes.Blob.patchGzip)
        expectNoDifference(TangledOAuthRequirements.pullCreatePermission, Scopes.Pull.create)
        expectNoDifference(
            TangledOAuthRequirements.pullStatusCreatePermission,
            Scopes.PullStatus.create
        )
        expectNoDifference(
            TangledOAuthRequirements.repositoryCreatePermission,
            Scopes.RPC.createRepository
        )
        expectNoDifference(
            TangledOAuthRequirements.repositorySetContributorsPermission,
            Scopes.RPC.setContributors
        )
        expectNoDifference(TangledOAuthRequirements.pullMergePermission, Scopes.RPC.merge)
    }

    @Test
    func pullRequestWorkflowAuthorizationCoversTheFullLifecycle() {
        expectNoDifference(
            TangledOAuthRequirements.pullRequestWorkflowAuthRequirement.permissions,
            TangledOAuthRequirements.proposalAuthRequirement.permissions
                .union(TangledOAuthRequirements.pullRequestSurfaceAuthRequirement.permissions)
                .union(TangledOAuthRequirements.pullMergeAuthRequirement.permissions)
        )
    }

    @Test
    func proposalTokenMustUpgradeBeforeThePullRequestWorkflowCanMergeThroughAKnot() {
        let manifest = OAuth.AppManifest(
            appID: OAuth.App.ID(
                URL(string: "https://openmusicevent.app/oauth-client-metadata.json")!
            ),
            redirectURIs: [
                OAuth.App.RedirectURI(URL(string: "app.openmusicevent:/oauth/callback")!)
            ],
            registeredRequirements: [
                TangledOAuthRequirements.pullRequestWorkflowAuthRequirement
            ]
        )
        let proposalSession = tangledScopeTestSession(
            permissions: TangledOAuthRequirements.proposalAuthRequirement.permissions
        )
        let missingWorkflowPermissions: Set<OAuth.Permission> = [
            TangledOAuthRequirements.pullUpdatePermission,
            TangledOAuthRequirements.pullDeletePermission,
            TangledOAuthRequirements.pullStatusCreatePermission,
            TangledOAuthRequirements.pullStatusUpdatePermission,
            TangledOAuthRequirements.pullStatusDeletePermission,
            TangledOAuthRequirements.pullMergePermission,
        ]

        // A token that can create a proposal is not authorized to hit the knot merge
        // endpoint or to write the merged pull-status record.
        expectNoDifference(
            proposalSession.grantedPermissions.missing(
                TangledOAuthRequirements.pullRequestWorkflowAuthRequirement.permissions
            ),
            missingWorkflowPermissions
        )
        expectNoDifference(
            OAuth.authorizationStatus(
                for: TangledOAuthRequirements.pullRequestWorkflowAuthRequirement,
                session: proposalSession,
                manifest: manifest
            ),
            .upgradeAvailable(
                missing: missingWorkflowPermissions,
                requirement: TangledOAuthRequirements.pullRequestWorkflowAuthRequirement
            )
        )

        // Once the workflow permission set is granted, the same request is satisfied.
        let workflowSession = tangledScopeTestSession(
            permissions: TangledOAuthRequirements.pullRequestWorkflowAuthRequirement.permissions
        )
        expectNoDifference(
            OAuth.authorizationStatus(
                for: TangledOAuthRequirements.pullRequestWorkflowAuthRequirement,
                session: workflowSession,
                manifest: manifest
            ),
            .satisfied(workflowSession)
        )
    }
}

private func tangledScopeTestSession(
    permissions: Set<OAuth.Permission>
) -> OAuth.Session {
    var session = OAuth.Session.placeholder
    var grantedPermissions = Set([OAuth.Permission.atproto])
    grantedPermissions.formUnion(permissions)
    session.scope = OAuth.Scope(
        rawValue: grantedPermissions
            .map(\.rawValue)
            .sorted()
            .joined(separator: " ")
    )
    return session
}
