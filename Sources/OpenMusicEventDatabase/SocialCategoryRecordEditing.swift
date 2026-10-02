import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventLexicon
import SQLiteData

public enum SocialCategoryRecordEditing {
    public enum Error: Swift.Error, Equatable {
        case eventUnavailable
        case categoryUnavailable
        case categoryInUse
        case postUnavailable
    }

    public struct Fields: Equatable, Sendable {
        public var name: String
        public var description: String?
        public var defaultNotificationState: Social.Category.NotificationState
        public var notificationsRequired: Bool

        public init(
            name: String,
            description: String? = nil,
            defaultNotificationState: Social.Category.NotificationState,
            notificationsRequired: Bool
        ) {
            self.name = name
            self.description = description
            self.defaultNotificationState = defaultNotificationState
            self.notificationsRequired = notificationsRequired
        }

        fileprivate func apply(to category: inout Social.Category) {
            category.name = name
            category.description = description
            category.defaultNotificationState = .known(
                notificationsRequired ? .subscribed : defaultNotificationState
            )
            category.notificationsRequired = notificationsRequired
        }
    }

    public static func create(
        eventID: Event.ID,
        fields: Fields,
        createdAt: Date,
        in db: Database
    ) throws -> Social.Category.ID {
        guard var event = try Event.find(eventID).fetchOne(db) else {
            throw Error.eventUnavailable
        }
        let existing = try Social.Category.all.fetchAll(db)
            .filter { $0.id.authority == eventID.authority }
        let previousKey = (existing.map(\.id) + (event.categories ?? []))
            .compactMap(\.rkey)
            .max { $0.rawValue < $1.rawValue }
        let id = try CanonicalRecordID.next(
            collection: Social.Category.lexiconID,
            in: eventID.authority,
            at: createdAt,
            after: previousKey
        )
        var category = try Social.Category(
            id: id,
            event: eventID,
            name: fields.name,
            createdAt: ATProto.DateTime(rawValue: ISO8601DateFormatter().string(from: createdAt))
        )
        fields.apply(to: &category)
        try category.validateReferences()
        try Social.Category.insert { category }.execute(db)
        event.categories = (event.categories ?? []) + [id]
        try event.validateReferences()
        try Event.upsert { event }.execute(db)
        return id
    }

    public static func update(
        _ categoryID: Social.Category.ID,
        eventID: Event.ID,
        fields: Fields,
        in db: Database
    ) throws {
        guard let event = try Event.find(eventID).fetchOne(db) else {
            throw Error.eventUnavailable
        }
        guard var category = try Social.Category.find(categoryID).fetchOne(db),
              category.event == eventID else {
            throw Error.categoryUnavailable
        }
        fields.apply(to: &category)
        try category.validateGraph(event: event)
        try Social.Category.upsert { category }.execute(db)
    }

    public static func delete(
        _ categoryID: Social.Category.ID,
        eventID: Event.ID,
        in db: Database
    ) throws {
        guard var event = try Event.find(eventID).fetchOne(db),
              let category = try Social.Category.find(categoryID).fetchOne(db),
              category.event == eventID else {
            throw Error.categoryUnavailable
        }
        let posts = try Social.Post.all.fetchAll(db)
        guard !posts.contains(where: { $0.category == categoryID }) else {
            throw Error.categoryInUse
        }
        try Social.Category.find(categoryID).delete().execute(db)
        let remaining = event.categories?.filter { $0 != categoryID }
        event.categories = remaining?.isEmpty == true ? nil : remaining
        try event.validateReferences()
        try Event.upsert { event }.execute(db)
    }

    public static func setPinnedPosts(
        _ postIDs: [Social.Post.ID],
        categoryID: Social.Category.ID,
        eventID: Event.ID,
        in db: Database
    ) throws {
        guard let event = try Event.find(eventID).fetchOne(db),
              var category = try Social.Category.find(categoryID).fetchOne(db),
              category.event == eventID else {
            throw Error.categoryUnavailable
        }
        let availableIDs = Set(
            try Social.Post.where { $0.category.eq(categoryID) }
                .fetchAll(db)
                .filter { $0.event == eventID }
                .map(\.id)
        )
        guard postIDs.allSatisfy(availableIDs.contains) else {
            throw Error.postUnavailable
        }
        category.pinnedPosts = postIDs.isEmpty ? nil : postIDs
        try category.validateGraph(event: event)
        try Social.Category.upsert { category }.execute(db)
    }
}
