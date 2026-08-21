import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
import SwiftUI
import Tagged

struct CommunicationChannelRow: Equatable, Identifiable, Sendable {
    let channel: OMERecord.Channel
    let preference: ChannelPreferences?
    let unreadPostCount: Int

    var id: OMERecord.Channel.ID { channel.id }

    var effectiveNotificationState: OMERecord.Channel.NotificationState {
        channel.effectiveNotificationState(preference: preference)
    }

    var notificationSystemImage: String {
        channel.notificationsRequired
            ? "bell.badge"
            : effectiveNotificationState.systemImage
    }
}

@Feature
public struct ChannelDeleteConfirmation: Prompt {
    public struct State: Identifiable {
        public init(channelID: OMERecord.ID<OMERecord.Channel>) {
            self.channelID = channelID
        }

        public let channelID: OMERecord.ID<OMERecord.Channel>
        public var id: OMERecord.ID<OMERecord.Channel> { channelID }
    }

    public enum Action {
        case deleteButtonTapped(OMERecord.ID<OMERecord.Channel>)
    }
}

@Feature
public struct CommunicationsViewer {
    public init() {}

    public struct State {
        public let eventID: OMERecord.Event.ID
        @SharedReader(.defaultAuthoringGrant)
        public var authoringGrant: AuthoringGrant?
        @SharedReader(.devicePermissions)
        public var permissions: DevicePermissions
        public var destination: Destination.State?
        public var errorMessage: String?

        @FetchAll public var channels: [OMERecord.Channel]
        @FetchAll public var channelPreferences: [ChannelPreferences]
        @FetchOne public var event: OMERecord.Event?
        @Fetch public var unreadPostCounts: CommsUnreadPostCounts

        public init(
            eventID: OMERecord.Event.ID,
            destination: Destination.State? = nil
        ) {
            self.eventID = eventID
            self.destination = destination
            _channels = FetchAll(CommunicationsViewer.channelsQuery(eventID: eventID))
            _channelPreferences = FetchAll(CommunicationsViewer.channelPreferencesQuery(eventID: eventID))
            _event = FetchOne(OMERecord.Event.where { $0.id.eq(eventID) })
            _unreadPostCounts = Fetch(
                wrappedValue: CommsUnreadPostCounts(),
                CommsUnreadPostCountsRequest(eventIDs: [eventID])
            )
        }

        var channelRows: [CommunicationChannelRow] {
            let preferencesByID = Dictionary(
                uniqueKeysWithValues: channelPreferences.map { ($0.id, $0) }
            )
            return channels.map { channel in
                CommunicationChannelRow(
                    channel: channel,
                    preference: preferencesByID[channel.id],
                    unreadPostCount: unreadPostCounts.count(for: channel.id)
                )
            }
        }

        var hasContent: Bool {
            event != nil && (
                shouldShowNotificationPrompt
                    || !(event?.reportingLinks ?? []).isEmpty
                    || !channels.isEmpty
            )
        }

        var shouldShowNotificationPrompt: Bool {
            !permissions.notificationsAreAllowed
        }

        public var canManageChannels: Bool {
            authoringGrant?.access.canEditContent == true
        }

        public var unreadPostCount: Int {
            unreadPostCounts.count(for: eventID)
        }
    }

    public enum Action {
        case addChannelButtonTapped
        case channelButtonTapped(OMERecord.ID<OMERecord.Channel>)
        case deleteChannelButtonTapped(OMERecord.ID<OMERecord.Channel>)
        case destination(Destination.Action)
        case editChannelButtonTapped(OMERecord.Channel)
        case markAllPostsReadButtonTapped(OMERecord.Channel.ID)
        case markAllPostsUnreadButtonTapped(OMERecord.Channel.ID)
        case notificationPermissionButtonTapped
        case notificationStateButtonTapped(
            OMERecord.Channel.ID,
            OMERecord.Channel.NotificationState
        )
        case openNotificationSettingsButtonTapped
    }

