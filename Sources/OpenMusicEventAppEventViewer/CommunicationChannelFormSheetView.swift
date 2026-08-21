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

struct CommunicationChannelFormSheetView: View {
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
        CommunicationChannelComposerSheetView(store: store, channel: channel)
            .sheet(
                item: $store.scope(\.destination, action: \.destination).channelForm
            ) { formStore in
                NavigationStack {
                    ChannelFormView(store: formStore)
                }
            }
    }
}

