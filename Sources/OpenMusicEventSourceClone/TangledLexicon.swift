import ATProto
import ATProtoOAuth
import Dependencies
import Foundation
import XRPCClient

public enum TangledOAuthRequirements {
    public static let patchBlobPermission = OAuth.Permission("blob:application/gzip")
    public static let legacyPatchBlobPermission = OAuth.Permission("blob:text/x-patch")
    public static let publicKeyCreatePermission = OAuth.Permission(
        "repo:sh.tangled.publicKey?action=create"
    )
    public static let pullPermission = OAuth.Permission(
        "repo:sh.tangled.repo.pull"
    )
    public static let pullCreatePermission = OAuth.Permission(
        "repo:sh.tangled.repo.pull?action=create"
    )
    public static let pullStatusPermission = OAuth.Permission(
        "repo:sh.tangled.repo.pull.status"
    )
    public static let pullStatusCreatePermission = OAuth.Permission(
        "repo:sh.tangled.repo.pull.status?action=create"
    )

    public static let publicKeyAuthRequirement = OAuth.AuthRequirement(
        permissions: [publicKeyCreatePermission]
    )

    public static let proposalAuthRequirement = OAuth.AuthRequirement(
        permissions: [
            patchBlobPermission,
            pullCreatePermission,
        ]
    )

    public static let pullRequestSurfaceAuthRequirement = OAuth.AuthRequirement(
        permissions: [
            patchBlobPermission,
            pullPermission,
            pullStatusPermission,
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

public struct TangledPublicKeyRecord: Encodable, Decodable, Equatable, Sendable {
    public static let collection = "sh.tangled.publicKey"

    public var key: String
    public var name: String
    public var createdAt: String

    public init(key: String, name: String, createdAt: String) {
        self.key = key
        self.name = name
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case createdAt
        case key
        case name
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(String.self, forKey: .createdAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.collection, forKey: .type)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(key, forKey: .key)
        try container.encode(name, forKey: .name)
    }
}

public struct TangledRepositoryRecord: Decodable, Equatable, Sendable {
    public static let collection = "sh.tangled.repo"

    public var name: String?
    public var repo: String?
    public var repoDid: String?

    public init(name: String? = nil, repo: String? = nil, repoDid: String? = nil) {
        self.name = name
        self.repo = repo
        self.repoDid = repoDid
    }

    public func matches(_ reference: TangledRepositoryReference) -> Bool {
        (name ?? repo) == reference.repository
    }
}

public struct TangledRepositoryTarget: Equatable, Sendable {
    public var recordURI: String
    public var repoDID: String

    public init(recordURI: String, repoDID: String) {
        self.recordURI = recordURI
        self.repoDID = repoDID
    }
}

public struct TangledRepoPullRecord: Encodable, Sendable {
    public static let collection = "sh.tangled.repo.pull"

    public struct Round: Encodable, Sendable {
        public var createdAt: String
        public var patchBlob: ATProto.Blob

        public init(createdAt: String, patchBlob: ATProto.Blob) {
            self.createdAt = createdAt
            self.patchBlob = patchBlob
        }
    }

    public struct Target: Encodable, Equatable, Sendable {
        public var branch: String
        public var repo: String
        public var repoDID: String?

        public init(branch: String, repo: String, repoDID: String? = nil) {
            self.branch = branch
            self.repo = repo
            self.repoDID = repoDID
        }

        enum CodingKeys: String, CodingKey {
            case branch
            case repo
            case repoDID = "repoDid"
        }
    }

    public struct Source: Encodable, Equatable, Sendable {
        public var branch: String
        public var repo: String?
        public var sha: String?

        public init(branch: String, repo: String? = nil, sha: String? = nil) {
            self.branch = branch
            self.repo = repo
            self.sha = sha
        }

        enum CodingKeys: String, CodingKey {
            case branch
            case repo
            case sha
        }
    }

    public var body: String?
    public var createdAt: String
    public var patch: String?
    public var patchBlob: ATProto.Blob
    public var pullID: Int64
    public var rounds: [Round]
    public var source: Source?
    public var target: Target
    public var title: String

    public init(
        body: String? = nil,
        createdAt: String,
        patch: String? = nil,
        patchBlob: ATProto.Blob,
        pullID: Int64,
        rounds: [Round],
        source: Source? = nil,
        target: Target,
        title: String
    ) {
        self.body = body
        self.createdAt = createdAt
        self.patch = patch
        self.patchBlob = patchBlob
        self.pullID = pullID
        self.rounds = rounds
        self.source = source
        self.target = target
        self.title = title
    }

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case body
        case createdAt
        case patch
        case patchBlob
        case pullID = "pullId"
        case rounds
        case source
        case target
        case targetBranch
        case targetRepo
        case title
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.collection, forKey: .type)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(patch, forKey: .patch)
        try container.encode(patchBlob, forKey: .patchBlob)
        try container.encode(pullID, forKey: .pullID)
        try container.encode(rounds, forKey: .rounds)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encode(target, forKey: .target)
        try container.encode(target.branch, forKey: .targetBranch)
        try container.encode(target.repo, forKey: .targetRepo)
        try container.encode(title, forKey: .title)
    }
}

public struct TangledGetRecordRequest<RecordValue: Decodable & Sendable>: XRPC.Request, Sendable {
    public static var nsid: ATProto.NSID { ATProto.NSID("com.atproto.repo.getRecord") }
    public static var type: XRPC.RequestType { .query }

