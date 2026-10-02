import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@Suite
struct CanonicalSocialCategoryEditingTests {
    @Test
    func addingPinnedPostsPreservesAnExistingCategory() throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        EventRecordMigrations.register(into: &migrator)
        try migrator.migrate(
            database,
            upTo: "Create canonical Event related record storage"
        )

        let categoryID = try #require(Social.Category.ID(
            "at://did:plc:organizer/social.ome.category/3mrdbziccpcak"
        ))
        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO "social.ome.category"
                    ("id", "event", "name", "createdAt", "defaultNotificationState", "notificationsRequired")
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    categoryID.description,
                    eventID.description,
                    "Announcements",
                    "2026-09-02T18:00:00Z",
                    "subscribed",
                    false,
                ]
            )
        }

        try migrator.migrate(database)
        let category = try database.read {
            try #require(try Social.Category.find(categoryID).fetchOne($0))
        }
        #expect(category.event == eventID)
        #expect(category.name == "Announcements")
        #expect(category.defaultNotificationState == .known(.subscribed))
        #expect(category.pinnedPosts == nil)
    }

    @Test
    func categoryPolicyEditsPreserveIdentityAndPostsPreventDeletion() throws {
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
                    defaultNotificationState: .unsubscribed,
                    notificationsRequired: false
                ),
                createdAt: try Date("2026-09-02T18:00:00Z", strategy: .iso8601),
                in: db
            )
        }
        let initial = try database.read {
            try #require(try Social.Category.find(categoryID).fetchOne($0))
        }
        #expect(initial.defaultNotificationState == .known(.unsubscribed))
        #expect(try database.read { try Event.find(eventID).fetchOne($0)?.categories } == [categoryID])

        try database.write { db in
            try SocialCategoryRecordEditing.update(
                categoryID,
                eventID: eventID,
                fields: .init(
                    name: "Important updates",
                    description: "Organizer announcements",
                    defaultNotificationState: .unsubscribed,
                    notificationsRequired: true
                ),
                in: db
            )
        }
        let updated = try database.read {
            try #require(try Social.Category.find(categoryID).fetchOne($0))
        }
        #expect(updated.id == initial.id)
        #expect(updated.createdAt == initial.createdAt)
        #expect(updated.name == "Important updates")
        #expect(updated.notificationsRequired == true)
        #expect(updated.defaultNotificationState == .known(.subscribed))

        let post = try Social.Post(
            id: #require(Social.Post.ID(
                "at://did:plc:organizer/social.ome.post/3mrdbziccpcak"
            )),
            text: "The gates are open",
            event: eventID,
            category: categoryID,
            createdAt: "2026-09-05T20:00:00Z"
        )
        try database.write { try Social.Post.insert { post }.execute($0) }
        #expect(throws: SocialCategoryRecordEditing.Error.categoryInUse) {
            try database.write {
                try SocialCategoryRecordEditing.delete(categoryID, eventID: eventID, in: $0)
            }
        }
        #expect(try database.read { try Social.Category.find(categoryID).fetchOne($0) } == updated)

        try database.write { db in
            try Social.Post.find(post.id).delete().execute(db)
            try SocialCategoryRecordEditing.delete(categoryID, eventID: eventID, in: db)
        }
        #expect(try database.read { try Social.Category.find(categoryID).fetchOne($0) } == nil)
        #expect(try database.read { try Event.find(eventID).fetchOne($0)?.categories } == nil)
    }

    @Test
    func pinnedPostsKeepOrderAndRejectPostsFromAnotherCategory() throws {
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
        let categoryIDs = try database.write { db in
            let general = try SocialCategoryRecordEditing.create(
                eventID: eventID,
                fields: .init(name: "General", defaultNotificationState: .subscribed, notificationsRequired: false),
                createdAt: try Date("2026-09-02T18:00:00Z", strategy: .iso8601),
                in: db
            )
            let safety = try SocialCategoryRecordEditing.create(
                eventID: eventID,
                fields: .init(name: "Safety", defaultNotificationState: .subscribed, notificationsRequired: true),
                createdAt: try Date("2026-09-02T18:00:01Z", strategy: .iso8601),
                in: db
            )
            return (general, safety)
        }
        let firstID = try #require(Social.Post.ID(
            "at://did:plc:organizer/social.ome.post/3mrdbziccpcak"
        ))
        let secondID = try #require(Social.Post.ID(
            "at://did:plc:organizer/social.ome.post/3mrdbziccpcal"
        ))
        let otherID = try #require(Social.Post.ID(
            "at://did:plc:organizer/social.ome.post/3mrdbziccpcam"
        ))
        let posts = [
            try Social.Post(id: firstID, text: "First", event: eventID, category: categoryIDs.0, createdAt: "2026-09-03T12:00:00Z"),
            try Social.Post(id: secondID, text: "Second", event: eventID, category: categoryIDs.0, createdAt: "2026-09-03T12:01:00Z"),
            try Social.Post(id: otherID, text: "Other", event: eventID, category: categoryIDs.1, createdAt: "2026-09-03T12:02:00Z"),
        ]
        try database.write { try Social.Post.insert { posts }.execute($0) }

        try database.write { db in
            try SocialCategoryRecordEditing.setPinnedPosts(
                [secondID, firstID], categoryID: categoryIDs.0, eventID: eventID, in: db
            )
        }
        #expect(try database.read { try Social.Category.find(categoryIDs.0).fetchOne($0)?.pinnedPosts }
            == [secondID, firstID])

        #expect(throws: SocialCategoryRecordEditing.Error.postUnavailable) {
            try database.write { db in
                try SocialCategoryRecordEditing.setPinnedPosts(
                    [otherID], categoryID: categoryIDs.0, eventID: eventID, in: db
                )
            }
        }
        #expect(try database.read { try Social.Category.find(categoryIDs.0).fetchOne($0)?.pinnedPosts }
            == [secondID, firstID])

        try database.write { db in
            try SocialCategoryRecordEditing.setPinnedPosts(
                [], categoryID: categoryIDs.0, eventID: eventID, in: db
            )
        }
        #expect(try database.read { try Social.Category.find(categoryIDs.0).fetchOne($0)?.pinnedPosts }
            == nil)
    }
}
