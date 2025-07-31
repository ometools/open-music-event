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
        
        var channels: [ChannelSubscription] = []
        var isLoading: Bool = false

        struct ChannelSubscription: Identifiable {
            var id: CommunicationChannel.ID
            var channelName: String
            var notificationState: CommunicationChannel.NotificationState
        }

        @ObservationIgnored
        @Dependency(\.defaultDatabase) var defaultDatabase
        
        @ObservationIgnored
        @Dependency(\.musicEventID) var musicEventID

        @ObservationIgnored
        @Dependency(\.notificationPermissionManager) var permissionManager

        func task() async {
            isLoading = true
            let id = musicEventID
            
            let values = ValueObservation.tracking { db in
                let sql = """
                    SELECT 
                        c.name as name,
                        c.id as id,
                        c.sortIndex as sortIndex,
                        userNotificationState as state
                    FROM channels c
                    WHERE c.musicEventID = ?
                    ORDER BY c.sortIndex, c.name
                """
                
                return try Row.fetchAll(db, sql: sql, arguments: [id]).map { row in
                    let state: String = row["state"] ?? "unsubscribed"
                    return ChannelSubscription(
                        id: OmeID(row["id"]),
                        channelName: row["name"],
                        notificationState: .init(rawValue: state)!
                    )
                }
            }
            .values(in: defaultDatabase)
            
            do {
                for try await channels in values {
                    self.channels = channels
                    self.isLoading = false
                }
            } catch {
                reportIssue(error)
                self.isLoading = false
            }
        }

        subscript(notificationState channelID: CommunicationChannel.ID) -> CommunicationChannel.NotificationState {
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
                            Text(channel.channelName)

                            Spacer()

                            NotificationToggle(state: $store[notificationState: channel.id])
                                .disabled(!store.permissionManager.isAuthorized)
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
    @Binding var state: CommunicationChannel.NotificationState

    var body: some View {
        Picker("", selection: $state) {
            ForEach(CommunicationChannel.NotificationState.allCases, id: \.self) {
                Text($0.label)
            }
        }
    }
}

extension CommunicationChannel.NotificationState: PickableValue {
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
