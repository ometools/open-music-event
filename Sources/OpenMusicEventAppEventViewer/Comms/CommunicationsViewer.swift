import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventImages
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
import SwiftUI
import Tagged

struct CommunicationChannelRow: Equatable, Identifiable, Sendable {
    let channel: Social.Category
    let preference: ChannelPreferences?
    let unreadPostCount: Int

    var id: Social.Category.ID { channel.id }

    var effectiveNotificationState: Social.Category.NotificationState {
        channel.effectiveNotificationState(preference: preference)
    }

    var notificationSystemImage: String {
        channel.notificationsRequired == true
            ? "bell.badge"
            : effectiveNotificationState.systemImage
    }
}

@Feature
public struct ChannelDeleteConfirmation: Prompt {
    public struct State: Identifiable {
        public init(channelID: Social.Category.ID) {
            self.channelID = channelID
        }

        public let channelID: Social.Category.ID
        public var id: Social.Category.ID { channelID }
    }

    public enum Action {
        case deleteButtonTapped(Social.Category.ID)
    }
}

@Feature
public struct CommunicationsViewer {
    public init() {}

    public struct State {
        public let eventID: Event.ID
        @SharedReader
        public var authoringGrant: AuthoringGrant?
        @SharedReader(.devicePermissions)
        public var permissions: DevicePermissions
        public var destination: Destination.State?
        public var errorMessage: String?

        @FetchAll public var channels: [Social.Category]
        @FetchAll public var channelPreferences: [ChannelPreferences]
        @FetchOne public var event: Event?
        @Fetch public var unreadPostCounts: CommsUnreadPostCounts

        public init(
            eventID: Event.ID,
            destination: Destination.State? = nil
        ) {
            self._authoringGrant = .authoringGrant(for: eventID)
            self.eventID = eventID
            self.destination = destination
            _channels = FetchAll(CommunicationsViewer.channelsQuery(eventID: eventID))
            _channelPreferences = FetchAll(CommunicationsViewer.channelPreferencesQuery(eventID: eventID))
            _event = FetchOne(Event.where { $0.id.eq(eventID) })
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
                    unreadPostCount: unreadPostCounts.count(forCategory: channel.id)
                )
            }
        }

        var hasContent: Bool {
            event != nil && (
                shouldShowNotificationPrompt
                    || shouldShowCriticalAlertPrompt
                    || !(event?.reportingLinks ?? []).isEmpty
                    || !channels.isEmpty
            )
        }

        var shouldShowCriticalAlertPrompt: Bool {
            permissions.notificationsAreAllowed
                && permissions.criticalAlerts == .disabled
        }

        var shouldShowNotificationPrompt: Bool {
            !permissions.notificationsAreAllowed
        }

        public var canManageChannels: Bool {
            authoringGrant?.access.canEditContent == true
        }

        public var unreadPostCount: Int {
            unreadPostCounts.count(forEvent: eventID)
        }
    }

    public enum Action {
        case addChannelButtonTapped
        case channelButtonTapped(Social.Category.ID)
        case criticalAlertPermissionButtonTapped
        case deleteChannelButtonTapped(Social.Category.ID)
        case destination(Destination.Action)
        case editChannelButtonTapped(Social.Category)
        case markAllPostsReadButtonTapped(Social.Category.ID)
        case markAllPostsUnreadButtonTapped(Social.Category.ID)
        case notificationPermissionButtonTapped
        case notificationStateButtonTapped(
            Social.Category.ID,
            Social.Category.NotificationState
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
        eventID: Event.ID
    ) -> some SelectStatementOf<Social.Category> {
        Social.Category
            .where { $0.event.eq(eventID) }
            .order { $0.name.collate(.nocase) }
    }

    static func channelPreferencesQuery(
        eventID: Event.ID
    ) -> some SelectStatementOf<ChannelPreferences> {
        ChannelPreferences.all
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

            case .criticalAlertPermissionButtonTapped:
                store.addTask {
                    do {
                        _ = try await devicePermissions.requestCriticalAlerts()
                        try await store.state.$permissions.load()
                        try store.modify { $0.errorMessage = nil }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to request Critical Alerts permission."
                        }
                    }
                }

            case let .deleteChannelButtonTapped(channelID):
                state.destination = .deleteChannelConfirmation(
                    ChannelDeleteConfirmation.State(channelID: channelID)
                )

            case let .destination(.deleteChannelConfirmation(.deleteButtonTapped(channelID))):
                let eventID = state.eventID
                state.destination = nil
                store.addTask {
                    do {
                        try await database.write { db in
                            try SocialCategoryRecordEditing.delete(
                                channelID, eventID: eventID, in: db
                            )
                        }
                        try store.modify { $0.errorMessage = nil }
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to delete this channel."
                        }
                    }
                }

            case let .editChannelButtonTapped(channel):
                state.destination = .channelForm(ChannelForm.State(category: channel))

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
                    notificationState != .unsubscribed || channel.notificationsRequired != true
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
        .ifLet(\.destination) {
            Destination.body
        }
    }
}

