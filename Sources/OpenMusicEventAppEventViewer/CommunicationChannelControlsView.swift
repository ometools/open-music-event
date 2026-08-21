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

struct CommunicationChannelControlsView: View {
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
        CommunicationChannelFormSheetView(store: store, channel: channel)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    CommunicationChannelNotificationMenu(
                        store: store,
                        channel: channel
                    )
                }

                if store.canEditChannel {
                    ToolbarItem(placement: .primaryAction) {
                        CommunicationChannelSettingsMenu(
                            store: store,
                            channel: channel
                        )
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
                    store.send(
                        .destination(
                            .deleteChannelConfirmation(
                                .deleteButtonTapped(store.channelID)
                            )
                        )
                    )
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the channel. Posts already published in it are not changed.")
            }
    }
}

