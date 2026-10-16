import ComposableNotifications
import OpenMusicEventAppEventViewer
import OpenMusicEventAppRouting
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData

extension ApplicationNotificationIndicatorSourceID {
    public static let unreadCommsPosts = Self(rawValue: "comms.unread-posts")
}

extension ApplicationNotificationIndicatorSummary {
    public func count(for eventID: Event.ID) -> Int {
        count(for: eventID.description)
    }
}

/// One user-facing indicator domain that can contribute to the application badge.
///
/// Delivery sources and indicator domains are deliberately independent: an adapter can use
/// installed event IDs, query application-wide state, or ignore event installation entirely.
struct ApplicationNotificationIndicatorAdapter: Sendable {
    let sourceID: ApplicationNotificationIndicatorSourceID
    let fetchContributions: @Sendable (
        _ installedEventIDs: Set<Event.ID>,
        _ database: Database
    ) throws -> [ApplicationNotificationIndicatorContribution]

    static let unreadCommsPosts = Self(
        sourceID: .unreadCommsPosts,
        fetchContributions: { installedEventIDs, database in
            let commsCounts = try CommsUnreadPostCounts.fetch(
                eventIDs: installedEventIDs,
                in: database
            )
            return installedEventIDs.compactMap { eventID in
                let count = commsCounts.count(forEvent: eventID)
                guard count > 0 else { return nil }
                let eventSourceID = NotificationSource.ID(
                    rawValue: eventID.description
                )
                return ApplicationNotificationIndicatorContribution(
                    id: .init(
                        sourceID: .unreadCommsPosts,
                        scopeID: eventSourceID.rawValue
                    ),
                    count: count
                )
            }
        }
    )

    /// Add future Comms or non-Comms domains here without changing badge aggregation.
    static let liveValues: [Self] = [.unreadCommsPosts]
}

struct ApplicationNotificationIndicatorSummaryRequest: FetchKeyRequest {
    func fetch(_ database: Database) throws -> ApplicationNotificationIndicatorSummary {
        let installedEventIDs = Set(
            try InstalledEvent.all.fetchAll(database).map(\.id)
        )
        let contributions = try ApplicationNotificationIndicatorAdapter.liveValues.flatMap {
            adapter in
            let contributions = try adapter.fetchContributions(installedEventIDs, database)
            precondition(
                contributions.allSatisfy { $0.id.sourceID == adapter.sourceID },
                "An application notification indicator adapter returned another domain's contribution."
            )
            return contributions
        }
        .sorted {
            ($0.id.sourceID.rawValue, $0.id.scopeID)
                < ($1.id.sourceID.rawValue, $1.id.scopeID)
        }
        return ApplicationNotificationIndicatorSummary(contributions: contributions)
    }
}

struct ApplicationNotificationSubscriptionsRequest: FetchKeyRequest {
    func fetch(_ database: Database) throws -> Set<NotificationSubscription> {
        let installedEventIDs = Set(
            try InstalledEvent.all.fetchAll(database).map(\.id)
        )
        let preferencesByChannelID = Dictionary(
            uniqueKeysWithValues: try ChannelPreferences.all
                .fetchAll(database)
                .map { ($0.id, $0) }
        )
        var subscriptions = Set(
            installedEventIDs.map { eventID in
                NotificationSubscription(
                    sourceID: NotificationSource.ID(
                        rawValue: eventID.description
                    )
                )
            }
        )
        let channelSubscriptions = try Social.Category.all
            .fetchAll(database)
            .compactMap { channel -> NotificationSubscription? in
                let eventID = channel.event
                guard installedEventIDs.contains(eventID),
                      channel.notificationsAreEnabled(
                          preference: preferencesByChannelID[channel.id]
                      )
                else { return nil }
                return NotificationSubscription(
                    sourceID: NotificationSource.ID(
                        rawValue: AppRoute.event(
                            eventID,
                            .channel(channel.id)
                        )
                        .notificationRoute
                    )
                )
            }
        subscriptions.formUnion(channelSubscriptions)
        return subscriptions
    }
}
