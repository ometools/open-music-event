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
        .navigationDestination(item: $store.scope(\.destination, action: \.destination).channelDetail) { detailStore in
            CommunicationChannelDetailView(store: detailStore)
        }
        .sheet(item: $store.scope(\.destination, action: \.destination).channelForm) { formStore in
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
            isPresented: $store.scope(
                \.destination,
                action: \.destination
            ).deleteChannelConfirmation.isPresented,
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
    }
}

struct CommunicationChannelListRow: View {
    let store: StoreOf<CommunicationsViewer>
    let row: CommunicationChannelRow

    var body: some View {
        Button {
            store.send(.channelButtonTapped(row.channel.id.channelID))
        } label: {
            CommunicationChannelRowView(row: row)
                .frame(maxWidth: .infinity, alignment: .leading)
                .portableContentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            if !row.channel.notificationsRequired {
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
                        .deleteChannelButtonTapped(row.channel.id.channelID)
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
                    row.channel.notificationsRequired
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
                        .deleteChannelButtonTapped(row.channel.id.channelID)
                    )
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

