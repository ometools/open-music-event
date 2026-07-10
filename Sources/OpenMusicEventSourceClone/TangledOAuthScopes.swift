import ATProto
import ATProtoOAuth
import Tagged

public enum Tangled {}

extension Tangled {
    public enum OAuth {
        public enum Scopes {
            public typealias MIMEType = ATProto.MIMEType
            public typealias NSID = ATProto.NSID
            public typealias Scope = ATProto.OAuth.Permission

            public enum Blob {
                public static let patchGzipMIMEType: MIMEType = "application/gzip"
                public static let legacyPatchTextMIMEType: MIMEType = "text/x-patch"

                public static let patchGzip = Scope("blob:\(patchGzipMIMEType)")
                public static let legacyPatchText = Scope("blob:\(legacyPatchTextMIMEType)")
            }

            public enum PublicKey {
                public static let collection: NSID = "sh.tangled.publicKey"

                public static let create = Scope("repo:\(collection)?action=create")
            }

            public enum Repository {
                public static let collection: NSID = "sh.tangled.repo"

                public static let createRecord = Scope("repo:\(collection)?action=create")
                public static let updateRecord = Scope("repo:\(collection)?action=update")
                public static let deleteRecord = Scope("repo:\(collection)?action=delete")
            }

            public enum Pull {
                public static let collection: NSID = "sh.tangled.repo.pull"

                public static let read = Scope("repo:\(collection)")
                public static let create = Scope("repo:\(collection)?action=create")
                public static let update = Scope("repo:\(collection)?action=update")
                public static let delete = Scope("repo:\(collection)?action=delete")
            }

            public enum PullStatus {
                public static let collection: NSID = "sh.tangled.repo.pull.status"

                public static let read = Scope("repo:\(collection)")
                public static let create = Scope("repo:\(collection)?action=create")
                public static let update = Scope("repo:\(collection)?action=update")
                public static let delete = Scope("repo:\(collection)?action=delete")
            }

            public enum RPC {
                public static let createRepositoryNSID: NSID = "sh.tangled.repo.create"
                public static let setContributorsNSID: NSID = "sh.tangled.repo.setContributors"
                public static let mergeNSID: NSID = "sh.tangled.repo.merge"
                public static let mergeCheckNSID: NSID = "sh.tangled.repo.mergeCheck"

                public static let createRepository = Scope("rpc:\(createRepositoryNSID)")
                public static let setContributors = Scope("rpc:\(setContributorsNSID)")
                public static let merge = Scope("rpc:\(mergeNSID)")
                public static let mergeCheck = Scope("rpc:\(mergeCheckNSID)")
            }

            public static var openMusicEventRegisteredTangledScopes: [Scope] {
                [
                    Blob.patchGzip,
                    Blob.legacyPatchText,
                    PublicKey.create,
                    PullStatus.create,
                    PullStatus.delete,
                    PullStatus.update,
                    Pull.create,
                    Pull.delete,
                    Pull.update,
                    Repository.createRecord,
                    Repository.deleteRecord,
                    Repository.updateRecord,
                    RPC.createRepository,
                    RPC.merge,
                    RPC.setContributors,
                ]
            }

            public static var openMusicEventRegisteredTangledScopeStrings: [String] {
                openMusicEventRegisteredTangledScopes.map(\.rawValue)
            }
        }
    }
}

public enum TangledOAuthRequirements {
    private typealias Scopes = Tangled.OAuth.Scopes

    public static let patchBlobPermission = Scopes.Blob.patchGzip
    public static let legacyPatchBlobPermission = Scopes.Blob.legacyPatchText
    public static let publicKeyCreatePermission = Scopes.PublicKey.create
    public static let repositoryRecordCreatePermission = Scopes.Repository.createRecord
    public static let repositoryRecordUpdatePermission = Scopes.Repository.updateRecord
    public static let repositoryRecordDeletePermission = Scopes.Repository.deleteRecord
    public static let pullPermission = Scopes.Pull.read
    public static let pullCreatePermission = Scopes.Pull.create
    public static let pullUpdatePermission = Scopes.Pull.update
    public static let pullDeletePermission = Scopes.Pull.delete
    public static let pullStatusPermission = Scopes.PullStatus.read
    public static let pullStatusCreatePermission = Scopes.PullStatus.create
    public static let pullStatusUpdatePermission = Scopes.PullStatus.update
    public static let pullStatusDeletePermission = Scopes.PullStatus.delete
    public static let repositoryCreatePermission = Scopes.RPC.createRepository
    public static let repositorySetContributorsPermission = Scopes.RPC.setContributors
    public static let pullMergePermission = Scopes.RPC.merge
    public static let pullMergeCheckPermission = Scopes.RPC.mergeCheck

    public static let publicKeyAuthRequirement = OAuth.AuthRequirement(
        permissions: [publicKeyCreatePermission]
    )

    public static let proposalAuthRequirement = OAuth.AuthRequirement(
        permissions: [
            publicKeyCreatePermission,
            patchBlobPermission,
            pullCreatePermission,
        ]
    )

    public static let pullDeleteAuthRequirement = OAuth.AuthRequirement(
        permissions: [
            pullDeletePermission
        ]
    )

    public static let pullMergeAuthRequirement = OAuth.AuthRequirement(
        permissions: [
            pullMergePermission
        ]
    )

    public static let repositoryCreateAuthRequirement = OAuth.AuthRequirement(
        permissions: [
            repositoryCreatePermission
        ]
    )

    public static let repositorySetContributorsAuthRequirement = OAuth.AuthRequirement(
        permissions: [
            repositorySetContributorsPermission
        ]
    )

    public static let repositoryManagementAuthRequirement = OAuth.AuthRequirement(
        permissions: [
            repositoryCreatePermission,
            repositorySetContributorsPermission,
            repositoryRecordCreatePermission,
            repositoryRecordUpdatePermission,
            repositoryRecordDeletePermission,
        ]
    )

    public static let pullRequestSurfaceAuthRequirement = OAuth.AuthRequirement(
        permissions: [
            patchBlobPermission,
            pullCreatePermission,
            pullUpdatePermission,
            pullDeletePermission,
            pullStatusCreatePermission,
            pullStatusUpdatePermission,
            pullStatusDeletePermission,
        ]
    )

    public static let pullStatusAuthRequirement = OAuth.AuthRequirement(
        permissions: [
            pullStatusCreatePermission
        ]
    )

    public static let legacyPatchBlobAuthRequirement = OAuth.AuthRequirement(
        permissions: [
            legacyPatchBlobPermission
        ]
    )
}
