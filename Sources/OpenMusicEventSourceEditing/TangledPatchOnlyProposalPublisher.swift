import ATProto
import ATProtoOAuth
import ComposableWorkspace
import Dependencies
import Foundation
import OpenMusicEventSourceClone
import TangledLexicon
import TangledXRPC

public struct TangledDefaultBranchClient: Sendable {
    public var resolve: @Sendable (
        _ repository: TangledRepositoryReference
    ) async throws -> WorkspaceBranchReference

    public init(
        resolve: @escaping @Sendable (
            _ repository: TangledRepositoryReference
        ) async throws -> WorkspaceBranchReference
    ) {
        self.resolve = resolve
    }
}

public struct TangledBranchReferenceClient: Sendable {
    public var resolve: @Sendable (
        _ repository: TangledRepositoryReference,
        _ branch: WorkspaceBranch
    ) async throws -> WorkspaceBranchReference

    public init(
        resolve: @escaping @Sendable (
            _ repository: TangledRepositoryReference,
            _ branch: WorkspaceBranch
        ) async throws -> WorkspaceBranchReference
    ) {
        self.resolve = resolve
    }
}

extension TangledBranchReferenceClient: DependencyKey {
    public static var liveValue: Self {
        Self { repository, branch in
            let target = try await repository.resolvedTangledRepositoryTarget()
            @Dependency(XRPC.Client.self) var xrpcClient
            let output = try await xrpcClient.tangledListRefs(
                repo: target.repositoryDID,
                knotHost: target.knotHost
            )
            let canonical = "refs/heads/\(branch.rawValue)"
            guard let reference = output.refs.first(where: {
                $0.ref == canonical || $0.ref == branch.rawValue
            }) else {
                throw TangledBranchReferenceClientError.missingBranch(branch.rawValue)
            }
            return WorkspaceBranchReference(
                branch: branch,
                revision: WorkspaceRevision(rawValue: reference.sha)
            )
        }
    }

    public static var testValue: Self {
        Self { _, branch in
            throw TangledBranchReferenceClientError.missingBranch(branch.rawValue)
        }
    }
}

extension TangledDefaultBranchClient: DependencyKey {
    public static var liveValue: Self {
        Self { repository in
            let target = try await repository.resolvedTangledRepositoryTarget()
            @Dependency(XRPC.Client.self) var xrpcClient
            return try tangledDefaultBranch(
                try await xrpcClient.tangledListRefs(
                    repo: target.repositoryDID,
                    knotHost: target.knotHost
                )
            )
        }
    }

    public static var testValue: Self {
        Self { _ in
            throw TangledDefaultBranchClientError.unimplemented
        }
    }
}

public extension DependencyValues {
    var tangledDefaultBranch: TangledDefaultBranchClient {
        get { self[TangledDefaultBranchClient.self] }
        set { self[TangledDefaultBranchClient.self] = newValue }
    }

    var tangledBranchReference: TangledBranchReferenceClient {
        get { self[TangledBranchReferenceClient.self] }
        set { self[TangledBranchReferenceClient.self] = newValue }
    }
}

private enum TangledDefaultBranchClientError: Error {
    case unimplemented
}

private enum TangledBranchReferenceClientError: Error {
    case missingBranch(String)
}

struct TangledPatchOnlyProposalTarget: Codable, Equatable, Sendable {
    var repositoryDID: DID
    var repositoryOwnerDID: DID
    var repositoryName: String
    var knotHost: ATProto.PDSHost
}

struct TangledPatchOnlyProposalPublicationRequest: Codable, Equatable, Sendable {
    var authorRepository: DID
    var recordKey: ATProto.Record.Key
    var target: TangledPatchOnlyProposalTarget
    var title: String
    var body: String?
    var createdAt: TangledTimestamp
    var patch: TangledReplacementPatch
}

struct TangledPatchOnlyProposalMergeCheckRequest: Equatable, Sendable {
    var target: TangledPatchOnlyProposalTarget
    var patch: String
    var branch: String
}

