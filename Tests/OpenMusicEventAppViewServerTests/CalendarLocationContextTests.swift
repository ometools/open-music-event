import ATProto
import CustomDump
import Foundation
import GRDB
import OpenMusicEventLexicon
import SQLiteData
import Testing

@testable import OpenMusicEventAppViewServer

@Suite(AppViewTestTime()) struct CalendarLocationContextTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let catalog = ATProto.NSID("community.lexicon.calendar.event")

    @Test func `browse keeps venue city and publisher and infers the local zone without rewriting source data`() throws {
        let db = try DatabaseQueue()
        let store = try OpenMusicEventAppViewStore(database: db)
        var event = OME.CalendarEvent(uri: ATProto.URI("at://did:plc:venue/community.lexicon.calendar.event/concert")!,
            name: "Concert", startsAt: now.addingTimeInterval(100), createdAt: now,
            locations: [.init(name: "Unmapped meeting point"),
                        .init(name: "Labor Temple", locality: "Bozeman", region: "MT", latitude: "45.68", longitude: "-111.04")],
            organizer: .init(id: DID("did:plc:venue")!), source: .init(collection: catalog))
        try db.write { database in
            try CalendarEventBrowseProjection.upsert(event, now: now, in: database)
            try CalendarPublisher.where { $0.did.eq("did:plc:venue") }.update {
                $0.displayName = #bind("Venue Calendar")
                $0.avatarURL = #bind("https://cdn.bsky.app/img/avatar/plain/venue")
            }.execute(database)
        }
        let row = try #require(try store.browseEventSummaries(.init(catalogs: [catalog]), now: now).events.first)
        expectNoDifference(row.locationSummary, "Labor Temple")
        expectNoDifference(row.locality, "Bozeman")
        expectNoDifference(row.region, "MT")
        expectNoDifference(row.timeZoneIdentifier, "America/Denver")
        #expect(row.country?.contains("United States") == true)
        expectNoDifference(row.publisherName, "Venue Calendar")
        expectNoDifference(row.publisherAvatarURL, "https://cdn.bsky.app/img/avatar/plain/venue")
        let original = try db.read { try CalendarEventBrowseProjection.find(event.uri.description).select(\.event).fetchOne($0) }
        expectNoDifference(try JSONDecoder().decode(OME.CalendarEvent.self, from: #require(original)).timeZoneIdentifier, nil)
        let detail = try #require(try store.calendarEvent(uri: event.uri, appViewHost: "localhost"))
        expectNoDifference(detail.timeZoneIdentifier, "America/Denver")

        // The same record moves: cached context follows the new coordinates.
        event.locations = [.init(name: "Comedy Square", locality: "Bengaluru", latitude: "12.91", longitude: "77.64")]
        try db.write { try CalendarEventBrowseProjection.upsert(event, now: now, in: $0) }
        let moved = try #require(try store.browseEventSummaries(.init(catalogs: [catalog]), now: now).events.first)
        #expect(["Asia/Kolkata", "Asia/Calcutta"].contains(moved.timeZoneIdentifier ?? ""))
        expectNoDifference(moved.country, "India")

        // Explicit source information wins over geographic inference.
        event.timeZoneIdentifier = "Europe/London"
        event.locations[0].country = "Explicit country"
        try db.write { try CalendarEventBrowseProjection.upsert(event, now: now, in: $0) }
        let explicit = try #require(try store.browseEventSummaries(.init(catalogs: [catalog]), now: now).events.first)
        expectNoDifference(explicit.timeZoneIdentifier, "Europe/London")
        expectNoDifference(explicit.country, "Explicit country")

        // Removing the location never leaks the old inferred location into the row.
        event.timeZoneIdentifier = nil
        event.locations = []
        try db.write { try CalendarEventBrowseProjection.upsert(event, now: now, in: $0) }
        let unlocated = try #require(try store.browseEventSummaries(.init(catalogs: [catalog]), now: now).events.first)
        expectNoDifference(unlocated.timeZoneIdentifier, nil)
        expectNoDifference(unlocated.country, nil)
        expectNoDifference(unlocated.locationSummary, nil)
    }

    @Test func `migration backfills distinct coordinates without modifying existing rows and rolls back failed writes`() throws {
        let db = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("Existing coordinate projection fixture") { database in
            try #sql("""
                CREATE TABLE \(quote: CalendarEventBrowseProjection.tableName) (latitude REAL, longitude REAL, sentinel TEXT)
                """).execute(database)
            try #sql("""
                INSERT INTO \(quote: CalendarEventBrowseProjection.tableName) VALUES
                  (50.12,-5.54,'keep me'),(50.12,-5.54,'keep me too'),(NULL,NULL,'unlocated')
                """).execute(database)
        }
        try migrator.migrate(db)
        CalendarLocationContext.registerMigration(into: &migrator)
        try migrator.migrate(db)
        try db.read { database in
            expectNoDifference(try CalendarLocationContext.all.fetchCount(database), 1)
            let context = try #require(try CalendarLocationContext.all.fetchOne(database))
            expectNoDifference(context.timeZoneIdentifier, "Europe/London")
            expectNoDifference(try String.fetchAll(database, sql: "SELECT sentinel FROM \"\(CalendarEventBrowseProjection.tableName)\" ORDER BY rowid"),
                               ["keep me", "keep me too", "unlocated"])
        }
        enum Rollback: Error { case requested }
        #expect(throws: Rollback.self) {
            try db.write { database in
                try CalendarLocationContext.ensure(latitude: 40, longitude: -105, in: database)
                throw Rollback.requested
            }
        }
        expectNoDifference(try db.read { try CalendarLocationContext.all.fetchCount($0) }, 1)
    }
}
