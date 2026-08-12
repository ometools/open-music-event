import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData

@Selection
struct CommsPostIdentity: Sendable {
    let id: CommsPost.ID
}

public struct CommsUnreadPostCounts: Equatable, Sendable {
    public init(countsByEventID: [OMERecord.Event.ID: Int] = [:]) {
        self.countsByEventID = countsByEventID
    }

    public var countsByEventID: [OMERecord.Event.ID: Int]

    public func count(for eventID: OMERecord.Event.ID) -> Int {
        countsByEventID[eventID, default: 0]
    }

    public static func fetch(
        eventIDs: Set<OMERecord.Event.ID>,
        in database: Database
    ) throws -> Self {
        guard !eventIDs.isEmpty else { return Self() }

        let channels = try OMERecord.Channel.all.fetchAll(database)
        let preferences = try ChannelPreferences.all.fetchAll(database)
        let postIDs = try CommsPost
            .select { post -> CommsPostIdentity.Columns in
                CommsPostIdentity.Columns(id: post.id)
            }
            .fetchAll(database)
        let readPostIDs = Set(try CommsPostRead.all.fetchAll(database).map(\.id))
        let preferencesByChannelID = Dictionary(
            uniqueKeysWithValues: preferences.map { ($0.id, $0) }
        )

        let notificationEnabledChannelIDs = Set(
            channels.compactMap { channel -> OMERecord.Channel.ID? in
                let eventID = OMERecord.Event.ID(
                    organizerID: channel.id.organizerID,
                    eventID: channel.id.eventID
                )
                guard eventIDs.contains(eventID) else { return nil }
                return channel.notificationsAreEnabled(
                    preference: preferencesByChannelID[channel.id]
                ) ? channel.id : nil
            }
        )

        var countsByEventID: [OMERecord.Event.ID: Int] = [:]
        for postID in postIDs.map(\.id) {
            let channelRecordID = OMERecord.Channel.ID(
                organizerID: postID.organizerID,
                eventID: postID.eventID,
                channelID: postID.channelID
            )
            guard notificationEnabledChannelIDs.contains(channelRecordID) else { continue }
            guard !readPostIDs.contains(postID) else { continue }
            let eventID = OMERecord.Event.ID(
                organizerID: postID.organizerID,
                eventID: postID.eventID
            )
            countsByEventID[eventID, default: 0] += 1
        }
        return Self(countsByEventID: countsByEventID)
    }
}

struct CommsUnreadPostCountsRequest: FetchKeyRequest {
    let eventIDs: Set<OMERecord.Event.ID>

    func fetch(_ database: Database) throws -> CommsUnreadPostCounts {
        try CommsUnreadPostCounts.fetch(eventIDs: eventIDs, in: database)
    }
}
