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
