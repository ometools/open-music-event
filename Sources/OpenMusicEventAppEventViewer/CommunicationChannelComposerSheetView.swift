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

struct CommunicationChannelComposerSheetView: View {
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
        CommunicationChannelPostDestinationView(store: store, channel: channel)
            .sheet(
                item: $store.scope(\.destination, action: \.destination).composer
            ) { composerStore in
                NavigationStack {
                    CommsPostComposerView(store: composerStore)
                }
            }
    }
}