struct TangledPatchOnlyProposalPutRecordRequest: Equatable, Sendable {
    var authorRepository: DID
    var recordKey: ATProto.Record.Key
    var record: TangledPullRecord
    var swapRecord: ATProto.CID?
}

struct TangledPatchOnlyProposalTransport: Sendable {
    var listRefs: @Sendable (
        _ target: TangledPatchOnlyProposalTarget
    ) async throws -> TangledListRefsOutput
    var mergeCheck: @Sendable (
        _ request: TangledPatchOnlyProposalMergeCheckRequest
    ) async throws -> TangledMergeCheckOutput
    var authorize: @Sendable () async throws -> Void
    var uploadPatchBlob: @Sendable (_ data: Data) async throws -> ATProto.Blob
    var putRecord: @Sendable (
        _ request: TangledPatchOnlyProposalPutRecordRequest
    ) async throws -> ATProto.URI
}

extension TangledPatchOnlyProposalTransport {
    static let live = Self(
        listRefs: { target in
            @Dependency(XRPC.Client.self) var xrpcClient
            return try await xrpcClient.tangledListRefs(
                repo: target.repositoryDID,
                knotHost: target.knotHost
            )
        },
        mergeCheck: { request in
            @Dependency(XRPC.Client.self) var xrpcClient
            return try await xrpcClient.tangledMergeCheck(
                TangledMergeCheckInput(
                    did: request.target.repositoryOwnerDID,
                    name: request.target.repositoryName,
                    patch: request.patch,
                    branch: request.branch,
                    repo: request.target.repositoryDID
                ),
                knotHost: request.target.knotHost
            )
        },
        authorize: {
            @Dependency(\.oauthAuthorizationBroker) var authorizationBroker
            try await authorizationBroker.authorize(
                TangledOAuthRequirements.proposalAuthRequirement
            )
        },
        uploadPatchBlob: { data in
            @Dependency(XRPC.Client.self) var xrpcClient
            return try await xrpcClient.tangledUploadPatchBlob(
                data,
                authorizationPolicy: .required(
                    TangledOAuthRequirements.proposalAuthRequirement
                )
            )
            .blob
        },
        putRecord: { request in
            @Dependency(XRPC.Client.self) var xrpcClient
            let output = try await xrpcClient.run(
                TangledRepositoryRequests.putRecord(
                    repo: request.authorRepository.description,
                    collection: .pull,
                    rkey: request.recordKey,
                    record: request.record,
                    swapRecord: request.swapRecord,
                    authorizationPolicy: .required(
                        TangledOAuthRequirements.proposalAuthRequirement
                    )
                )
            )
            return output.uri
        }
    )
}

enum TangledPatchOnlyProposalPublisherError: Equatable, Error, Sendable {
    case missingDefaultBranch
    case invalidDefaultBranchRef(String)
    case missingDefaultBranchHead(String)
    case defaultBranchChanged(expected: String, observed: String)
    case mergeCheckRejected(String)
}

struct TangledPatchOnlyProposalPublisher: Sendable {
    var transport: TangledPatchOnlyProposalTransport

    init(transport: TangledPatchOnlyProposalTransport = .live) {
        self.transport = transport
    }

