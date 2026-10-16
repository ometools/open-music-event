import OpenMusicEventDatabase
import ATProtoTypes
import ATProtoSQLite
import CustomDump
import Foundation
import OpenMusicEventLexicon
import SQLiteData
import Testing

@Suite
struct EventCommunicationStorageTests {
    typealias Event = OpenMusicEventLexicon.Event
    typealias Category = Social.Category

    @Test
    func `an organizer creates edits and clears a category without storing attendee preferences`() throws {
        let eventURI = try #require(ATProto.URI("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"))
        let categoryURI = try #require(ATProto.URI("at://did:plc:organizer/social.ome.category/3mrdbziccpcai"))
        let event = try Event(
            id: eventURI, name: "Wicked Woods", createdAt: "2026-09-01T12:00:00Z", timeZone: .gmt,
            categories: [categoryURI]
        )
        var category = try Category(
            id: categoryURI, event: eventURI, name: "Emergencies", createdAt: "2026-09-01T12:00:00Z",
            description: "Official safety updates",
            media: [.known(.image(.init(
                source: .known(.url(#require(URL(string: "https://example.com/emergency-icon.png")))),
                role: .known(.icon(.init()))
            )))],
            defaultNotificationState: .known(.subscribed),
            notificationsRequired: true
        )
        let pinnedPostURI = try #require(ATProto.URI("at://did:plc:contributor/social.ome.post/3mrdbziccpcaj"))
        category.pinnedPosts = [pinnedPostURI]
        try category.validateGraph(event: event)
        let payload = try category.encodeLexicon()
        #expect(payload.object?["defaultNotificationState"] == "subscribed")
        #expect(payload.object?["notificationsRequired"] == true)
        #expect(payload.object?["pinnedPosts"] == .array([.string(pinnedPostURI.description)]))
        #expect(payload.object?["id"] == nil)
        #expect(payload.object?["subscriber"] == nil)
        expectNoDifference(try Category.decodeLexicon(payload, metadata: .init(uri: categoryURI)), category)

        // The same public model owns database storage and record encoding.
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        try database.write { db in
            try Category.insert { category }.execute(db)
        }
        expectNoDifference(try database.read { try Category.find(categoryURI).fetchOne($0) }, category)

        // Editing ordinary content preserves an unknown future subscription state.
        category.name = "Safety updates"
        category.defaultNotificationState = .unknown("digest")
        category.notificationsRequired = false
        category.description = nil
        category.media = nil
        try category.validateGraph(event: event)
        try database.write { db in
            try Category.upsert { category }.execute(db)
        }
        let reopened = try database.read { db in try #require(try Category.find(categoryURI).fetchOne(db)) }
        expectNoDifference(reopened, category)
        #expect(try reopened.encodeLexicon().object?["defaultNotificationState"] == "digest")
        #expect(try reopened.encodeLexicon().object?["media"] == nil)
        #expect(reopened.pinnedPosts == [pinnedPostURI])

        // Deleting the category leaves removal from Event.categories to the graph operation.
        try database.write { try Category.find(categoryURI).delete().execute($0) }
        #expect(try database.read { try Category.all.fetchCount($0) } == 0)
    }
}
