import ATProto
import CasePaths
import Foundation
import Lexicon
import SQLiteData

extension OpenMusicEvent {
    public typealias RelationshipTimestamp = String

    public enum RelationshipCollection: String, Codable, Equatable, Hashable, Sendable {
        case relationship = "app.openmusicevent.relationship"
        case confirmation = "app.openmusicevent.relationship.confirmation"

        public var nsid: ATProto.NSID {
            ATProto.NSID(rawValue)
        }

        public var repoScope: String {
            "repo:\(rawValue)"
        }
    }

    public enum RelationshipOAuthScopes {
        public static let defaultWriteScope = [
            RelationshipCollection.relationship.repoScope,
            RelationshipCollection.confirmation.repoScope,
        ]
        .joined(separator: " ")
    }
}

extension OpenMusicEvent {
    @Table("relationships")
    public struct Relationship: Codable, Equatable, Sendable {
        public static let collection = RelationshipCollection.relationship
        public static let nsid = collection.nsid

        public var type: String
        @Column(as: Open<Entity>.JSONRepresentation.self)
        public var subject: Open<Entity>
        public var role: Role
        @Column(as: Open<Entity>.JSONRepresentation?.self)
        public var object: Open<Entity>?
        public var createdAt: String

        public init(
            type: String = Self.collection.rawValue,
            subject: Open<Entity>,
            role: Role,
            object: Open<Entity>? = nil,
            createdAt: String
        ) {
            self.type = type
            self.subject = subject
            self.role = role
            self.object = object
            self.createdAt = createdAt
        }

        public init(
            type: String = Self.collection.rawValue,
            subject: Entity,
            role: Role,
            object: Entity? = nil,
            createdAt: String
        ) {
            self.init(
                type: type,
                subject: .known(subject),
                role: role,
                object: object.map { .known($0) },
                createdAt: createdAt
            )
        }

        public init(
            type: String = Self.collection.rawValue,
            subject: RecordReference,
            role: Role,
            object: RecordReference,
            createdAt: String
        ) {
            self.init(
                type: type,
                subject: .record(subject),
                role: role,
                object: .record(object),
                createdAt: createdAt
            )
        }

        enum CodingKeys: String, CodingKey {
            case type = "$type"
            case subject
            case role
            case object
            case createdAt
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decodeIfPresent(String.self, forKey: .type) ?? Self.collection.rawValue
            subject = try container.decode(Open<Entity>.self, forKey: .subject)
            role = try container.decode(Role.self, forKey: .role)
            object = try container.decodeIfPresent(Open<Entity>.self, forKey: .object)
            createdAt = try container.decode(String.self, forKey: .createdAt)
        }
    }

    @Table("relationshipConfirmations")
    public struct RelationshipConfirmation: Codable, Equatable, Sendable {
        public static let collection = RelationshipCollection.confirmation
        public static let nsid = collection.nsid

        public var type: String
        @Column(as: OpenMusicEvent.Relationship.RecordReference.JSONRepresentation.self)
        public var relationship: OpenMusicEvent.Relationship.RecordReference
        public var status: Status
        public var createdAt: String

        public init(
            type: String = Self.collection.rawValue,
            relationship: OpenMusicEvent.Relationship.RecordReference,
            status: Status = .accepted,
            createdAt: String
        ) {
            self.type = type
            self.relationship = relationship
            self.status = status
            self.createdAt = createdAt
        }

        enum CodingKeys: String, CodingKey {
            case type = "$type"
            case relationship
            case status
            case createdAt
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decodeIfPresent(String.self, forKey: .type) ?? Self.collection.rawValue
            relationship = try container.decode(OpenMusicEvent.Relationship.RecordReference.self, forKey: .relationship)
            status = try container.decode(Status.self, forKey: .status)
            createdAt = try container.decode(String.self, forKey: .createdAt)
        }
    }
}

extension OpenMusicEvent.Relationship {
    @CasePathable
    public enum Entity: OpenUnion {
        case identity(IdentityReference)
        case record(RecordReference)

        public static let unionTypes: OpenUnionTypes<Self> = [
            .type(IdentityReference.type, \.identity),
            .type(RecordReference.type, \.record),
        ]

        public var identity: IdentityReference? {
            guard case let .identity(reference) = self else { return nil }
            return reference
        }

        public var record: RecordReference? {
            guard case let .record(reference) = self else { return nil }
            return reference
        }

        public static func identity(
            did: DID,
            handle: String? = nil,
            displayName: String? = nil
        ) -> Self {
            .identity(
                IdentityReference(
                    did: did,
                    handle: handle,
                    displayName: displayName
                )
            )
        }

