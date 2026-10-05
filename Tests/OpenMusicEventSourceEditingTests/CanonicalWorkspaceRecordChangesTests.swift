import ATProto
import ATProtoTypes
import Foundation
import CustomDump
import OpenMusicEventDatabase
import OpenMusicEventLexicon
@testable import OpenMusicEventSourceEditing
import SQLiteData
import Testing

@Suite("Canonical workspace record changes")
struct CanonicalWorkspaceRecordChangesTests {
    @Test func `review shows changed description images and event local times without technical fields`() throws {
        let id = Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")!
        var original = try Event(id: id, name: "Testival", createdAt: "2026-07-01T00:00:00Z",
                                 timeZone: #require(TimeZone(identifier: "America/Denver")))
        original.description = "Before the edit"
        original.start = .known(.time(.init(value: "2026-07-02T02:00:00Z")))
        let imageA = OME.Image(source: .known(.url(URL(string: "https://example.com/a.png")!)),
                               alt: .init(rawValue: "Green map"))
        let imageB = OME.Image(source: .known(.url(URL(string: "https://example.com/b.png")!)),
                               alt: .init(rawValue: "Orange map"))
        original.media = [.known(.image(imageA))]
        var edited = original
        edited.description = "After the edit"
        edited.media = [.known(.image(imageB))]
        let change = try CanonicalWorkspaceRecordChange(
            collection: Event.tableName, id: id, kind: .edited,
            before: original.encodeLexicon(), after: edited.encodeLexicon()
        )
        expectNoDifference(change.title, "Testival")
        expectNoDifference(change.fields.map(\.id), ["description", "media"])
        expectNoDifference(change.fields[0].before?.lines, ["Before the edit"])
        expectNoDifference(change.fields[0].after?.lines, ["After the edit"])
        expectNoDifference(change.fields[1].before?.images, [imageA])
        expectNoDifference(change.fields[1].after?.images, [imageB])

        // The first publication includes the event-local date, not the device's date.
        let firstPublication = try #require(try CanonicalWorkspaceRecordChange.event(original, receipt: nil))
        let start = try #require(firstPublication.fields.first { $0.id == "start" })
        let expectedDate = try Date("2026-07-02T02:00:00Z", strategy: .iso8601)
        expectNoDifference(start.after?.lines, [
            expectedDate.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened,
                                                    timeZone: original.timeZone)),
            "America/Denver"
        ])
        #expect(!firstPublication.fields.contains { $0.id == "createdAt" || $0.id == "id" || $0.id == "$type" })

