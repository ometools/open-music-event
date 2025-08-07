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
        
        var channels: [CommunicationChannel] = []
        var isLoading: Bool = false

        @ObservationIgnored
        @Dependency(\.defaultDatabase) var defaultDatabase
        
        @ObservationIgnored
        @Dependency(\.musicEventID) var musicEventID

        @ObservationIgnored
        @Dependency(\.notificationManager) var permissionManager

        func task() async {
            let id = musicEventID
            
            let values = ValueObservation.tracking { db in
                try CommunicationChannel
                    .filter(Column("musicEventID") == id)
                    .fetchAll(db)
            }
            .values(in: defaultDatabase)
            
            await withErrorReporting {
                for try await channels in values {
                    self.channels = channels
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
                        try db.execute(sql: "UPDATE \(CoreModels.CommunicationChannel.tableName) SET userNotificationState = ? WHERE id = ?", arguments: [newValue.rawValue, channelID])
                    }
                }
            }
        }
        
        func didTapEnableNotifications() async {
            if permissionManager.shouldShowPermissionRequest {
                _ = await permissionManager.requestPermission()
            } else if permissionManager.shouldShowSettingsPrompt {
                permissionManager.openSettings()
            }
        }

    }
    
    @Bindable var store: Store

    public init(store: Store) {
        self.store = store
    }
    
    public var body: some View {
        List {

            if store.permissionManager.shouldShowPermissionRequest || store.permissionManager.shouldShowSettingsPrompt {
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

                            NotificationToggle(state: $store[notificationState: channel.id])
                                .disabled(channel.notificationsRequired)
                                .disabled(!store.permissionManager.isAuthorized)

                            if channel.notificationsRequired {
                                Image(systemName: "warning")
                                    .foregroundStyle(Color.yellow)
                            }
                        }
                    }
                    
                } header: {
                    Text("Communication Channels")

                } footer: {
                    if !store.permissionManager.isAuthorized {
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
        .navigationBarTitleDisplayMode(.large)
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

import SwiftUI

/**
 A protocol that defines an value that can be selected in a picker view. This should only be used with enum types

 Conforming types must provide a label property, which is `LocalizedStringKey`. The label property describes the title of the pickable value in the picker view. Values conforming to this type also comform to CaseIterable, which allows the declaration order of enum cases to drive the ordering of elements in the picker view.
 */
public protocol PickableValue: CaseIterable, LabeledValue { }

public protocol LabeledValue: Hashable {
    var label: LocalizedStringKey { get }
}
