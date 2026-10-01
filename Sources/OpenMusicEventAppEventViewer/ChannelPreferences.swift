import OpenMusicEventLexicon
import ATProtoSQLite
import SQLiteData

@Table("channelPreferences")
public struct ChannelPreferences: Equatable, Sendable, Identifiable {
    public init(
        id: Social.Category.ID,
        notificationState: Social.Category.NotificationState
    ) {
        self.id = id
        self.notificationState = notificationState
    }

    public var id: Social.Category.ID
    public var notificationState: Social.Category.NotificationState
}

extension Social.Category {
    public func effectiveNotificationState(
        preference: ChannelPreferences?
    ) -> Social.Category.NotificationState {
        notificationsRequired == true
            ? .subscribed
            : preference?.notificationState
                ?? (defaultNotificationState == .known(.unsubscribed) ? .unsubscribed : .subscribed)
    }

    public func notificationsAreEnabled(
        preference: ChannelPreferences?
    ) -> Bool {
        effectiveNotificationState(preference: preference) == .subscribed
    }
}

@Table("commsPostReads")
public struct CommsPostRead: Equatable, Sendable, Identifiable {
    public init(id: Social.Post.ID) {
        self.id = id
    }

    public let id: Social.Post.ID

    public static func setRead(
        _ isRead: Bool,
        postID: Social.Post.ID,
        in database: Database
    ) throws {
        if isRead {
            try Self.upsert { Self(id: postID) }.execute(database)
        } else {
            try Self.find(postID).delete().execute(database)
        }
    }

    public static func setRead(
        _ isRead: Bool,
        channelID: Social.Category.ID,
        in database: Database
    ) throws {
        if isRead {
            let posts = try Social.Post
                .where { $0.category.eq(channelID) }
                .fetchAll(database)
            for post in posts {
                try Self.upsert { Self(id: post.id) }.execute(database)
            }
        } else {
            let posts = try Social.Post
                .where { $0.category.eq(channelID) }
                .fetchAll(database)
            for post in posts {
                try Self.find(post.id).delete().execute(database)
            }
        }
    }

    public static func setRead(
        _ isRead: Bool,
        eventID: Event.ID,
        in database: Database
    ) throws {
        if isRead {
            let posts = try Social.Post
                .where { $0.event.eq(eventID) }
                .fetchAll(database)
            for post in posts {
                try Self.upsert { Self(id: post.id) }.execute(database)
            }
        } else {
            let posts = try Social.Post
                .where { $0.event.eq(eventID) }
                .fetchAll(database)
            for post in posts {
                try Self.find(post.id).delete().execute(database)
            }
        }
    }
}
