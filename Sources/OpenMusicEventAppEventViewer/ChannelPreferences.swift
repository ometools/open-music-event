import SQLiteData

@Table("channelPreferences")
public struct ChannelPreferences: Equatable, Sendable, Identifiable {
    public init(
        id: OMERecord.Channel.ID,
        notificationState: OMERecord.Channel.NotificationState
    ) {
        self.id = id
        self.notificationState = notificationState
    }

    public var id: OMERecord.Channel.ID
    public var notificationState: OMERecord.Channel.NotificationState
}

extension OMERecord.Channel {
    public func effectiveNotificationState(
        preference: ChannelPreferences?
    ) -> OMERecord.Channel.NotificationState {
        notificationsRequired
            ? .subscribed
            : preference?.notificationState ?? defaultNotificationState
    }

    public func notificationsAreEnabled(
        preference: ChannelPreferences?
    ) -> Bool {
        effectiveNotificationState(preference: preference) == .subscribed
    }
}

@Table("commsPostReads")
public struct CommsPostRead: Equatable, Sendable, Identifiable {
    public init(id: CommsPost.ID) {
        self.id = id
    }

    public let id: CommsPost.ID

    public static func setRead(
        _ isRead: Bool,
        postID: CommsPost.ID,
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
        channelID: OMERecord.Channel.ID,
        in database: Database
    ) throws {
        if isRead {
            let posts = try CommsPost
                .where { $0.id.organizerID.eq(channelID.organizerID) }
                .where { $0.id.eventID.eq(channelID.eventID) }
                .where { $0.id.channelID.eq(channelID.channelID) }
                .fetchAll(database)
            for post in posts {
                try Self.upsert { Self(id: post.id) }.execute(database)
            }
        } else {
            try Self
                .where { $0.id.organizerID.eq(channelID.organizerID) }
                .where { $0.id.eventID.eq(channelID.eventID) }
                .where { $0.id.channelID.eq(channelID.channelID) }
                .delete()
                .execute(database)
        }
    }

    public static func setRead(
        _ isRead: Bool,
        eventID: OMERecord.Event.ID,
        in database: Database
    ) throws {
        if isRead {
            let posts = try CommsPost
                .where { $0.id.organizerID.eq(eventID.organizerID) }
                .where { $0.id.eventID.eq(eventID.eventID) }
                .fetchAll(database)
            for post in posts {
                try Self.upsert { Self(id: post.id) }.execute(database)
            }
        } else {
            try Self
                .where { $0.id.organizerID.eq(eventID.organizerID) }
                .where { $0.id.eventID.eq(eventID.eventID) }
                .delete()
                .execute(database)
        }
    }
}
