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

struct CommunicationChannelSettingsMenu: View {
    let store: StoreOf<CommunicationChannelDetail>
    let channel: OMERecord.Channel

    var body: some View {
        Menu {
            Button {
                store.send(.newPostButtonTapped)
            } label: {
                Label("New Post", mappedSystemImage: "square.and.pencil")
            }

            Button {
                store.send(.editChannelButtonTapped(channel))
            } label: {
                Label("Edit Channel", systemImage: "pencil")
            }

            Button(role: .destructive) {
                store.send(.deleteChannelButtonTapped)
            } label: {
                Label("Delete Channel", systemImage: "trash")
            }
        } label: {
            Label("Channel Settings", mappedSystemImage: "gearshape")
        }
    }
}

