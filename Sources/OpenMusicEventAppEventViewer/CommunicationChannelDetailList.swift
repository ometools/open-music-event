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

struct CommunicationChannelDetailList: View {
    let store: StoreOf<CommunicationChannelDetail>
    let channel: OMERecord.Channel

    var body: some View {
        List {
            Section {
                Text(channel.description)
                    .font(.subheadline)
            } footer: {
                if store.shouldShowEmptyPostsFooter {
                    Text("There are no posts in this channel yet.")
                }
            }

            if !store.pinnedPosts.isEmpty {
                Section("Pinned Posts") {
                    ForEach(store.pinnedPosts) { post in
                        CommunicationChannelPostRow(store: store, post: post)
                    }
                }
            }

            if !store.recentPosts.isEmpty {
                Section("Recent Posts") {
                    ForEach(store.recentPosts) { post in
                        CommunicationChannelPostRow(store: store, post: post)
                    }
                }
            }

            if channel.notificationsRequired || store.errorMessage != nil {
                Section("Notifications") {
                    if channel.notificationsRequired {
                        Label(
                            "Notifications are required for this channel.",
                            mappedSystemImage: "bell.badge"
                        )
                        .foregroundStyle(.secondary)
                    }

                    if let errorMessage = store.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}

