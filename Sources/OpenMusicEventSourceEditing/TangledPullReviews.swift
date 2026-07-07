import ATProto
import ATProtoOAuth
import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSourceClone
import TangledLexicon
import TangledXRPC
import XRPCClient

public struct OpenMusicEventTangledPullReviewRequest: Equatable, Sendable {
    public var eventID: OME.Event.ID

    public init(eventID: OME.Event.ID) {
        self.eventID = eventID
    }
}

public struct TangledPullReview: Equatable, Identifiable, Sendable {
    public var id: String { uri }

    public var author: String
    public var body: String?
    public var commentCount: Int
    public var createdAt: String
    public var patchBlobs: [PatchBlob]
    public var sourceBranch: String?
    public var sourceRepositoryDID: String?
    public var state: String
    public var stateUpdatedAt: String?
    public var targetBranch: String
    public var targetRepositoryDID: String
    public var title: String
    public var uri: String

    public init(
        author: String,
        body: String? = nil,
        commentCount: Int,
        createdAt: String,
        patchBlobs: [PatchBlob],
        sourceBranch: String? = nil,
        sourceRepositoryDID: String? = nil,
        state: String,
        stateUpdatedAt: String? = nil,
        targetBranch: String,
        targetRepositoryDID: String,
        title: String,
        uri: String
    ) {
        self.author = author
        self.body = body
        self.commentCount = commentCount
        self.createdAt = createdAt
        self.patchBlobs = patchBlobs
        self.sourceBranch = sourceBranch
        self.sourceRepositoryDID = sourceRepositoryDID
        self.state = state
        self.stateUpdatedAt = stateUpdatedAt
        self.targetBranch = targetBranch
        self.targetRepositoryDID = targetRepositoryDID
        self.title = title
        self.uri = uri
    }

    init(item: TangledPullListItem) {
        self.init(
            author: item.uri.authorDescription,
            body: item.value.body,
            commentCount: item.commentCount,
            createdAt: item.value.createdAt,
            patchBlobs: item.value.rounds.enumerated().map { offset, round in
                PatchBlob(index: offset + 1, round: round)
            },
            sourceBranch: item.value.source?.branch,
            sourceRepositoryDID: item.value.source?.repo?.description,
            state: item.state.rawValue,
            stateUpdatedAt: item.stateUpdatedAt,
            targetBranch: item.value.target.branch,
            targetRepositoryDID: item.value.target.repo.description,
            title: item.value.title,
            uri: item.uri.description
        )
    }

    public var rawReviewText: String {
        var lines = [
            "uri: \(uri)",
            "author: \(author)",
            "state: \(state)",
            "createdAt: \(createdAt)",
            "target.repo: \(targetRepositoryDID)",
            "target.branch: \(targetBranch)",
        ]
        if let sourceBranch {
            lines.append("source.branch: \(sourceBranch)")
        }
        if let sourceRepositoryDID {
            lines.append("source.repo: \(sourceRepositoryDID)")
        }
        if let stateUpdatedAt {
            lines.append("stateUpdatedAt: \(stateUpdatedAt)")
        }
        lines.append("commentCount: \(commentCount)")
        lines.append("title: \(title)")
        if let body, !body.isEmpty {
            lines.append("body:")
            lines.append(body)
        }
        if patchBlobs.isEmpty {
            lines.append("patchBlobs: []")
        } else {
            lines.append("patchBlobs:")
            for patchBlob in patchBlobs {
                lines.append("  - round: \(patchBlob.index)")
                lines.append("    cid: \(patchBlob.cid)")
                lines.append("    mimeType: \(patchBlob.mimeType)")
                if let size = patchBlob.size {
                    lines.append("    size: \(size)")
                }
                lines.append("    createdAt: \(patchBlob.createdAt)")
            }
        }
        return lines.joined(separator: "\n")
    }

    public struct PatchBlob: Equatable, Identifiable, Sendable {
        public var id: String { "\(index):\(cid)" }

        public var cid: String
        public var createdAt: String
        public var index: Int
        public var mimeType: String
        public var size: Int?

        public init(
            cid: String,
            createdAt: String,
            index: Int,
            mimeType: String,
            size: Int? = nil
        ) {
            self.cid = cid
            self.createdAt = createdAt
            self.index = index
            self.mimeType = mimeType
            self.size = size
        }

        init(index: Int, round: TangledPullRecord.Round) {
            self.init(
                cid: round.patchBlob.ref.rawValue,
                createdAt: round.createdAt,
                index: index,
                mimeType: round.patchBlob.mimeType.rawValue,
                size: round.patchBlob.size
            )
        }
    }
}

