import ATProto
import ATProtoTypes
import Foundation
import OpenMusicEventLexicon
import SQLiteData

public enum SocialPostRecordEditing {
    public enum Error: Swift.Error, Equatable {
        case eventUnavailable
        case categoryUnavailable
        case postUnavailable
        case notAuthor
    }

    public struct Fields: Equatable, Sendable {
        public var title: String?
        public var text: String
        public var facets: [Social.Post.Facet]?
        public var embed: Social.Post.Embed?
        public var delivery: Social.Post.Delivery?

        public init(
            title: String? = nil,
            text: String,
            facets: [Social.Post.Facet]? = nil,
            embed: Social.Post.Embed? = nil,
            delivery: Social.Post.Delivery? = nil
        ) {
            self.title = title
            self.text = text
            self.facets = facets
            self.embed = embed
            self.delivery = delivery
        }

        fileprivate func apply(to post: inout Social.Post) {
            post.title = title
            post.text = text
            post.facets = facets
            post.embed = embed
            post.delivery = delivery.map(Open.known)
        }
    }

    public static func create(
        eventID: Event.ID,
        categoryID: Social.Category.ID?,
        author: DID,
        fields: Fields,
        createdAt: Date,
        in db: Database
    ) throws -> Social.Post.ID {
        let (event, category) = try graph(eventID: eventID, categoryID: categoryID, in: db)
        let authorRepository = ATProto.URI.Authority.did(author)
        let existing = try Social.Post.all.fetchAll(db)
            .filter { $0.id.authority == authorRepository }
        let previousKey = existing.map(\.id).compactMap(\.rkey)
            .max { $0.rawValue < $1.rawValue }
        let id = try CanonicalRecordID.next(
            collection: Social.Post.lexiconID,
            in: authorRepository,
            at: createdAt,
            after: previousKey
        )
        var post = try Social.Post(
            id: id,
            text: fields.text,
            event: eventID,
            category: categoryID,
            createdAt: timestamp(createdAt)
        )
        fields.apply(to: &post)
        try post.validateGraph(event: event, category: category)
        try Social.Post.insert { post }.execute(db)
        return id
    }

    public static func update(
        _ postID: Social.Post.ID,
        eventID: Event.ID,
        categoryID: Social.Category.ID?,
        author: DID,
        fields: Fields,
        updatedAt: Date,
        in db: Database
    ) throws {
        guard postID.authority == .did(author) else { throw Error.notAuthor }
        let (event, category) = try graph(eventID: eventID, categoryID: categoryID, in: db)
        guard var post = try Social.Post.find(postID).fetchOne(db),
              post.event == eventID else { throw Error.postUnavailable }
        post.category = categoryID
        post.updatedAt = timestamp(updatedAt)
        fields.apply(to: &post)
        try post.validateGraph(event: event, category: category)
        try Social.Post.upsert { post }.execute(db)
    }

    public static func delete(
        _ postID: Social.Post.ID,
        author: DID,
        in db: Database
    ) throws {
        guard postID.authority == .did(author) else { throw Error.notAuthor }
        guard try Social.Post.find(postID).fetchOne(db) != nil else {
            throw Error.postUnavailable
        }
        let categories = try Social.Category.all.fetchAll(db)
        for var category in categories where category.pinnedPosts?.contains(postID) == true {
            let remaining = category.pinnedPosts?.filter { $0 != postID }
            category.pinnedPosts = remaining?.isEmpty == true ? nil : remaining
            try category.validateReferences()
            try Social.Category.upsert { category }.execute(db)
        }
        try Social.Post.find(postID).delete().execute(db)
    }

    private static func graph(
        eventID: Event.ID,
        categoryID: Social.Category.ID?,
        in db: Database
    ) throws -> (Event, Social.Category?) {
        guard let event = try Event.find(eventID).fetchOne(db) else {
            throw Error.eventUnavailable
        }
        guard let categoryID else { return (event, nil) }
        guard let category = try Social.Category.find(categoryID).fetchOne(db),
              category.event == eventID else {
            throw Error.categoryUnavailable
        }
        return (event, category)
    }

    private static func timestamp(_ date: Date) -> ATProto.DateTime {
        ATProto.DateTime(rawValue: ISO8601DateFormatter().string(from: date))
    }
}
