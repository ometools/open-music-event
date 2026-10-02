import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@Suite
struct CanonicalSocialPostEditingTests {
    @Test
    func accountOwnedPostKeepsItsIdentityThroughEditsAndOnlyItsAuthorCanDeleteIt() throws {
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
            timeZone: #require(TimeZone(identifier: "America/Denver"))
        )
        try database.write { try Event.insert { event }.execute($0) }
        let categoryID = try database.write { db in
            try SocialCategoryRecordEditing.create(
                eventID: eventID,
                fields: .init(
                    name: "Announcements",
                    defaultNotificationState: .known(.subscribed),
                    notificationsRequired: false
                ),
                createdAt: try Date("2026-09-02T18:00:00Z", strategy: .iso8601),
                in: db
            )
        }

        let author = try #require(DID("did:plc:contributor"))
        let organizer = try #require(DID("did:plc:organizer"))
        let postID = try database.write { db in
            try SocialPostRecordEditing.create(
                eventID: eventID,
                categoryID: categoryID,
                author: author,
                fields: .init(
                    title: "Gates open",
                    text: "Welcome to the woods",
                    delivery: .standard
                ),
                createdAt: try Date("2026-09-05T20:00:00Z", strategy: .iso8601),
                in: db
            )
        }
        let original = try database.read {
            try #require(try Social.Post.find(postID).fetchOne($0))
        }
        #expect(postID.authority == .did(author))
        #expect(original.event == eventID)
        #expect(original.category == categoryID)
        #expect(original.delivery == .known(.standard))
        try database.write { db in
            var category = try #require(try Social.Category.find(categoryID).fetchOne(db))
            category.pinnedPosts = [postID]
            try Social.Category.upsert { category }.execute(db)
        }

        try database.write { db in
            try SocialPostRecordEditing.update(
                postID,
                eventID: eventID,
                categoryID: categoryID,
                author: author,
                fields: .init(text: "The gates are open", delivery: .silent),
                updatedAt: try Date("2026-09-05T20:05:00Z", strategy: .iso8601),
                in: db
            )
        }
        let updated = try database.read {
            try #require(try Social.Post.find(postID).fetchOne($0))
        }
        #expect(updated.id == original.id)
        #expect(updated.createdAt == original.createdAt)
        #expect(updated.title == nil)
        #expect(updated.text == "The gates are open")
        #expect(updated.delivery == .known(.silent))
        #expect(updated.updatedAt == "2026-09-05T20:05:00Z")

        #expect(throws: ValidationError.self) {
            try database.write { db in
                try SocialPostRecordEditing.update(
                    postID,
                    eventID: eventID,
                    categoryID: categoryID,
                    author: author,
                    fields: .init(text: "Emergency", delivery: .emergency),
                    updatedAt: try Date("2026-09-05T20:10:00Z", strategy: .iso8601),
                    in: db
                )
            }
        }
        #expect(throws: SocialPostRecordEditing.Error.notAuthor) {
            try database.write { db in
                try SocialPostRecordEditing.delete(postID, author: organizer, in: db)
            }
        }
        #expect(try database.read { try Social.Post.find(postID).fetchOne($0) } == updated)

        try database.write { db in
            try SocialPostRecordEditing.delete(postID, author: author, in: db)
        }
        #expect(try database.read { try Social.Post.find(postID).fetchOne($0) } == nil)
        #expect(try database.read {
            try Social.Category.find(categoryID).fetchOne($0)?.pinnedPosts
        } == nil)
    }
}
