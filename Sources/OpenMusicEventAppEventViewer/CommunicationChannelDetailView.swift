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

public struct CommunicationChannelDetailView: View {
    @Bindable var store: StoreOf<CommunicationChannelDetail>

    public init(store: StoreOf<CommunicationChannelDetail>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let channel = store.channel {
                CommunicationChannelControlsView(store: store, channel: channel)
            } else {
                ViewerPlaceholderView(
                    title: "Channel",
                    systemImage: "megaphone",
                    description: "This communication channel could not be loaded."
                )
            }
        }
    }
}
