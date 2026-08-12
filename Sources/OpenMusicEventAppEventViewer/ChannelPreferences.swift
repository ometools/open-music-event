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
}
