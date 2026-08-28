import ATProto
import ATProtoOAuth
import ComposableWorkspace
import Dependencies
import Foundation
import OpenMusicEventSourceClone
import TangledLexicon
import TangledXRPC
import XRPCClient

struct TangledPatchOnlyProposalTarget: Equatable, Sendable {
    var repositoryDID: DID
    var repositoryOwnerDID: DID
    var repositoryName: String
    var knotHost: ATProto.PDSHost
}

struct TangledPatchOnlyProposalPublicationRequest: Equatable, Sendable {
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
                    branch: request.branch
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
    case defaultBranchAdvanced(expected: WorkspaceRevision, observed: WorkspaceRevision)
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
                branch: initialBranch.name
            )
        )
        if let rejection = mergeCheckRejection(mergeCheck) {
            throw TangledPatchOnlyProposalPublisherError.mergeCheckRejected(rejection)
        }

        let finalBranch = try await defaultBranch(
            for: request.target,
            expectedRevision: request.patch.baseRevision
        )
        guard finalBranch.name == initialBranch.name else {
            throw TangledPatchOnlyProposalPublisherError.defaultBranchChanged(
                expected: initialBranch.name,
                observed: finalBranch.name
            )
        }

        try await transport.authorize()
        let patchBlob = try await transport.uploadPatchBlob(request.patch.compressedBlob)
        let record = TangledPullRecord(
            target: TangledPullRecord.Target(
                repo: request.target.repositoryDID,
                branch: initialBranch.name
            ),
            title: request.title,
            body: request.body,
            rounds: [
                TangledPullRecord.Round(
                    patchBlob: patchBlob,
                    createdAt: request.createdAt
                )
            ],
            source: nil,
            createdAt: request.createdAt
        )
        let uri = try await transport.putRecord(
            TangledPatchOnlyProposalPutRecordRequest(
                authorRepository: request.authorRepository,
                recordKey: request.recordKey,
                record: record
            )
        )
        return WorkspaceProposalID(rawValue: uri.description)
    }
}

private extension TangledPatchOnlyProposalPublisher {
    struct DefaultBranch: Equatable, Sendable {
        var name: String
        var revision: WorkspaceRevision
    }

    func defaultBranch(
        for target: TangledPatchOnlyProposalTarget,
        expectedRevision: WorkspaceRevision
    ) async throws -> DefaultBranch {
        let output = try await transport.listRefs(target)
        guard let defaultBranch = output.defaultBranch else {
            throw TangledPatchOnlyProposalPublisherError.missingDefaultBranch
        }
        let name = try normalizedDefaultBranch(defaultBranch.ref)
        guard let rawHead = defaultBranch.head?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !rawHead.isEmpty else {
            throw TangledPatchOnlyProposalPublisherError.missingDefaultBranchHead(
                defaultBranch.ref
            )
        }
        let revision = WorkspaceRevision(rawValue: rawHead)
        guard revision == expectedRevision else {
            throw TangledPatchOnlyProposalPublisherError.defaultBranchAdvanced(
                expected: expectedRevision,
                observed: revision
            )
        }
        return DefaultBranch(name: name, revision: revision)
    }

    func normalizedDefaultBranch(_ ref: String) throws -> String {
        let ref = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = ref.hasPrefix("refs/heads/")
            ? String(ref.dropFirst("refs/heads/".count))
            : ref
        guard !name.isEmpty, name != "HEAD" else {
            throw TangledPatchOnlyProposalPublisherError.invalidDefaultBranchRef(ref)
        }
        return name
    }

    func mergeCheckRejection(_ output: TangledMergeCheckOutput) -> String? {
        if let error = output.error?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty {
            return error
        }
        guard output.isConflicted else { return nil }
        if let message = output.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }
        let conflicts = output.conflicts?.map {
            "\($0.filename): \($0.reason)"
        }
        .joined(separator: ", ") ?? ""
        return conflicts.isEmpty ? "Patch has conflicts." : conflicts
    }
}
