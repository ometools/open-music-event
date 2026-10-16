import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData

public struct CommsUnreadPostCounts: Equatable, Sendable {
    public init(
        countsByChannelID: [Social.Category.ID: Int] = [:],
        notificationEnabledChannelIDs: Set<Social.Category.ID> = [],
        eventIDsByChannelID: [Social.Category.ID: Event.ID] = [:]
    ) {
        self.countsByChannelID = countsByChannelID
        self.notificationEnabledChannelIDs = notificationEnabledChannelIDs
        self.eventIDsByChannelID = eventIDsByChannelID
    }

    public var countsByChannelID: [Social.Category.ID: Int]
    public var notificationEnabledChannelIDs: Set<Social.Category.ID>
    public var eventIDsByChannelID: [Social.Category.ID: Event.ID]

    public func count(forCategory channelID: Social.Category.ID) -> Int {
        countsByChannelID[channelID, default: 0]
    }

    public func count(forEvent eventID: Event.ID) -> Int {
        var count = 0
        for (channelID, channelCount) in countsByChannelID {
            guard notificationEnabledChannelIDs.contains(channelID),
                  eventIDsByChannelID[channelID] == eventID
            else { continue }
            count += channelCount
        }
        return count
    }

    public static func fetch(
        eventIDs: Set<Event.ID>,
        in database: Database
    ) throws -> Self {
        guard !eventIDs.isEmpty else { return Self() }

        let channels = try Social.Category.all.fetchAll(database)
        let preferences = try ChannelPreferences.all.fetchAll(database)
        let posts = try Social.Post.all.fetchAll(database)
        let readPostIDs = Set(try CommsPostRead.all.fetchAll(database).map(\.id))
        let preferencesByChannelID = Dictionary(
            uniqueKeysWithValues: preferences.map { ($0.id, $0) }
        )

        let eventChannelIDs = Set(
            channels.compactMap { channel -> Social.Category.ID? in
                guard eventIDs.contains(channel.event) else { return nil }
                return channel.id
            }
        )
        let notificationEnabledChannelIDs = Set(
            channels.compactMap { channel -> Social.Category.ID? in
                guard eventChannelIDs.contains(channel.id) else { return nil }
                return channel.notificationsAreEnabled(
                    preference: preferencesByChannelID[channel.id]
                ) ? channel.id : nil
            }
        )

        var countsByChannelID: [Social.Category.ID: Int] = [:]
        for post in posts {
            guard let categoryID = post.category,
                  eventChannelIDs.contains(categoryID),
                  !readPostIDs.contains(post.id)
            else { continue }
            countsByChannelID[categoryID, default: 0] += 1
        }
        return Self(
            countsByChannelID: countsByChannelID,
            notificationEnabledChannelIDs: notificationEnabledChannelIDs,
            eventIDsByChannelID: Dictionary(
                uniqueKeysWithValues: channels.map { ($0.id, $0.event) }
            )
        )
    }
}

struct CommsUnreadPostCountsRequest: FetchKeyRequest {
    let eventIDs: Set<Event.ID>

    func fetch(_ database: Database) throws -> CommsUnreadPostCounts {
        try CommsUnreadPostCounts.fetch(eventIDs: eventIDs, in: database)
    }
}
