import ATProto
import ATProtoOAuth
import ComposableAtmosphereConstellation
import Dependencies
import Foundation
import Gzip
import HTTPClient
import Lexicon
import OpenMusicEventLexicon
import OpenMusicEventSourceClone
import TangledLexicon
import TangledXRPC
import XRPCClient

public struct OpenMusicEventTangledPullReviewRequest: Equatable, Sendable {
    public var target: OpenMusicEventSourceTarget

    public init(eventID: OME.Event.ID) {
        self.init(target: .event(eventID))
    }

    public init(target: OpenMusicEventSourceTarget) {
        self.target = target
    }
}

public struct OpenMusicEventTangledPullReviewMergeRequest: Equatable, Sendable {
    public var target: OpenMusicEventSourceTarget
    public var review: TangledPullReview

    public init(eventID: OME.Event.ID, review: TangledPullReview) {
        self.init(target: .event(eventID), review: review)
    }

    public init(target: OpenMusicEventSourceTarget, review: TangledPullReview) {
        self.target = target
        self.review = review
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
    case invalidBlobURL(String)
    case invalidPatchBlob(String)
    case invalidRepositoryDID(String)
    case invalidReviewAuthor(String)
    case invalidReviewURI(String)
    case missingPatchBlob(String)
    case missingPullAuthorPDS(String)
    case missingRemote
    case repositoryRecordMissingName(String)
    case repositoryRecordNotFound(owner: String, repository: String)
    case targetRepositoryMismatch(expected: String, actual: String)
    case unsupportedRemoteKind(String)
    case unsupportedReviewURICollection(String)
}

public struct TangledPullReviewClient: Sendable {
    public var list: @Sendable (
        OpenMusicEventTangledPullReviewRequest
    ) async throws -> [TangledPullReview]
    public var close: @Sendable (TangledPullReview) async throws -> Void
    public var delete: @Sendable (TangledPullReview) async throws -> Void
    public var merge: @Sendable (
        OpenMusicEventTangledPullReviewMergeRequest
    ) async throws -> Void

    public init(
        list: @escaping @Sendable (
            OpenMusicEventTangledPullReviewRequest
        ) async throws -> [TangledPullReview],
        close: @escaping @Sendable (TangledPullReview) async throws -> Void = { _ in },
        merge: @escaping @Sendable (
            OpenMusicEventTangledPullReviewMergeRequest
        ) async throws -> Void = { _ in },
        delete: @escaping @Sendable (TangledPullReview) async throws -> Void = { _ in }
    ) {
        self.list = list
        self.close = close
        self.merge = merge
        self.delete = delete
    }
}

public enum TangledPullReviewListSource: Equatable, Sendable {
    case tangledXRPC
    case tangledXRPCWithConstellationBackfill
    case constellationBackfill
}

public extension TangledPullReviewClient {
    static let noop = Self(list: { _ in [] })

