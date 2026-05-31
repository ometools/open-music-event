import ATProto
import CustomDump
import Foundation
import GRDB
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

struct CalendarPersistenceTests {
    @Test
    func roundTripsCalendarWithImages() async throws {
        let database = try makePreparedDatabase()
        let ownerID = try #require(OME.Organizer.ID("did:plc:calendarowner"))
        let image = OME.ImageAsset(
            source: .url(URL(string: "https://example.com/calendar.png")!),
            role: .hero,
            renderKind: .fullImage,
            materializationPolicy: .prefetchOnOpen
        )
        let calendarID = OME.Calendar.ID(
            ownerID: ownerID,
            calendarID: OME.Calendar.defaultID
        )

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: ownerID)
            }
            .execute(db)

            try OME.Calendar.insert {
                OME.Calendar.Draft(
                    id: calendarID,
                    name: "Events",
                    description: "Default public calendar.",
                    images: [image]
                )
            }
            .execute(db)
        }

        let calendar = try await database.read { db in
            try OME.Calendar.fetchOne(db)
        }

        expectNoDifference(
            calendar,
            OME.Calendar(
                id: calendarID,
                name: "Events",
                description: "Default public calendar.",
                images: [image]
            )
        )
    }

    @Test
    func roundTripsCalendarEntryWithEventReference() async throws {
        let database = try makePreparedDatabase()
        let calendarOwnerID = try #require(OME.Organizer.ID("did:plc:calendarowner"))
        let eventOwnerID = try #require(OME.Organizer.ID("did:plc:eventowner"))
        let calendarID = OME.Calendar.ID(
            ownerID: calendarOwnerID,
            calendarID: OME.Calendar.defaultID
        )
        let entryID = OME.CalendarEntry.ID(
            calendarOwnerID: calendarOwnerID,
            calendarID: OME.Calendar.defaultID,
            entryID: localID("event-entry")
        )
        let eventRef = OME.Event.reference(
            id: OME.Event.ID(
                organizerID: eventOwnerID,
                eventID: localID("club-night")
            )
        )
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: calendarOwnerID)
            }
            .execute(db)

            try OME.Calendar.insert {
                OME.Calendar.Draft(
                    id: calendarID,
                    name: "Events",
                    description: nil,
                    images: nil
                )
            }
            .execute(db)

            try OME.CalendarEntry.insert {
                OME.CalendarEntry.Draft(
                    id: entryID,
                    event: eventRef,
                    createdAt: createdAt,
                    note: "DJ calendar pick.",
                    pinned: true
                )
            }
            .execute(db)
        }

        let entry = try await database.read { db in
            try OME.CalendarEntry.fetchOne(db)
        }

        expectNoDifference(
            entry,
            OME.CalendarEntry(
                id: entryID,
                event: eventRef,
                createdAt: createdAt,
                note: "DJ calendar pick.",
                pinned: true
            )
        )
    }

    @Test
    func roundTripsEventOwner() async throws {
        let database = try makePreparedDatabase()
        let organizerID = try #require(OME.Organizer.ID("did:plc:eventowner"))
        let eventID = OME.Event.ID(
            organizerID: organizerID,
            eventID: localID("archive-event")
        )
        let owner = try #require(OME.Contributor.Actor("gratefuldead.bsky.social"))
        let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))

        try await database.write { db in
            try OME.Organizer.insert {
                OME.Organizer.Draft(id: organizerID)
            }
            .execute(db)

            try OME.Event.insert {
                OME.Event.Draft(
                    id: eventID,
                    name: "Archive Event",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: .known(.planned),
                    mode: .known(.inPerson),
                    locations: nil,
                    uris: nil,
                    timeZone: timeZone,
                    imageURL: nil,
                    iconImageURL: nil,
                    siteMapImageURL: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil,
                    owner: owner
                )
            }
            .execute(db)
        }

        let event = try await database.read { db in
            try OME.Event.fetchOne(db)
        }

        #expect(event?.owner == owner)
    }

}

private func makePreparedDatabase() throws -> any DatabaseWriter {
    let database = try SQLiteData.defaultDatabase()
    var migrator = DatabaseMigrator()
    OME.DatabaseMigrations.register(into: &migrator)
    try migrator.migrate(database)
    return database
}

private func localID<Record>(_ string: String) -> OME.ID<Record> {
    OME.ID<Record>(.init(string))
}