    @Feature
    public enum Destination {
        case channelForm(ChannelForm)
        case channelDetail(CommunicationChannelDetail)
        case deleteChannelConfirmation(ChannelDeleteConfirmation)
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.devicePermissions) var devicePermissions

    static func channelsQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<OMERecord.Channel> {
        OMERecord.Channel
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
            .order { ($0.sortIndex.asc(nulls: .last), $0.name.collate(.nocase)) }
    }

    static func channelPreferencesQuery(
        eventID: OMERecord.Event.ID
    ) -> some SelectStatementOf<ChannelPreferences> {
        ChannelPreferences
            .where { $0.id.organizerID.eq(eventID.organizerID) }
            .where { $0.id.eventID.eq(eventID.eventID) }
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addChannelButtonTapped:
                guard state.canManageChannels else { return }
                state.destination = .channelForm(
                    ChannelForm.State(eventID: state.eventID)
                )

            case let .channelButtonTapped(channelID):
                state.destination = .channelDetail(
                    CommunicationChannelDetail.State(
                        channelID: channelID,
                        eventID: state.eventID
                    )
                )

            case let .deleteChannelButtonTapped(channelID):
                state.destination = .deleteChannelConfirmation(
                    ChannelDeleteConfirmation.State(channelID: channelID)
                )

            case let .destination(.deleteChannelConfirmation(.deleteButtonTapped(channelID))):
                let recordID = OMERecord.Channel.ID(
                    organizerID: state.eventID.organizerID,
                    eventID: state.eventID.eventID,
                    channelID: channelID
                )
                state.destination = nil
                store.addTask {
                    do {
                        try await database.write { db in
                            try OMERecord.Channel.find(recordID).delete().execute(db)
                        }
                        try store.modify { $0.errorMessage = nil }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to delete this channel."
                        }
                    }
                }

            case let .editChannelButtonTapped(channel):
                state.destination = .channelForm(ChannelForm.State(channel: channel))

            case let .markAllPostsReadButtonTapped(channelID):
                store.addTask {
                    do {
                        try await database.write { database in
                            try CommsPostRead.setRead(
                                true,
                                channelID: channelID,
                                in: database
                            )
                        }
                        try store.modify { $0.errorMessage = nil }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to mark all posts in this channel as read."
                        }
                    }
                }

            case let .markAllPostsUnreadButtonTapped(channelID):
                store.addTask {
                    do {
                        try await database.write { database in
                            try CommsPostRead.setRead(
                                false,
                                channelID: channelID,
                                in: database
                            )
                        }
                        try store.modify { $0.errorMessage = nil }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to mark all posts in this channel as unread."
                        }
                    }
                }

            case .notificationPermissionButtonTapped:
                store.addTask {
                    do {
                        _ = try await devicePermissions.requestNotifications()
                        try await store.state.$permissions.load()
                        try store.modify { $0.errorMessage = nil }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to request notification permission."
                        }
                    }
                }

            case let .notificationStateButtonTapped(channelID, notificationState):
                guard
                    let channel = state.channels.first(where: { $0.id == channelID }),
                    notificationState != .unsubscribed || !channel.notificationsRequired
                else { return }

                let channelPreference = ChannelPreferences(
                    id: channelID,
                    notificationState: notificationState
                )
                store.addTask {
                    do {
                        try await database.write { db in
                            try ChannelPreferences.upsert { channelPreference }.execute(db)
                        }
                        let refreshTask = try store.post(
                            NotificationSubscriptionsRefreshRequested()
                        )
                        await refreshTask?.value
                        try store.modify {
                            $0.errorMessage = nil
                        }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to update notification preference."
                        }
                    }
                }

            case .openNotificationSettingsButtonTapped:
                store.addTask {
                    _ = await devicePermissions.openNotificationSettings()
                }

            case .destination:
                break
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}