    static var openMusicEvent: Self {
        Self(
            list: { request in
                @Dependency(\.openMusicEventCalendarSourcePatchLocationResolver)
                var calendarSourcePatchLocationResolver
                @Dependency(\.openMusicEventSourcePatchLocationResolver) var locationResolver
                @Dependency(\.tangledPullReviewListSource) var listSource
                @Dependency(XRPC.Client.self) var xrpcClient

                let location = try await request.target.resolveLocation(
                    calendarSourcePatchLocationResolver: calendarSourcePatchLocationResolver,
                    sourcePatchLocationResolver: locationResolver
                )
                guard let remote = location.remote else {
                    throw TangledPullReviewClientError.missingRemote
                }
                guard remote.kind == "tangled" else {
                    throw TangledPullReviewClientError.unsupportedRemoteKind(remote.kind)
                }

                let repository = try TangledRepositoryReference(sourceReference: remote.reference)
                let targetRepository = try await TangledSourcePatchPublisher()
                    .targetRepository(repository)
                guard let subject = DID(targetRepository.repoDID) else {
                    throw TangledPullReviewClientError.invalidRepositoryDID(
                        targetRepository.repoDID
                    )
                }

                switch listSource {
                case .tangledXRPC:
                    return try await xrpcClient.tangledPullReviewsFromXRPC(subject: subject)

                case .tangledXRPCWithConstellationBackfill:
                    let xrpcReviews = try await xrpcClient
                        .tangledPullReviewsFromXRPC(subject: subject)
                    let constellationReviews: [TangledPullReview]
                    do {
                        constellationReviews = try await xrpcClient
                            .tangledPullReviewsFromConstellation(subject: subject)
                    } catch {
                        return xrpcReviews
                    }
                    return mergedTangledPullReviews(
                        primary: xrpcReviews,
                        fallback: constellationReviews
                    )

                case .constellationBackfill:
                    return try await xrpcClient
                        .tangledPullReviewsFromConstellation(subject: subject)
                }
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
            merge: { request in
                @Dependency(\.date.now) var now
                @Dependency(\.getDefaultSession) var getDefaultSession
                @Dependency(XRPC.Client.self) var xrpcClient

                let pullURI = try requireTangledPullURI(request.review.uri)
                let pullAuthorDID = try requireDIDAuthority(pullURI)
                let pullRecord = try await xrpcClient.tangledPullRecord(pullURI)
                let mergeRepository = try await TangledPullReviewMergeRepository
                    .resolve(target: request.target)
                guard mergeRepository.repoDID == pullRecord.value.target.repo else {
                    throw TangledPullReviewClientError.targetRepositoryMismatch(
                        expected: mergeRepository.repoDID.description,
                        actual: pullRecord.value.target.repo.description
                    )
                }

                let patch = try await patchTextForLatestRound(
                    in: pullRecord.value,
                    authorDID: pullAuthorDID
                )
                _ = try await xrpcClient.tangledMerge(
                    TangledMergeInput(
                        did: mergeRepository.ownerDID,
                        name: mergeRepository.name,
                        patch: patch,
                        branch: pullRecord.value.target.branch,
                        authorName: request.review.author,
                        commitBody: pullRecord.value.body,
                        commitMessage: pullRecord.value.title
                    ),
                    knotHost: mergeRepository.knotHost
                )

                let record = TangledPullStatusRecord(
                    pull: pullURI,
                    status: .merged,
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

                let pullURI = try requireTangledPullURI(review.uri)
                guard let rkey = pullURI.rkey else { fatalError("validated above") }

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

    var tangledPullReviewListSource: TangledPullReviewListSource {
        get { self[TangledPullReviewListSourceKey.self] }
        set { self[TangledPullReviewListSourceKey.self] = newValue }
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

private enum TangledPullReviewListSourceKey: DependencyKey {
    static let liveValue = TangledPullReviewListSource.tangledXRPC
    static let testValue = TangledPullReviewListSource.tangledXRPC
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

private extension XRPC.Client {
    func tangledPullRecord(
        _ pullURI: ATProto.URI
    ) async throws -> ATProto.Repository.ListedRecord<TangledPullRecord> {
        guard let rkey = pullURI.rkey else {
            throw TangledPullReviewClientError.unsupportedReviewURICollection(
                pullURI.description
            )
        }
        let authorDID = try requireDIDAuthority(pullURI)
        let pdsHost = try await pdsHost(for: authorDID)
        return try await run(
            TangledRepositoryRequests.getRecord(
                TangledPullRecord.self,
                repo: authorDID.description,
                collection: .pull,
                rkey: rkey,
                pdsHost: pdsHost
            )
        )
    }

    func tangledPullReviewsFromXRPC(
        subject: DID
    ) async throws -> [TangledPullReview] {
        let output = try await tangledListPulls(
            subject: subject,
            status: .open,
            limit: 50,
            order: .descending
        )
        return output.items.map(TangledPullReview.init(item:))
    }

    func tangledPullReviewsFromConstellation(
        subject: DID
    ) async throws -> [TangledPullReview] {
        let output = try await constellationGetBacklinkedRecords(
            TangledPullRecord.self,
            subject: subject,
            source: Constellation.BacklinkSource(
                collection: TangledNSID.pull,
                path: "target.repo"
            ),
            collection: TangledNSID.pull,
            limit: 100
        )

        var reviews: [TangledPullReview] = []
        reviews.reserveCapacity(output.records.count)

        for record in output.records where record.value.target.repo == subject {
            let status = try await latestTangledPullStatusFromConstellation(
                pullURI: record.uri
            )
            guard status.state == .open else { continue }

            reviews.append(
                TangledPullReview(
                    item: TangledPullListItem(
                        uri: record.uri,
                        cid: record.cid,
                        value: record.value,
                        state: status.state,
                        stateUpdatedAt: status.updatedAt,
                        commentCount: 0
                    )
                )
            )
        }

        return reviews
    }

    func latestTangledPullStatusFromConstellation(
        pullURI: ATProto.URI
    ) async throws -> (state: Open<TangledPullState>, updatedAt: TangledTimestamp?) {
        let output = try await constellationGetBacklinkedRecords(
            TangledPullStatusRecord.self,
            subject: pullURI,
            source: Constellation.BacklinkSource(
                collection: TangledNSID.pullStatus,
                path: "pull"
            ),
            collection: TangledNSID.pullStatus,
            limit: 25
        )
        let latestStatus = output.records
            .filter { $0.value.pull == pullURI }
            .max { $0.backlink.rkey.rawValue < $1.backlink.rkey.rawValue }

        guard let latestStatus else {
            return (.open, nil)
        }
        return (
            tangledPullState(from: latestStatus.value.status),
            latestStatus.value.createdAt
        )
    }
}

private struct TangledPullReviewMergeRepository: Sendable {
    var knotHost: ATProto.PDSHost
    var name: String
    var ownerDID: DID
    var repoDID: DID

    static func resolve(target: OpenMusicEventSourceTarget) async throws -> Self {
        @Dependency(\.openMusicEventCalendarSourcePatchLocationResolver)
        var calendarLocationResolver
        @Dependency(\.openMusicEventSourcePatchLocationResolver) var locationResolver
        @Dependency(XRPC.Client.self) var xrpcClient

        let location = try await target.resolveLocation(
            calendarSourcePatchLocationResolver: calendarLocationResolver,
            sourcePatchLocationResolver: locationResolver
        )
        guard let remote = location.remote else {
            throw TangledPullReviewClientError.missingRemote
        }
        guard remote.kind == "tangled" else {
            throw TangledPullReviewClientError.unsupportedRemoteKind(remote.kind)
        }

        let repository = try TangledRepositoryReference(sourceReference: remote.reference)
        let owner = try await TangledPullReviewRepositoryOwner.resolve(repository)
        var cursor: String?

        repeat {
            let output = try await xrpcClient.run(
                TangledRepositoryRequests.listRecords(
                    TangledRepoRecord.self,
                    repo: owner.did.description,
                    collection: .repo,
                    cursor: cursor,
                    pdsHost: owner.pdsHost
                )
            )

            if let record = output.records.first(where: { record in
                record.value.name == repository.repository
                    || record.uri.rkey?.rawValue == repository.repository
            }) {
                guard let repoDID = record.value.repoDid else {
                    throw TangledPullReviewClientError.invalidRepositoryDID(
                        record.uri.description
                    )
                }
                guard let name = record.value.name ?? record.uri.rkey?.rawValue else {
                    throw TangledPullReviewClientError.repositoryRecordMissingName(
                        record.uri.description
                    )
                }
                return Self(
                    knotHost: ATProto.PDSHost(record.value.knot),
                    name: name,
                    ownerDID: owner.did,
                    repoDID: repoDID
                )
            }

            cursor = output.cursor
        } while cursor != nil

        throw TangledPullReviewClientError.repositoryRecordNotFound(
            owner: owner.did.description,
            repository: repository.repository
        )
    }
}

private struct TangledPullReviewRepositoryOwner: Sendable {
    var did: DID
    var pdsHost: ATProto.PDSHost

    static func resolve(
        _ repository: TangledRepositoryReference
    ) async throws -> Self {
        let owner = repository.owner.hasPrefix("@")
            ? String(repository.owner.dropFirst())
            : repository.owner

        @Dependency(Atmosphere.Account.Client.self) var accountClient
        let account: Atmosphere.Account
        let document: DID.Document

        if let did = DID(owner) {
            (account, document) = try await accountClient.resolveDID(did)
        } else {
            (account, document) = try await accountClient.resolveHandle(
                Atmosphere.Account.Handle(owner)
            )
        }

        guard let pdsHost = document.pdsHost else {
            throw TangledPullReviewClientError.missingPullAuthorPDS(
                account.id.rawValue.description
            )
        }

        return Self(did: account.id.rawValue, pdsHost: pdsHost)
    }
}

private func patchTextForLatestRound(
    in pull: TangledPullRecord,
    authorDID: DID
) async throws -> String {
    guard let round = pull.rounds.max(by: { $0.createdAt < $1.createdAt }) else {
        throw TangledPullReviewClientError.missingPatchBlob(pull.title)
    }
    let pdsHost = try await pdsHost(for: authorDID)
    let patchBlob = try await patchBlobData(
        did: authorDID,
        cid: round.patchBlob.ref,
        pdsHost: pdsHost
    )
    let patchData = patchBlob.isGzipped ? try patchBlob.gunzipped() : patchBlob
    guard let patch = String(data: patchData, encoding: .utf8) else {
        throw TangledPullReviewClientError.invalidPatchBlob(round.patchBlob.ref.rawValue)
    }
    return patch
}

private func patchBlobData(
    did: DID,
    cid: ATProto.CID,
    pdsHost: ATProto.PDSHost
) async throws -> Data {
    @Dependency(\.httpClient) var httpClient
    guard let url = URL(
        string: "https://\(pdsHost.rawValue)/xrpc/com.atproto.sync.getBlob"
    ) else {
        throw TangledPullReviewClientError.invalidBlobURL(pdsHost.rawValue)
    }
    return try await httpClient.get(
        url,
        queryItems: [
            URLQueryItem(name: "did", value: did.description),
            URLQueryItem(name: "cid", value: cid.rawValue),
        ],
        decodingTo: Data.self
    )
}

private func pdsHost(for did: DID) async throws -> ATProto.PDSHost {
    @Dependency(Atmosphere.Account.Client.self) var accountClient
    let (_, document) = try await accountClient.resolveDID(did)
    guard let pdsHost = document.pdsHost else {
        throw TangledPullReviewClientError.missingPullAuthorPDS(did.description)
    }
    return pdsHost
}

private func requireTangledPullURI(_ uri: String) throws -> ATProto.URI {
    guard let pullURI = ATProto.URI(uri) else {
        throw TangledPullReviewClientError.invalidReviewURI(uri)
    }
    guard pullURI.collection == TangledNSID.pull, pullURI.rkey != nil else {
        throw TangledPullReviewClientError.unsupportedReviewURICollection(uri)
    }
    return pullURI
}

private func requireDIDAuthority(_ uri: ATProto.URI) throws -> DID {
    switch uri.authority {
    case let .did(did):
        return did
    case .handle:
        throw TangledPullReviewClientError.invalidReviewAuthor(uri.description)
    }
}

private func tangledPullState(
    from status: Open<TangledPullStatus>
) -> Open<TangledPullState> {
    switch status.rawValue {
    case TangledPullStatus.closed.rawValue:
        return .closed
    case TangledPullStatus.merged.rawValue:
        return .merged
    default:
        return .open
    }
}

private func mergedTangledPullReviews(
    primary: [TangledPullReview],
    fallback: [TangledPullReview]
) -> [TangledPullReview] {
    var seen = Set<String>()
    var reviews: [TangledPullReview] = []
    reviews.reserveCapacity(primary.count + fallback.count)

    for review in primary + fallback where seen.insert(review.uri).inserted {
        reviews.append(review)
    }

    return reviews.sorted {
        ($0.stateUpdatedAt ?? $0.createdAt) > ($1.stateUpdatedAt ?? $1.createdAt)
    }
}

private func tangledPullReviewTimestamp(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}
