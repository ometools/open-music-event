import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventLexicon
import SQLiteData

public enum RelationshipRecordEditing {
    public enum Error: Swift.Error, Equatable {
        case eventUnavailable
        case relationshipUnavailable
        case subjectUnavailable
        case roleRequired
    }

    public struct Fields: Equatable, Sendable {
        public var subject: Open<OME.Relationship.Entity>
        public var role: OME.Relationship.Role
        public var capabilities: [OME.WorkspaceRole.Capability]?

        public init(
            subject: Open<OME.Relationship.Entity>,
            role: OME.Relationship.Role,
            capabilities: [OME.WorkspaceRole.Capability]? = nil
        ) {
            self.subject = subject
            self.role = role
            self.capabilities = capabilities
        }

        public init(_ relationship: OME.Relationship) {
            self.init(
                subject: relationship.subject,
                role: relationship.role,
                capabilities: relationship.capabilities
            )
        }

        fileprivate func validate() throws {
            guard case .known = subject else { throw Error.subjectUnavailable }
            guard !role.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw Error.roleRequired
            }
        }

        fileprivate func apply(to relationship: inout OME.Relationship) {
            relationship.subject = subject
            relationship.role = role
            relationship.capabilities = role == .collaborator ? capabilities : nil
        }
    }

    public static func create(
        eventID: Event.ID,
        fields: Fields,
        createdAt: Date,
        in db: Database
    ) throws -> ATProto.URI {
        guard try Event.find(eventID).fetchOne(db) != nil else {
            throw Error.eventUnavailable
        }
        try fields.validate()
        let existing = try OME.Relationship.all.fetchAll(db)
        let previousKey = existing.compactMap(\.id)
            .filter { $0.authority == eventID.authority }
            .compactMap(\.rkey)
            .max { $0.rawValue < $1.rawValue }
        var relationship = OME.Relationship(
            subject: fields.subject,
            role: fields.role,
            object: .known(.record(.init(uri: eventID))),
            createdAt: ISO8601DateFormatter().string(from: createdAt)
        )
        fields.apply(to: &relationship)
        try relationship.assignRecordID(at: createdAt, after: previousKey)
        guard let id = relationship.id, id.authority == eventID.authority else {
            throw Error.eventUnavailable
        }
        try OME.Relationship.insert { relationship }.execute(db)
        return id
    }

    public static func update(
        _ id: ATProto.URI,
        eventID: Event.ID,
        fields: Fields,
        in db: Database
    ) throws {
        guard try Event.find(eventID).fetchOne(db) != nil else {
            throw Error.eventUnavailable
        }
        try fields.validate()
        guard var relationship = try relationship(id, eventID: eventID, in: db) else {
            throw Error.relationshipUnavailable
        }
        fields.apply(to: &relationship)
        try OME.Relationship.upsert { relationship }.execute(db)
    }

    public static func delete(
        _ id: ATProto.URI,
        eventID: Event.ID,
        in db: Database
    ) throws {
        guard try relationship(id, eventID: eventID, in: db) != nil else {
            throw Error.relationshipUnavailable
        }
        try OME.Relationship.where { $0.id.eq(id) }.delete().execute(db)
    }

    private static func relationship(
        _ id: ATProto.URI,
        eventID: Event.ID,
        in db: Database
    ) throws -> OME.Relationship? {
        guard id.authority == eventID.authority else { return nil }
        let rows = try OME.Relationship.all.fetchAll(db)
        return rows.first { row in
            guard row.id == id,
                  case let .some(.known(.record(object))) = row.object
            else { return false }
            return object.uri == eventID
        }
    }
}
