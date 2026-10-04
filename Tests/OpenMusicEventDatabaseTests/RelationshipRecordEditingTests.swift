import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@Suite("Relationship record editing")
struct RelationshipRecordEditingTests {
    @Test
    func ownerCreatesEditsAndDeletesAnEventCollaboratorByRecordURI() throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let event = try Event(
            id: eventID,
            name: "Wicked Woods",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        try database.write { try Event.insert { event }.execute($0) }

        let collaborator = try #require(DID("did:plc:collaborator"))
        let id = try database.write { db in
            try RelationshipRecordEditing.create(
                eventID: eventID,
                fields: .init(
                    subject: .known(.identity(did: collaborator)),
                    role: .collaborator,
                    capabilities: [.propose]
                ),
                createdAt: try Date("2026-09-02T18:00:00Z", strategy: .iso8601),
                in: db
            )
        }
        let created = try database.read {
            try #require(try OME.Relationship.where { $0.id.eq(id) }.fetchOne($0))
        }
        #expect(id.authority == eventID.authority)
        #expect(id.collection == OME.Relationship.nsid)
        #expect(created.workspaceRole == .collaborator([.propose]))
        #expect(created.createdAt == "2026-09-02T18:00:00Z")

        try database.write { db in
            try RelationshipRecordEditing.update(
                id,
                eventID: eventID,
                fields: .init(
                    subject: .known(.identity(did: collaborator, displayName: "Alice")),
                    role: .collaborator,
                    capabilities: [.propose, .merge]
                ),
                in: db
            )
        }
        let updated = try database.read {
            try #require(try OME.Relationship.where { $0.id.eq(id) }.fetchOne($0))
        }
        #expect(updated.id == id)
        #expect(updated.createdAt == created.createdAt)
        #expect(updated.workspaceRole == .collaborator([.propose, .merge]))

        try database.write { db in
            try RelationshipRecordEditing.delete(id, eventID: eventID, in: db)
        }
        #expect(try database.read {
            try OME.Relationship.where { $0.id.eq(id) }.fetchOne($0)
        } == nil)
    }
}