        // Removing optional content still shows what is being removed.
        edited.description = nil
        let removed = try CanonicalWorkspaceRecordChange(
            collection: Event.tableName, id: id, kind: .edited,
            before: original.encodeLexicon(), after: edited.encodeLexicon()
        )
        expectNoDifference(removed.fields.first { $0.id == "description" }?.after, nil)
        expectNoDifference(removed.fields.first { $0.id == "description" }?.before?.lines, ["Before the edit"])
    }

    @Test func `later edits compare and reset to verified content without advancing the import baseline`() throws {
        let working = try DatabaseQueue()
        let baseline = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(working)
        try migrator.migrate(baseline)
        let reference = SourceBaselineDatabase(path: "baseline", database: baseline)
        let id = Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")!
        let imported = try Event(id: id, name: "Testival", createdAt: "2026-07-01T00:00:00Z", timeZone: .gmt)
        try baseline.write { try Event.insert { imported }.execute($0) }
        var published = imported
        published.description = "Published version"
        let review = try EventRecordPublication.prepare(events: [published], account: DID("did:plc:organizer")!) { _ in Data() }
        let receipt = EventRecordPublicationReceipt(
            id: id, cid: ATProto.CID(rawValue: "bafyreipublished"),
            payloadSHA256: review.records[0].payloadSHA256, images: [],
            event: .init(uri: id, cid: nil, value: review.records[0].payload)
        )
        var edited = published
        edited.description = "Next unpublished edit"
        let saved = edited
        try working.write { db in
            try Event.insert { saved }.execute(db)
            try EventRecordPublicationReceipt.insert { receipt }.execute(db)
        }
        let changes = try working.read {
            try CanonicalWorkspaceRecordChanges.changes(eventID: id, in: $0, referenceDatabase: reference)
        }
        expectNoDifference(changes.count, 1)
        expectNoDifference(changes[0].fields[0].before?.lines, ["Published version"])
        expectNoDifference(changes[0].fields[0].after?.lines, ["Next unpublished edit"])

        try CanonicalWorkspaceRecordChanges.reset(eventID: id, in: working, referenceDatabase: reference)
        expectNoDifference(try working.read { try Event.find(id).fetchOne($0)?.description }, "Published version")
        expectNoDifference(try baseline.read { try Event.find(id).fetchOne($0)?.description }, nil)
        expectNoDifference(try working.read {
            try CanonicalWorkspaceRecordChanges.changes(eventID: id, in: $0, referenceDatabase: reference)
        }, [])
    }

    @Test func `verified publication is no longer a pending local change`() throws {
        let working = try DatabaseQueue()
        let baseline = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(working)
        try migrator.migrate(baseline)
        let reference = SourceBaselineDatabase(path: "baseline", database: baseline)
        let id = Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")!
        let imported = try Event(id: id, name: "Testival", createdAt: "2026-07-01T00:00:00Z", timeZone: .gmt)
        try baseline.write { try Event.insert { imported }.execute($0) }
        var edited = imported
        edited.description = "Published from the event form"
        let published = edited
        let review = try EventRecordPublication.prepare(events: [published], account: DID("did:plc:organizer")!) { _ in
            Issue.record("This event has no images")
            return Data()
        }
        let receipt = EventRecordPublicationReceipt(
            id: id, cid: ATProto.CID(rawValue: "bafyreipublished"),
            payloadSHA256: review.records[0].payloadSHA256, images: []
        )
        // A verified receipt refers to the exact saved content, even when imported earlier.
        try working.write { db in
            try Event.insert { published }.execute(db)
            try EventRecordPublicationReceipt.insert { receipt }.execute(db)
        }
        let changes = try working.read {
            try CanonicalWorkspaceRecordChanges.changes(eventID: id, in: $0, referenceDatabase: reference)
        }
        expectNoDifference(changes, [])
    }

    @Test
    func eventRelationshipChangesResetWithoutTouchingSiblingEvent() throws {
        let working = try DatabaseQueue()
        let baseline = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(working)
        try migrator.migrate(baseline)
        let reference = SourceBaselineDatabase(path: "baseline", database: baseline)
        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let siblingID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcai"
        ))
        let events = try [eventID, siblingID].map {
            try Event(id: $0, name: "Wicked Woods", createdAt: "2026-09-01T12:00:00Z", timeZone: .gmt)
        }
        try working.write { db in try Event.insert { events }.execute(db) }
        try baseline.write { db in try Event.insert { events }.execute(db) }
        let collaborator = try #require(DID("did:plc:collaborator"))
        let fields = RelationshipRecordEditing.Fields(
            subject: .known(.identity(did: collaborator)),
            role: .collaborator,
            capabilities: [.propose]
        )
        let createdAt = try Date("2026-09-02T18:00:00Z", strategy: .iso8601)

        // The sibling event receives a collaborator, but this workspace has no changes.
        let siblingRelationshipID = try working.write {
            try RelationshipRecordEditing.create(eventID: siblingID, fields: fields, createdAt: createdAt, in: $0)
        }
        try working.read { db in
            let changes = try CanonicalWorkspaceRecordChanges.changes(
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(changes.isEmpty)
        }

        // Adding a collaborator to this event produces one URI-addressed change.
        let relationshipID = try working.write {
            try RelationshipRecordEditing.create(eventID: eventID, fields: fields, createdAt: createdAt, in: $0)
        }
        try working.read { db in
            let changes = try CanonicalWorkspaceRecordChanges.changes(
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(changes.count == 1)
            #expect(changes.first?.id == relationshipID)
            #expect(changes.first?.collection == OME.Relationship.tableName)
            #expect(changes.first?.kind == .added)
        }

        try CanonicalWorkspaceRecordChanges.reset(
            eventID: eventID,
            in: working,
            referenceDatabase: reference
        )
        try working.read { db in
            let relationships = try OME.Relationship.all.fetchAll(db)
            let changes = try CanonicalWorkspaceRecordChanges.changes(
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(relationships.map(\.id) == [siblingRelationshipID])
            #expect(changes.isEmpty)
        }
    }

    @Test
    func detectsOrganizerChangesWithoutCountingOtherRepositories() throws {
        let working = try DatabaseQueue()
        let baseline = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(working)
        try migrator.migrate(baseline)
        let reference = SourceBaselineDatabase(path: "baseline", database: baseline)
        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let event = try Event(
            id: eventID,
            name: "Wicked Woods",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        try working.write { db in try Event.insert { event }.execute(db) }
        try baseline.write { db in try Event.insert { event }.execute(db) }

        try working.read { db in
            let hasChanges = try CanonicalWorkspaceRecordChanges.hasChanges(
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(!hasChanges)
        }

        try working.write { db in
            var changed = try #require(try Event.find(eventID).fetchOne(db))
            changed.name = "Wicked Woods Updated"
            let saved = changed
            try Event.upsert { saved }.execute(db)
        }
        try working.read { db in
            let changes = try CanonicalWorkspaceRecordChanges.changes(
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(changes.count == 1)
            #expect(changes.first?.collection == Event.tableName)
            #expect(changes.first?.id == eventID)
            #expect(changes.first?.kind == .edited)
        }

        let otherID = try #require(Event.ID(
            "at://did:plc:other/events.openmusic.event/3mrdbziccpcai"
        ))
        let other = try Event(
            id: otherID,
            name: "Another Event",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        try working.write { db in
            try Event.upsert { event }.execute(db)
            try Event.insert { other }.execute(db)
        }
        try working.read { db in
            let hasChanges = try CanonicalWorkspaceRecordChanges.hasChanges(
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(!hasChanges)
        }

        let siblingID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcaj"
        ))
        let sibling = try Event(
            id: siblingID,
            name: "Another organizer event",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: .gmt
        )
        try working.write { db in try Event.insert { sibling }.execute(db) }
        try working.read { db in
            let changes = try CanonicalWorkspaceRecordChanges.changes(
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(changes.count == 1)
            #expect(changes.first?.id == siblingID)
            #expect(changes.first?.kind == .added)
        }
        try baseline.write { db in try Event.insert { sibling }.execute(db) }

        let placeID = try #require(EventPlace.ID(
            "at://did:plc:organizer/events.openmusic.eventPlace/3mrdbziccpcak"
        ))
        let place = try EventPlace(
            id: placeID,
            event: eventID,
            name: "Main Stage",
            createdAt: "2026-09-01T12:00:00Z"
        )
        try working.write { db in try EventPlace.insert { place }.execute(db) }
        try working.read { db in
            let hasChanges = try CanonicalWorkspaceRecordChanges.hasChanges(
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(hasChanges)
        }

        let stageID = try #require(Stage.ID(
            "at://did:plc:organizer/events.openmusic.stage/3mrdbziccpcam"
        ))
        let stage = try Stage(
            id: stageID,
            name: "Persistent Main Stage",
            createdAt: "2026-09-01T12:00:00Z"
        )
        try baseline.write { db in try EventPlace.insert { place }.execute(db) }
        try working.write { db in try Stage.insert { stage }.execute(db) }
        try working.read { db in
            let hasChanges = try CanonicalWorkspaceRecordChanges.hasChanges(
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(hasChanges)
        }

        // Deleting one record and adding another produces two local changes without
        // including the unrelated repository's event.
        try working.write { db in try EventPlace.find(placeID).delete().execute(db) }
        try working.read { db in
            let changes = try CanonicalWorkspaceRecordChanges.changes(
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(changes.count == 2)
            #expect(changes.contains { $0.id == placeID && $0.kind == .deleted })
            #expect(changes.contains { $0.id == stageID && $0.kind == .added })
        }

        try CanonicalWorkspaceRecordChanges.reset(
            eventID: eventID,
            in: working,
            referenceDatabase: reference
        )
        try working.read { db in
            let restoredEvent = try Event.find(eventID).fetchOne(db)
            let siblingEvent = try Event.find(siblingID).fetchOne(db)
            let restoredPlace = try EventPlace.find(placeID).fetchOne(db)
            let removedStage = try Stage.find(stageID).fetchOne(db)
            let otherEvent = try Event.find(otherID).fetchOne(db)
            let remainingChanges = try CanonicalWorkspaceRecordChanges.changes(
                eventID: eventID, in: db, referenceDatabase: reference
            )
            #expect(restoredEvent?.name == "Wicked Woods")
            #expect(siblingEvent?.name == "Another organizer event")
            #expect(restoredPlace?.name == "Main Stage")
            #expect(removedStage == nil)
            #expect(otherEvent?.name == "Another Event")
            #expect(remainingChanges.isEmpty)
        }
    }
}