public struct CommunicationsViewerView: View {
    @Bindable var store: StoreOf<CommunicationsViewer>

    public init(store: StoreOf<CommunicationsViewer>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.hasContent {
                List {
                    if store.shouldShowNotificationPrompt {
                        Section {
                            Button {
                                if store.permissions.notifications == .unknown {
                                    store.send(.notificationPermissionButtonTapped)
                                } else {
                                    store.send(.openNotificationSettingsButtonTapped)
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    MappedSystemImage(systemName: "bell.badge")
                                        .frame(width: 24, height: 24)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Turn On Notifications")
                                            .foregroundStyle(.primary)
                                        Text("This event wants to send you important updates.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text(
                                        store.permissions.notifications == .unknown
                                            ? "Allow"
                                            : "Settings"
                                    )
                                    .font(.subheadline.weight(.semibold))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if store.shouldShowCriticalAlertPrompt {
                        Section {
                            Button {
                                store.send(.criticalAlertPermissionButtonTapped)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    MappedSystemImage(systemName: "bell.badge")
                                        .frame(width: 24, height: 24)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Allow Critical Alerts")
                                            .foregroundStyle(.primary)
                                        Text(
                                            "Emergency updates can alert you even when notifications are silenced."
                                        )
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text("Allow")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .buttonStyle(.plain)

                            Button("Open Notification Settings") {
                                store.send(.openNotificationSettingsButtonTapped)
                            }
                        }
                    }

                    channelsSection

                    if let errorMessage = store.errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            } else {
                ViewerPlaceholderView(
                    title: "Comms",
                    systemImage: "megaphone",
                    description: store.event == nil
                        ? "This event could not be loaded."
                        : "No communication channels have been added to this event yet."
                )
            }
        }
        .navigationTitle("Comms")
        .navigationDestination(item: $store.scope(\.destination).channelDetail) { detailStore in
            CommunicationChannelDetailView(store: detailStore)
        }
        .sheet(item: $store.scope(\.destination).channelForm) { formStore in
            NavigationStack {
                ChannelFormView(store: formStore)
            }
        }
        .toolbar {
            if store.canManageChannels {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.send(.addChannelButtonTapped)
                    } label: {
                        Label("Add Channel", systemImage: "plus")
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete Channel?",
            isPresented: $store.scope(\.destination).deleteChannelConfirmation.isPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Channel", role: .destructive) {
                if let channelID = store.destination?.deleteChannelConfirmation?.channelID {
                    store.send(
                        .destination(
                            .deleteChannelConfirmation(
                                .deleteButtonTapped(channelID)
                            )
                        )
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the channel. Posts already published in it are not changed.")
        }
        .accessibilityIdentifier(
            "view.communications.\(store.eventID.description)"
        )
    }

    @ViewBuilder
    private var channelsSection: some View {
        if store.channelRows.isEmpty {
            Section {
                Text("No communication channels have been added to this event yet.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("Channels") {
                ForEach(store.channelRows) { row in
                    CommunicationChannelListRow(store: store, row: row)
                }
            }
        }
    }
}

struct CommunicationChannelListRow: View {
    let store: StoreOf<CommunicationsViewer>
    let row: CommunicationChannelRow

    var body: some View {
        Button {
            store.send(.channelButtonTapped(row.channel.id))
        } label: {
            CommunicationChannelRowView(row: row)
                .frame(maxWidth: .infinity, alignment: .leading)
                .portableContentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            "button.channel.\(row.channel.id.description)"
        )
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            CommunicationChannelNotificationSwipeActions(store: store, row: row)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            CommunicationChannelAuthoringSwipeActions(store: store, row: row)
        }
        .contextMenu {
            CommunicationChannelContextActions(store: store, row: row)
        }
    }
}

struct CommunicationChannelNotificationSwipeActions: View {
    let store: StoreOf<CommunicationsViewer>
    let row: CommunicationChannelRow

    var body: some View {
        Group {
            if row.channel.notificationsRequired != true {
                if row.effectiveNotificationState == .subscribed {
                    Button {
                        store.send(
                            .notificationStateButtonTapped(
                                row.channel.id,
                                .unsubscribed
                            )
                        )
                    } label: {
                        Label(
                            "Don't Notify Me For New Posts",
                            mappedSystemImage: "bell.slash"
                        )
                    }
                } else {
                    Button {
                        store.send(
                            .notificationStateButtonTapped(
                                row.channel.id,
                                .subscribed
                            )
                        )
                    } label: {
                        Label(
                            "Notify Me For New Posts",
                            mappedSystemImage: "bell"
                        )
                    }
                }
            }
        }
    }
}

struct CommunicationChannelAuthoringSwipeActions: View {
    let store: StoreOf<CommunicationsViewer>
    let row: CommunicationChannelRow

    var body: some View {
        Group {
            if store.canManageChannels {
                Button {
                    store.send(.editChannelButtonTapped(row.channel))
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    store.send(
                        .deleteChannelButtonTapped(row.channel.id)
                    )
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

struct CommunicationChannelContextActions: View {
    let store: StoreOf<CommunicationsViewer>
    let row: CommunicationChannelRow

    var body: some View {
        Group {
            Button {
                store.send(
                    .markAllPostsReadButtonTapped(row.channel.id)
                )
            } label: {
                Label("Mark All as Read", systemImage: "mail-open")
            }

            Button {
                store.send(
                    .markAllPostsUnreadButtonTapped(row.channel.id)
                )
            } label: {
                Label("Mark All as Unread", systemImage: "mail-unread")
            }

            Divider()

            Menu {
                Button {
                    store.send(
                        .notificationStateButtonTapped(
                            row.channel.id,
                            .subscribed
                        )
                    )
                } label: {
                    Label(
                        "Notify Me For New Posts",
                        mappedSystemImage: row.effectiveNotificationState == .subscribed
                            ? "checkmark"
                            : "bell"
                    )
                }
                .disabled(row.effectiveNotificationState == .subscribed)

                Button {
                    store.send(
                        .notificationStateButtonTapped(
                            row.channel.id,
                            .unsubscribed
                        )
                    )
                } label: {
                    Label(
                        "Don't Notify Me For New Posts",
                        mappedSystemImage: row.effectiveNotificationState == .unsubscribed
                            ? "checkmark"
                            : "bell.slash"
                    )
                }
                .disabled(
                    row.channel.notificationsRequired == true
                        || row.effectiveNotificationState == .unsubscribed
                )
            } label: {
                Label(
                    "Notifications: \(row.effectiveNotificationState.menuTitle)",
                    mappedSystemImage: row.notificationSystemImage
                )
            }

            if store.canManageChannels {
                Divider()

                Button {
                    store.send(.editChannelButtonTapped(row.channel))
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    store.send(
                        .deleteChannelButtonTapped(row.channel.id)
                    )
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

struct CommunicationChannelRowView: View {
    let row: CommunicationChannelRow

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.channel.name)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                if let description = row.channel.displayDescription {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if row.unreadPostCount > 0 {
                Text("\(row.unreadPostCount)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .portableMonospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.tint, in: Capsule())
                    .accessibilityLabel(
                        Text("Unread posts: \(row.unreadPostCount)")
                    )
            }

            notificationImage
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    var notificationImage: some View {
        if row.channel.notificationsRequired == true {
            MappedSystemImage(systemName: "bell.badge")
                .frame(width: 20, height: 20)
                .accessibilityLabel("Notifications required")
        } else if row.effectiveNotificationState == .subscribed {
            MappedSystemImage(systemName: "bell.fill")
                .frame(width: 20, height: 20)
                .accessibilityLabel("Notifications enabled")
        }
    }
}

private extension Social.Category {
    var displayDescription: String? {
        let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
