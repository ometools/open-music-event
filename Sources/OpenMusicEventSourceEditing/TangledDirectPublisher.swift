import ATProto
import ComposableWorkspace
import Dependencies
import Foundation
import OpenMusicEventSourceClone
import TangledLexicon
import TangledXRPC

struct TangledDirectPublicationRequest: Equatable, Sendable {
    var target: TangledPatchOnlyProposalTarget
    var branch: WorkspaceBranch
    var title: String
    var body: String?
    var patch: TangledReplacementPatch
}

struct TangledDirectTransport: Sendable {
    var listRefs: @Sendable (TangledPatchOnlyProposalTarget) async throws -> TangledListRefsOutput
    var mergeCheck: @Sendable (
        TangledPatchOnlyProposalMergeCheckRequest
    ) async throws -> TangledMergeCheckOutput
    var merge: @Sendable (TangledDirectPublicationRequest, WorkspaceBranch) async throws -> Void

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
        merge: { request, branch in
            @Dependency(XRPC.Client.self) var xrpcClient
            _ = try await xrpcClient.tangledMerge(
                TangledMergeInput(
                    did: request.target.repositoryOwnerDID,
                    name: request.target.repositoryName,
                    patch: request.patch.patchText,
                    branch: branch.rawValue,
                    repo: request.target.repositoryDID,
                    authorName: "Open Music Event",
                    commitBody: request.body,
                    commitMessage: request.title
                ),
                knotHost: request.target.knotHost
            )
        }
    )
}

enum TangledDirectPublisherError: Equatable, Error, Sendable {
    case branchMissing(String)
    case mergeCheckRejected(String)
    case mergeDidNotAdvance(WorkspaceRevision)
}

struct TangledDirectPublisher: Sendable {
    var transport: TangledDirectTransport

    init(transport: TangledDirectTransport = .live) {
        self.transport = transport
    }

    func publish(
        _ request: TangledDirectPublicationRequest
    ) async throws -> WorkspaceBranchReference {
        try await requireExpectedHead(request)
        let mergeCheck = try await transport.mergeCheck(
            TangledPatchOnlyProposalMergeCheckRequest(
                target: request.target,
                patch: request.patch.patchText,
                branch: request.branch.rawValue
            )
        )
        if mergeCheck.isConflicted {
            throw WorkspacePublicationConflict(
                conflictingPaths: mergeCheckConflictPaths(mergeCheck)
            )
        }
        if let rejection = mergeCheckRejection(mergeCheck) {
            throw TangledDirectPublisherError.mergeCheckRejected(rejection)
        }
        try await requireExpectedHead(request)
        try await transport.merge(request, request.branch)
        let published = try branchReference(
            request.branch,
            in: try await transport.listRefs(request.target)
        )
        guard published.revision != request.patch.baseRevision else {
            throw TangledDirectPublisherError.mergeDidNotAdvance(published.revision)
        }
        return published
    }

    func requireExpectedHead(_ request: TangledDirectPublicationRequest) async throws {
        let observed = try branchReference(
            request.branch,
            in: try await transport.listRefs(request.target)
        )
        guard observed.revision == request.patch.baseRevision else {
            throw WorkspaceHeadMismatch(
                observedRevision: observed.revision
            )
        }
    }

    func branchReference(
        _ branch: WorkspaceBranch,
        in output: TangledListRefsOutput
    ) throws -> WorkspaceBranchReference {
        let canonical = "refs/heads/\(branch.rawValue)"
        guard let reference = output.refs.first(where: {
            $0.ref == canonical || $0.ref == branch.rawValue
        }) else {
            throw TangledDirectPublisherError.branchMissing(branch.rawValue)
        }
        return WorkspaceBranchReference(
            branch: branch,
            revision: WorkspaceRevision(rawValue: reference.sha)
        )
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
