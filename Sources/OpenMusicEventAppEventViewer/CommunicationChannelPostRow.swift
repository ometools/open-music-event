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

struct CommunicationChannelPostRow: View {
    let store: StoreOf<CommunicationChannelDetail>
    let post: CommsPost

    var body: some View {
        let isRead = store.readPostIDs.contains(post.id)
        Button {
            store.send(.postButtonTapped(post.id))
        } label: {
            CommsPostRowView(post: post, isRead: isRead)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                store.send(.markPostReadButtonTapped(post.id))
            } label: {
                Label(
                    "Mark as Read",
                    systemImage: isRead ? "checkmark" : "mail-open"
                )
            }
            .disabled(isRead)

            Button {
                store.send(.markPostUnreadButtonTapped(post.id))
            } label: {
                Label(
                    "Mark as Unread",
                    systemImage: isRead ? "mail-unread" : "checkmark"
                )
            }
            .disabled(!isRead)
        }
    }
}