        public static func record(
            author: DID,
            collection: ATProto.NSID,
            rkey: ATProto.Record.Key,
            cid: ATProto.CID? = nil
        ) -> Self {
            .record(
                RecordReference(
                    author: author,
                    collection: collection,
                    rkey: rkey,
                    cid: cid
                )
            )
        }
    }

    public struct IdentityReference: Codable, Equatable, Hashable, Sendable {
        public static let type = "app.openmusicevent.relationship#identity"

        public var type: String
        public var did: DID
        public var handle: String?
        public var displayName: String?

        public init(
            type: String = Self.type,
            did: DID,
            handle: String? = nil,
            displayName: String? = nil
        ) {
            self.type = type
            self.did = did
            self.handle = handle
            self.displayName = displayName
        }

        enum CodingKeys: String, CodingKey {
            case type = "$type"
            case did
            case handle
            case displayName
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decodeIfPresent(String.self, forKey: .type) ?? Self.type
            did = try container.decode(DID.self, forKey: .did)
            handle = try container.decodeIfPresent(String.self, forKey: .handle)
            displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        }
    }

    public struct RecordReference: Codable, Equatable, Hashable, Sendable {
        public static let type = "app.openmusicevent.relationship#record"

        public var type: String
        public var uri: ATProto.URI
        public var cid: ATProto.CID?

        public init(
            type: String = Self.type,
            uri: ATProto.URI,
            cid: ATProto.CID? = nil
        ) {
            self.type = type
            self.uri = uri
            self.cid = cid
        }

        public init(
            type: String = Self.type,
            author: DID,
            collection: ATProto.NSID,
            rkey: ATProto.Record.Key,
            cid: ATProto.CID? = nil
        ) {
            self.init(
                type: type,
                uri: ATProto.URI(
                    authority: .did(author),
                    collection: collection,
                    rkey: rkey
                ),
                cid: cid
            )
        }

        enum CodingKeys: String, CodingKey {
            case type = "$type"
            case uri
            case cid
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decodeIfPresent(String.self, forKey: .type) ?? Self.type
            uri = try container.decode(ATProto.URI.self, forKey: .uri)
            cid = try container.decodeIfPresent(ATProto.CID.self, forKey: .cid)
        }
    }

    public struct Role: Codable, Equatable, Hashable, Sendable, ExpressibleByStringLiteral, RawRepresentable, SQLiteType {
        public var rawValue: String

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.init(value)
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.init(try container.decode(String.self))
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        public static let contributor = Self("contributor")
        public static let developer = Self("developer")
        public static let maintainer = Self("maintainer")
        public static let organizer = Self("organizer")
        public static let performer = Self("performer")
        public static let sponsor = Self("sponsor")
        public static let author = Self("author")
        public static let publisher = Self("publisher")
        public static let promoter = Self("promoter")
        public static let mediaManager = Self("mediaManager")
        public static let soundTech = Self("soundTech")
        public static let stageHand = Self("stageHand")
        public static let dj = Self("dj")
        public static let dancer = Self("dancer")
        public static let visualArtist = Self("visualArtist")
        public static let displayed = Self("displayed")
    }

    public enum Validation {
        public static func author(
            _ author: DID,
            matches entity: Open<Entity>
        ) -> Bool {
            switch entity {
            case .unknown:
                false
            case let .known(.identity(identity)):
                identity.did == author
            case let .known(.record(record)):
                record.uri.authority.relationshipDID == author
            }
        }

        public static func relationshipAuthor(
            _ author: DID,
            canAssert relationship: OpenMusicEvent.Relationship
        ) -> Bool {
            guard let object = relationship.object else { return true }
            return self.author(author, matches: object)
        }

        public static func confirmationAuthor(
            _ author: DID,
            confirms relationship: OpenMusicEvent.Relationship
        ) -> Bool {
            self.author(author, matches: relationship.subject)
        }
    }
}

extension OpenMusicEvent.RelationshipConfirmation {
    public struct Status: Codable, Equatable, Hashable, Sendable, ExpressibleByStringLiteral, RawRepresentable, SQLiteType {
        public var rawValue: String

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.init(value)
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.init(try container.decode(String.self))
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        public static let accepted = Self("accepted")
        public static let rejected = Self("rejected")
        public static let revoked = Self("revoked")
    }
}

private extension ATProto.URI.Authority {
    var relationshipDID: DID? {
        guard case let .did(did) = self else { return nil }
        return did
    }
}