    func publish(
        _ request: TangledPatchOnlyProposalPublicationRequest
    ) async throws -> WorkspaceProposalID {
        let initialBranch = try await defaultBranch(
            for: request.target,
            expectedRevision: request.patch.baseRevision
        )
        let mergeCheck = try await transport.mergeCheck(
            TangledPatchOnlyProposalMergeCheckRequest(
                target: request.target,
                patch: request.patch.patchText,
                branch: initialBranch.branch.rawValue
            )
        )
        if mergeCheck.isConflicted {
            throw WorkspacePublicationConflict(
                conflictingPaths: mergeCheckConflictPaths(mergeCheck)
            )
        }
        if let rejection = mergeCheckRejection(mergeCheck) {
            throw TangledPatchOnlyProposalPublisherError.mergeCheckRejected(rejection)
        }

        let finalBranch = try await defaultBranch(
            for: request.target,
            expectedRevision: request.patch.baseRevision
        )
        guard finalBranch.branch == initialBranch.branch else {
            throw TangledPatchOnlyProposalPublisherError.defaultBranchChanged(
                expected: initialBranch.branch.rawValue,
                observed: finalBranch.branch.rawValue
            )
        }

        try await transport.authorize()
        let patchBlob = try await transport.uploadPatchBlob(request.patch.compressedBlob)
        let publicationBranch = try await defaultBranch(
            for: request.target,
            expectedRevision: request.patch.baseRevision
        )
        guard publicationBranch.branch == initialBranch.branch else {
            throw TangledPatchOnlyProposalPublisherError.defaultBranchChanged(
                expected: initialBranch.branch.rawValue,
                observed: publicationBranch.branch.rawValue
            )
        }
        let round = TangledPullRecord.Round(
            patchBlob: patchBlob,
            createdAt: request.createdAt
        )
        var record = TangledPullRecord(
            target: TangledPullRecord.Target(
                repo: request.target.repositoryDID,
                branch: initialBranch.branch.rawValue
            ),
            title: request.title,
            body: request.body,
            rounds: [],
            source: nil,
            createdAt: request.createdAt
        )
        record.rounds.append(round)
        record.source = nil
        let uri = try await transport.putRecord(
            TangledPatchOnlyProposalPutRecordRequest(
                authorRepository: request.authorRepository,
                recordKey: request.recordKey,
                record: record,
                swapRecord: nil
            )
        )
        return WorkspaceProposalID(rawValue: uri.description)
    }
}

private extension TangledPatchOnlyProposalPublisher {
    func defaultBranch(
        for target: TangledPatchOnlyProposalTarget,
        expectedRevision: WorkspaceRevision
    ) async throws -> WorkspaceBranchReference {
        let branch = try tangledDefaultBranch(try await transport.listRefs(target))
        guard branch.revision == expectedRevision else {
            throw WorkspaceHeadMismatch(
                observedRevision: branch.revision
            )
        }
        return branch
    }

    func mergeCheckRejection(_ output: TangledMergeCheckOutput) -> String? {
        if let error = output.error?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty {
            return error
        }
        return nil
    }

    func mergeCheckConflictPaths(
        _ output: TangledMergeCheckOutput
    ) -> [WorkspaceConflictPath] {
        Array(
            Set(
                output.conflicts?.compactMap { conflict in
                    let path = conflict.filename.trimmingCharacters(in: .whitespacesAndNewlines)
                    return path.isEmpty ? nil : path
                } ?? []
            )
        )
        .sorted()
        .map(WorkspaceConflictPath.init(rawValue:))
    }
}

private func tangledDefaultBranch(
    _ output: TangledListRefsOutput
) throws -> WorkspaceBranchReference {
    guard let defaultBranch = output.defaultBranch else {
        throw TangledPatchOnlyProposalPublisherError.missingDefaultBranch
    }
    let rawRef = defaultBranch.ref.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = rawRef.hasPrefix("refs/heads/")
        ? String(rawRef.dropFirst("refs/heads/".count))
        : rawRef
    guard !name.isEmpty, name != "HEAD" else {
        throw TangledPatchOnlyProposalPublisherError.invalidDefaultBranchRef(rawRef)
    }
    guard let rawHead = defaultBranch.head?.trimmingCharacters(
        in: .whitespacesAndNewlines
    ), !rawHead.isEmpty else {
        throw TangledPatchOnlyProposalPublisherError.missingDefaultBranchHead(
            defaultBranch.ref
        )
    }
    return WorkspaceBranchReference(
        branch: WorkspaceBranch(rawValue: name),
        revision: WorkspaceRevision(rawValue: rawHead)
    )
}