    public typealias Input = Never
    public typealias Output = TangledListedRecord<RecordValue>
    public typealias Parameters = Never

    public var repo: String
    public var collection: String
    public var rkey: String
    public var cid: String?
    public var pdsHost: ATProto.PDSHost?
    public var authorizationPolicy: XRPC.AuthorizationPolicy

    public init(
        repo: String,
        collection: String,
        rkey: String,
        cid: String? = nil,
        pdsHost: ATProto.PDSHost? = nil,
        authorizationPolicy: XRPC.AuthorizationPolicy = .none
    ) {
        self.repo = repo
        self.collection = collection
        self.rkey = rkey
        self.cid = cid
        self.pdsHost = pdsHost
        self.authorizationPolicy = authorizationPolicy
    }

    public var routing: XRPC.Routing {
        guard let pdsHost else { return XRPC.Routing() }
        return XRPC.Routing(
            unauthenticated: .host(pdsHost),
            authenticated: .host(pdsHost)
        )
    }

    public var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "repo", value: repo),
            URLQueryItem(name: "collection", value: collection),
            URLQueryItem(name: "rkey", value: rkey),
        ]
        if let cid {
            items.append(URLQueryItem(name: "cid", value: cid))
        }
        return items
    }
}

public struct TangledListRecordsRequest<RecordValue: Decodable & Sendable>: XRPC.Request, Sendable {
    public static var nsid: ATProto.NSID { ATProto.NSID("com.atproto.repo.listRecords") }
    public static var type: XRPC.RequestType { .query }

    public typealias Input = Never
    public typealias Output = TangledListRecordsOutput<RecordValue>
    public typealias Parameters = Never

    public var repo: String
    public var collection: String
    public var cursor: String?
    public var pdsHost: ATProto.PDSHost?
    public var authorizationPolicy: XRPC.AuthorizationPolicy

    public init(
        repo: String,
        collection: String,
        cursor: String? = nil,
        pdsHost: ATProto.PDSHost? = nil,
        authorizationPolicy: XRPC.AuthorizationPolicy = .none
    ) {
        self.repo = repo
        self.collection = collection
        self.cursor = cursor
        self.pdsHost = pdsHost
        self.authorizationPolicy = authorizationPolicy
    }

    public var routing: XRPC.Routing {
        guard let pdsHost else { return XRPC.Routing() }
        return XRPC.Routing(
            unauthenticated: .host(pdsHost),
            authenticated: .host(pdsHost)
        )
    }

    public var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "repo", value: repo),
            URLQueryItem(name: "collection", value: collection),
            URLQueryItem(name: "limit", value: "100"),
        ]
        if let cursor {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return items
    }
}

public struct TangledListRecordsOutput<RecordValue: Decodable & Sendable>: Decodable, Sendable {
    public var cursor: String?
    public var records: [TangledListedRecord<RecordValue>]

    public init(cursor: String? = nil, records: [TangledListedRecord<RecordValue>]) {
        self.cursor = cursor
        self.records = records
    }
}

public struct TangledListedRecord<RecordValue: Decodable & Sendable>: Decodable, Sendable {
    public var uri: ATProto.URI
    public var cid: ATProto.CID?
    public var value: RecordValue

    public init(uri: ATProto.URI, cid: ATProto.CID? = nil, value: RecordValue) {
        self.uri = uri
        self.cid = cid
        self.value = value
    }
}

public struct TangledCreateRecordInput<Record: Encodable & Sendable>: Encodable, Sendable {
    public var repo: String
    public var collection: String
    public var record: Record

    public init(repo: String, collection: String, record: Record) {
        self.repo = repo
        self.collection = collection
        self.record = record
    }
}

public struct TangledCreateRecordOutput: Decodable, Equatable, Sendable {
    public var uri: ATProto.URI
    public var cid: ATProto.CID

    public init(uri: ATProto.URI, cid: ATProto.CID) {
        self.uri = uri
        self.cid = cid
    }
}

public struct TangledCreateRecordRequest<Record: Encodable & Sendable>: XRPC.Request, Sendable {
    public static var nsid: ATProto.NSID { ATProto.NSID("com.atproto.repo.createRecord") }
    public static var type: XRPC.RequestType { .procedure }

    public typealias Input = TangledCreateRecordInput<Record>
    public typealias Output = TangledCreateRecordOutput
    public typealias Parameters = Never

    public var input: Input
    public var authorizationPolicy: XRPC.AuthorizationPolicy

    public init(
        input: Input,
        authorizationPolicy: XRPC.AuthorizationPolicy
    ) {
        self.input = input
        self.authorizationPolicy = authorizationPolicy
    }
}
