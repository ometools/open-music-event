import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@Suite
struct CanonicalContributorEditingTests {
    @Test
    func contributorEditsPreserveIdentityAndDeletionKeepsProgramCreditText() throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)

        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let programID = try #require(Program.ID(
            "at://did:plc:organizer/events.openmusic.program/3mrdbziccpcai"
        ))
        let itemID = try #require(ProgramItem.ID(
            "at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcaj"
        ))
        let placeID = try #require(EventPlace.ID(
            "at://did:plc:organizer/events.openmusic.eventPlace/3mrdbziccpcak"
        ))
        let event = try Event(
            id: eventID,
            name: "Wicked Woods",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: #require(TimeZone(identifier: "America/Denver")),
            programs: [programID]
        )
        try database.write { try Event.insert { event }.execute($0) }

        let contributorID = try database.write { db in
            try ContributorRecordEditing.create(
                eventID: eventID,
                fields: .init(name: "The Woods Collective"),
                createdAt: try Date("2026-09-02T18:00:00Z", strategy: .iso8601),
                in: db
            )
        }
        let original = try database.read {
            try #require(try Contributor.find(contributorID).fetchOne($0))
        }
        #expect(contributorID.authority == eventID.authority)

        let subject = try #require(DID("did:plc:collective"))
        try database.write { db in
            try ContributorRecordEditing.update(
                contributorID,
                eventID: eventID,
                fields: .init(
                    name: "Wicked Woods Collective",
                    subject: subject,
                    description: "Live performers",
                    roles: [.known(.performer)]
                ),
                in: db
            )
        }
        let updated = try database.read {
            try #require(try Contributor.find(contributorID).fetchOne($0))
        }
        #expect(updated.id == original.id)
        #expect(updated.createdAt == original.createdAt)
        #expect(updated.subject == subject)
        #expect(updated.roles == [.known(.performer)])

        var item = try ProgramItem(
            id: itemID,
            event: eventID,
            program: programID,
            title: "Opening Set",
            createdAt: "2026-09-04T18:00:00Z"
        )
        item.credits = [.init(name: "Wicked Woods Collective", contributor: contributorID)]
        try database.write { try ProgramItem.insert { item }.execute($0) }
        let stageColor = try #require(OME.Color(rawValue: 0x336699))
        let place = try EventPlace(
            id: placeID,
            event: eventID,
            name: "The Hollow",
            createdAt: "2026-09-04T18:00:00Z",
            kind: .known(.stage(.init(color: stageColor, lineup: [contributorID])))
        )
        try database.write { try EventPlace.insert { place }.execute($0) }

        try database.write { db in
            try ContributorRecordEditing.delete(contributorID, eventID: eventID, in: db)
        }
        #expect(try database.read { try Contributor.find(contributorID).fetchOne($0) } == nil)
        let retainedItem = try database.read {
            try #require(try ProgramItem.find(itemID).fetchOne($0))
        }
        #expect(retainedItem.credits?.map(\.name) == ["Wicked Woods Collective"])
        #expect(retainedItem.credits?.first?.contributor == nil)
        let retainedPlace = try database.read {
            try #require(try EventPlace.find(placeID).fetchOne($0))
        }
        guard case let .known(.stage(stage)) = retainedPlace.kind else {
            Issue.record("Expected the stage place to remain after contributor deletion")
            return
        }
        #expect(stage.lineup == nil)
        #expect(stage.color == stageColor)
    }
}
