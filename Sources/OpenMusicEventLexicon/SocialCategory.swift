import ATProto
import ATProtoTypes
import ATProtoSQLite
import Foundation
import SQLiteData

extension Social {
    @Table("social.ome.category")
    @Lexicon("social.ome.category", type: .record(key: .tid), description: "An organizer-owned category for posts about one event, including its presentation and notification policy. Attendee subscription choices are separate from this public policy.")
    public struct Category: RecordCodable, Equatable {
        @LexiconIgnored
        @Column(primaryKey: true)
        public let id: ATProto.URI

        @LexiconIgnored
        public var cid: ATProto.CID? = nil

        @LexiconField(description: "The DID-based events.openmusic.event record that owns this category.")
        public var event: Event.ID

        @LexiconField(description: "The attendee-facing category name.", minLength: 1, maxLength: 5_000, maxGraphemes: 500)
        public var name: String

        @LexiconField(description: "Client-declared creation timestamp, preserved through category edits.")
        public var createdAt: ATProto.DateTime

        @LexiconField(description: "The organizer's explanation of the posts that belong in this category.", maxLength: 30_000, maxGraphemes: 3_000)
        public var description: String? = nil

        @LexiconField(description: "Ordered category media, including an icon or header image.")
        @Column(as: [Open<OME.Media>].JSONRepresentation?.self)
        public var media: [Open<OME.Media>]? = nil

        @LexiconField(description: "Posts the organizer has pinned in this category, in display order.", minLength: 1)
        @Column(as: [ATProto.URI].JSONRepresentation?.self)
        public var pinnedPosts: [Social.Post.ID]? = nil

        @LexiconField(description: "The organizer's default subscription choice for attendees who have not made a choice. Omitted means unspecified.")
        public var defaultNotificationState: Open<NotificationState>? = nil

        @LexiconField(description: "Whether this category requires subscription within the event experience. True implies subscribed and cannot be paired with an unsubscribed default. This policy does not grant notification delivery authority or override device permissions.")
        public var notificationsRequired: Bool? = nil

        public func validateReferences() throws {
            try LexiconCoding.validateRecordURI(id, type: Self.self)
            try LexiconCoding.validateRecordURI(event, type: Event.self)
            guard id.authority == event.authority else {
                throw ValidationError("A category must be published in its event's repository", path: ["event"])
            }
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError("A category name cannot be blank", path: ["name"])
            }
            if notificationsRequired == true, defaultNotificationState == .known(.unsubscribed) {
                throw ValidationError("Required notifications cannot have an unsubscribed default", path: ["defaultNotificationState"])
            }
            var seenPinnedPosts: Set<Social.Post.ID> = []
            for (index, postID) in (pinnedPosts ?? []).enumerated() {
                try LexiconCoding.validateRecordURI(postID, type: Social.Post.self)
                guard seenPinnedPosts.insert(postID).inserted else {
                    throw ValidationError("A pinned post cannot be repeated", path: ["pinnedPosts", String(index)])
                }
            }
            for (index, item) in (media ?? []).enumerated() {
                if case .known(.image(let image)) = item {
                    do { try image.validateForPublication() }
                    catch let error as ValidationError {
                        throw ValidationError(error.reason, path: ["media", String(index)] + error.path)
                    }
                }
            }
            _ = try encodeLexicon()
        }

        public func validateGraph(event: Event) throws {
            try validateReferences()
            try event.validateReferences()
            guard self.event == event.id else {
                throw ValidationError("The category belongs to another event", path: ["event"])
            }
            guard event.categories?.contains(id) == true else {
                throw ValidationError("The event must list its category", path: ["event"])
            }
        }
    }
}

extension Social.Category {
    @Lexicon("social.ome.defs#notificationState", type: .string, description: "A known default category subscription state. Other states may be introduced by extensions.")
    public enum NotificationState: String, Equatable, Sendable, SQLiteType {
        case subscribed
        case unsubscribed
    }
}
