import ATProto
import Dependencies
import Foundation
import HTTPClient
import HTTPTypes
import OpenMusicEventLexicon

public struct OpenMusicEventWorkspaceProposalListRequest: Equatable, Sendable {
    public var source: ATProto.URI
    public var targetBranch: String

    public init(source: ATProto.URI, targetBranch: String) {
        self.source = source
        self.targetBranch = SourceWorkspace.normalizedBranch(targetBranch)
    }

    public init(workspace: SourceWorkspace) throws {
        guard let source = workspace.canonicalTangledSourceURI else {
            throw WorkspaceProposalClientError.invalidCanonicalSource(workspace.repository)
        }
        self.init(source: source, targetBranch: workspace.defaultBranch)
    }
}

public struct OpenMusicEventWorkspaceProposalMergeRequest: Equatable, Sendable {
    public var target: OpenMusicEventSourceTarget
    public var proposal: OME.WorkspaceProposal.Detail

    public init(
        target: OpenMusicEventSourceTarget,
        proposal: OME.WorkspaceProposal.Detail
    ) {
        self.target = target
        self.proposal = proposal
    }
}

public enum WorkspaceProposalClientError: Equatable, Error, Sendable {
    case invalidCanonicalSource(String)
    case invalidProposal(ATProto.URI)
    case proposalNotFound(ATProto.URI)
    case repeatedCursor(String)
}

public struct WorkspaceProposalClient: Sendable {
    public var list: nonisolated(nonsending) @Sendable (
        OpenMusicEventWorkspaceProposalListRequest
    ) async throws -> [OME.WorkspaceProposal.ListItem]
    public var detail: nonisolated(nonsending) @Sendable (
        ATProto.URI
    ) async throws -> OME.WorkspaceProposal.Detail
    public var close: nonisolated(nonsending) @Sendable (ATProto.URI) async throws -> Void
    public var merge: nonisolated(nonsending) @Sendable (
        OpenMusicEventWorkspaceProposalMergeRequest
    ) async throws -> Void

    public init(
        list: nonisolated(nonsending) @escaping @Sendable (
            OpenMusicEventWorkspaceProposalListRequest
        ) async throws -> [OME.WorkspaceProposal.ListItem],
        detail: nonisolated(nonsending) @escaping @Sendable (
            ATProto.URI
        ) async throws -> OME.WorkspaceProposal.Detail,
        close: nonisolated(nonsending) @escaping @Sendable (ATProto.URI) async throws -> Void = { _ in },
        merge: nonisolated(nonsending) @escaping @Sendable (
            OpenMusicEventWorkspaceProposalMergeRequest
        ) async throws -> Void = { _ in }
    ) {
        self.list = list
        self.detail = detail
        self.close = close
        self.merge = merge
    }
}

public extension WorkspaceProposalClient {
    static let noop = Self(
        list: { _ in [] },
        detail: { throw WorkspaceProposalClientError.proposalNotFound($0) }
    )

    static func openMusicEvent(appViewHost: ATProto.PDSHost) -> Self {
        let mutationClient = TangledPullReviewClient.openMusicEvent
        return Self(
            list: { request in
                @Dependency(XRPC.Client.self) var xrpcClient
                var proposals: [OME.WorkspaceProposal.ListItem] = []
                var cursor: String?
                var observedCursors: Set<String> = []

                while true {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let page = try await withDependencies {
                        $0.pdsHost = appViewHost
                        $0.jsonDecoder = decoder
                    } operation: {
                        try await xrpcClient.run(
                            OME.WorkspaceProposal.GetProposals(
                                source: request.source,
                                targetBranch: request.targetBranch,
                                includeRetained: false,
                                cursor: cursor,
                                limit: 100
                            )
                        )
                    }
                    proposals.append(contentsOf: page.proposals)
                    guard let nextCursor = page.cursor else { return proposals }
                    guard observedCursors.insert(nextCursor).inserted else {
                        throw WorkspaceProposalClientError.repeatedCursor(nextCursor)
                    }
                    cursor = nextCursor
                }
            },
            detail: { uri in
                @Dependency(XRPC.Client.self) var xrpcClient
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                do {
                    return try await withDependencies {
                        $0.pdsHost = appViewHost
                        $0.jsonDecoder = decoder
                        $0.expectedErrors.insert(
                            ExpectedHTTPError(status: .notFound, errorCode: "ProposalNotFound")
                        )
                    } operation: {
                        try await xrpcClient.run(OME.WorkspaceProposal.GetProposal(uri: uri))
                    }
                } catch let HTTPError.httpError(status, _, _) where status == .notFound {
                    throw WorkspaceProposalClientError.proposalNotFound(uri)
                }
            },
            close: { uri in
                try await mutationClient.close(TangledPullReview(proposalURI: uri))
            },
            merge: { request in
                try await mutationClient.merge(
                    OpenMusicEventTangledPullReviewMergeRequest(
                        target: request.target,
                        review: try TangledPullReview(proposal: request.proposal)
                    )
                )
            }
        )
    }
}

public extension DependencyValues {
    var workspaceProposalClient: WorkspaceProposalClient {
        get { self[WorkspaceProposalClientKey.self] }
        set { self[WorkspaceProposalClientKey.self] = newValue }
    }
}

private enum WorkspaceProposalClientKey: DependencyKey {
    static let liveValue = WorkspaceProposalClient.openMusicEvent(
        appViewHost: "openmusicevent.app"
    )
    static let testValue = WorkspaceProposalClient.noop
}

private extension TangledPullReview {
    init(proposalURI: ATProto.URI) {
        self.init(
            author: proposalURI.authorDescription,
            commentCount: 0,
            createdAt: "",
            patchBlobs: [],
            state: "",
            targetBranch: "",
            targetRepositoryDID: "",
            title: "",
            uri: proposalURI.description
        )
    }

    init(proposal: OME.WorkspaceProposal.Detail) throws {
        guard let title = proposal.title,
              let targetBranch = proposal.targetBranch,
              let targetRepositoryDID = proposal.targetRepositoryDID
        else {
            throw WorkspaceProposalClientError.invalidProposal(proposal.uri)
        }
        self.init(
            author: proposal.authorDID.description,
            body: proposal.body,
            commentCount: 0,
            createdAt: proposal.createdAt.map(Self.timestamp) ?? "",
            patchBlobs: [],
            sourceBranch: proposal.source?.branch,
            sourceRepositoryDID: proposal.source?.repositoryDID?.description,
            state: proposal.status.rawValue,
            stateUpdatedAt: proposal.updatedAt.map(Self.timestamp),
            targetBranch: targetBranch,
            targetRepositoryDID: targetRepositoryDID.description,
            title: title,
            uri: proposal.uri.description
        )
    }

    static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
