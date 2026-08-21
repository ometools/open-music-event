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

struct CommunicationChannelPostDestinationView: View {
    @Bindable var store: StoreOf<CommunicationChannelDetail>
    let channel: OMERecord.Channel

    init(
        store: StoreOf<CommunicationChannelDetail>,
        channel: OMERecord.Channel
    ) {
        self.store = store
        self.channel = channel
    }

    var body: some View {
        CommunicationChannelDetailList(store: store, channel: channel)
            .navigationTitle(channel.name)
            .navigationDestination(
                item: $store.scope(\.destination, action: \.destination).postDetail
            ) { postStore in
                CommsPostDetailView(store: postStore)
            }
    }
}