public enum TangledPullReviewClientError: Equatable, Error, Sendable {
    case invalidRepositoryDID(String)
    case invalidReviewURI(String)
    case missingRemote
    case unsupportedRemoteKind(String)
    case unsupportedReviewURICollection(String)
}

public struct TangledPullReviewClient: Sendable {
    public var list: @Sendable (
        OpenMusicEventTangledPullReviewRequest
    ) async throws -> [TangledPullReview]
    public var close: @Sendable (TangledPullReview) async throws -> Void
    public var delete: @Sendable (TangledPullReview) async throws -> Void

    public init(
        list: @escaping @Sendable (
            OpenMusicEventTangledPullReviewRequest
        ) async throws -> [TangledPullReview],
        close: @escaping @Sendable (TangledPullReview) async throws -> Void = { _ in },
        delete: @escaping @Sendable (TangledPullReview) async throws -> Void = { _ in }
    ) {
        self.list = list
        self.close = close
        self.delete = delete
    }
}

public extension TangledPullReviewClient {
    static let noop = Self(list: { _ in [] })

    static var openMusicEvent: Self {
        Self(
            list: { request in
                @Dependency(\.openMusicEventSourcePatchLocationResolver) var locationResolver
                @Dependency(XRPC.Client.self) var xrpcClient

                let location = try await locationResolver.resolve(
                    OpenMusicEventSourcePatchRequest(eventID: request.eventID)
                )
                guard let remote = location.remote else {
                    throw TangledPullReviewClientError.missingRemote
                }
                guard remote.kind == "tangled" else {
                    throw TangledPullReviewClientError.unsupportedRemoteKind(remote.kind)
                }

                let repository = try TangledRepositoryReference(parsing: remote.reference)
                let targetRepository = try await TangledSourcePatchPublisher()
                    .targetRepository(repository)
                guard let subject = DID(targetRepository.repoDID) else {
                    throw TangledPullReviewClientError.invalidRepositoryDID(
                        targetRepository.repoDID
                    )
                }

                let output = try await xrpcClient.tangledListPulls(
                    subject: subject,
                    status: .open,
                    limit: 50,
                    order: .descending
                )
                return output.items.map(TangledPullReview.init(item:))
            },
            close: { review in
                @Dependency(\.date.now) var now
                @Dependency(\.getDefaultSession) var getDefaultSession
                @Dependency(XRPC.Client.self) var xrpcClient

                guard let pullURI = ATProto.URI(review.uri) else {
                    throw TangledPullReviewClientError.invalidReviewURI(review.uri)
                }
                guard pullURI.collection == TangledNSID.pull, pullURI.rkey != nil else {
                    throw TangledPullReviewClientError.unsupportedReviewURICollection(
                        review.uri
                    )
                }

                let record = TangledPullStatusRecord(
                    pull: pullURI,
                    status: .closed,
                    createdAt: tangledPullReviewTimestamp(now)
                )
                _ = try await xrpcClient.run(
                    TangledRepositoryRequests.createRecord(
                        repo: getDefaultSession().accountID.rawValue.description,
                        collection: .pullStatus,
                        record: record,
                        authorizationPolicy: .required(
                            TangledOAuthRequirements.pullStatusAuthRequirement
                        )
                    )
                )
            },
            delete: { review in
                @Dependency(XRPC.Client.self) var xrpcClient

                guard let pullURI = ATProto.URI(review.uri) else {
                    throw TangledPullReviewClientError.invalidReviewURI(review.uri)
                }
                guard pullURI.collection == TangledNSID.pull, let rkey = pullURI.rkey else {
                    throw TangledPullReviewClientError.unsupportedReviewURICollection(
                        review.uri
                    )
                }

                _ = try await xrpcClient.run(
                    TangledRepositoryRequests.deleteRecord(
                        repo: pullURI.authorDescription,
                        collection: .pull,
                        rkey: rkey,
                        authorizationPolicy: .required(
                            TangledOAuthRequirements.pullDeleteAuthRequirement
                        )
                    )
                )
            }
        )
    }
}

public extension DependencyValues {
    var tangledPullReviewClient: TangledPullReviewClient {
        get { self[TangledPullReviewClientKey.self] }
        set { self[TangledPullReviewClientKey.self] = newValue }
    }
}

private enum TangledPullReviewClientKey: DependencyKey {
    static var liveValue: TangledPullReviewClient {
        .openMusicEvent
    }

    static var testValue: TangledPullReviewClient {
        .noop
    }
}

private extension ATProto.URI {
    var authorDescription: String {
        switch authority {
        case let .did(did):
            did.description
        case let .handle(handle):
            handle.rawValue
        }
    }
}

private func tangledPullReviewTimestamp(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}
