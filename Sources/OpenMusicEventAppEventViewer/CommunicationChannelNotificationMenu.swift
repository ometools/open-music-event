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

struct CommunicationChannelNotificationMenu: View {
    let store: StoreOf<CommunicationChannelDetail>
    let channel: OMERecord.Channel

    private var notificationState: OMERecord.Channel.NotificationState {
        store.effectiveNotificationState ?? channel.defaultNotificationState
    }

    private var isSubscribed: Bool {
        notificationState == .subscribed
    }

    private var isUnsubscribed: Bool {
        notificationState == .unsubscribed
    }

    private var subscribeSystemImage: String {
        isSubscribed ? "checkmark" : "bell"
    }

    private var unsubscribeSystemImage: String {
        isUnsubscribed ? "checkmark" : "bell.slash"
    }

    private var menuTitle: String {
        channel.notificationsRequired
            ? "Notifications Required"
            : "Notifications: \(notificationState.menuTitle)"
    }

    private var menuSystemImage: String {
        channel.notificationsRequired
            ? "bell.badge"
            : notificationState.systemImage
    }

    var body: some View {
        Menu {
            Button {
                store.send(.notificationStateButtonTapped(.subscribed))
            } label: {
                Label {
                    Text("Notify Me For New Posts")
                } icon: {
                    MappedSystemImage(systemName: subscribeSystemImage)
                }
            }
            .disabled(isSubscribed)

            Button {
                store.send(.notificationStateButtonTapped(.unsubscribed))
            } label: {
                Label {
                    Text("Don't Notify Me For New Posts")
                } icon: {
                    MappedSystemImage(systemName: unsubscribeSystemImage)
                }
            }
            .disabled(channel.notificationsRequired || isUnsubscribed)
        } label: {
            Label {
                Text(menuTitle)
            } icon: {
                MappedSystemImage(systemName: menuSystemImage)
            }
        }
    }
}
