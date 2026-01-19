//
//  NotificationPreferencesView.swift
//  open-music-event
//
//  Created by Claude Code on 8/2/25.
//

import SwiftUI
import Foundation
import CoreModels
import GRDB
import Dependencies

public struct NotificationPreferencesView: View {
    @Observable
    @MainActor
    public class Store {
        public init() {}
        
        var channels: [CommunicationChannel.ChannelUserInfo] = []
        var isLoading: Bool = false

        @ObservationIgnored
        @Dependency(\.defaultDatabase) var defaultDatabase
        
        @ObservationIgnored
        @Dependency(\.musicEventID) var musicEventID



        @ObservationIgnored
        @Dependency(\.notificationManager) var notificationManager

        var isAuthorized = false

        func task() async {
            let id = musicEventID

//
//
//            let values = ValueObservation.tracking { db in
//                return try GRDB.Row.fetchAll(db, sql: """
//                    SELECT 
//                        c.title,
//                        c.description,
//                        c.userNotificationState,
//                        c.notificationsRequired
//                        cp.userNotificationState
//                
//                    FROM channels c
//                    LEFT JOIN channelPreferences cp ON c.id = cp.channelID
//                    WHERE c.musicEventID = \(id)
//                """)
//            }
//            .values(in: defaultDatabase)

            await withTaskGroup {
                $0.addTask { @Sendable @MainActor in
                    await withErrorReporting {
//
//                        for row in channelData {
//                            if let topicName: String = row["firebaseTopicName"] {
//                                let notificationState: String = row["userNotificationState"]
//                                let topic = CommunicationChannel.FirebaseTopicName(rawValue: topicName)
//                                let state = CommunicationChannel.UserNotificationState(rawValue: notificationState)
//                                try await self.updateTopicSubscription(topic, to: state ?? .unsubscribed)
//                            }
//                        }
                   }
                }

                $0.addTask { @Sendable @MainActor in
                    _ = await self.notificationManager.requestPermission()
                    self.isAuthorized = self.notificationManager.isAuthorized
                }
            }
                

        }

        subscript(notificationState channelID: CommunicationChannel.ID) -> CommunicationChannel.UserNotificationState {
            get {

                self.channels.first(where: { $0.id == channelID })?.notificationState ?? .unsubscribed
            }

            set {
                withErrorReporting {
                    try defaultDatabase.write { db in
                        try db.execute(
                            sql: """
                                UPDATE \(CommunicationChannel.Preferences.tableName)
                                SET userNotificationState = ? WHERE channelID = ?
                            """,
                            arguments: [newValue.rawValue, channelID]
                        )
                    }
                }
            }
        }
        
        func didTapEnableNotifications() async {
            notificationManager.openSettings()
        }

    }
    
    @Bindable var store: Store

    public init(store: Store) {
        self.store = store
    }
    
    public var body: some View {
        List {
            if !store.isAuthorized {
                HStack {
                    Text("Notifications are currently disabled.")

                    Button("Enable") {
                        Task {
                            await store.didTapEnableNotifications()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if !store.channels.isEmpty {
                Section {
                    ForEach(store.channels) { channel in
                        HStack {
                            Text(channel.name)

                            Spacer()

                            if channel.notificationsRequired {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.yellow)
                            } else {
                                NotificationToggle(state: $store[notificationState: channel.id])
                                    .disabled(channel.notificationsRequired)
                                    .disabled(!store.isAuthorized)
                            }
                        }
                    }
                    
                } header: {
                    Text("Communication Channels")

                } footer: {
                    if !store.isAuthorized {
                        Text("Enable push notifications above to configure channel preferences.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Channels marked with ⚠️ send critical notifications that cannot be disabled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
//
            } else if store.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding()
                }
            } else {
                Section {
                    Text("No communication channels available for this event.")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        }
        .navigationTitle("Notifications")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task { await store.task() }

    }
}

//#if DEBUG
//#Preview {
//    NavigationStack {
//        NotificationPreferencesView(store: .init())
//    }
//}
//#endif


struct NotificationToggle: View {
    @Binding var state: CommunicationChannel.UserNotificationState

    var body: some View {
        Picker("", selection: $state) {
            ForEach(CommunicationChannel.UserNotificationState.allCases, id: \.self) {
                Text($0.label)
            }
        }
    }
}

extension CommunicationChannel.UserNotificationState: PickableValue {
    public var label: LocalizedStringKey {
        switch self {
        case .subscribed: "Subscribed"
        case .unsubscribed: "Unsubscribed"
        }
    }
}

