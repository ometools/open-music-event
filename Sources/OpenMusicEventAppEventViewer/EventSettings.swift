import ComposableArchitecture2
import ComposableAuthoring
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventEditors
import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct EventSettings {
    public init() {}

    public struct State {
        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
            _event = FetchOne(
                OMERecord.Event.where { $0.id.eq(eventID) }
            )
        }

        @FetchOne public var event: OMERecord.Event?
        public var eventID: OMERecord.Event.ID
        @SharedReader(.devicePermissions) public var permissions: DevicePermissions
    }

    public enum Action {
        case enterAuthoringButtonTapped
        case eventPoliciesButtonTapped
        case exitAuthoringButtonTapped
        case notificationPermissionButtonTapped
        case openNotificationSettingsButtonTapped
        case testErrorButtonTapped
    }

    @Dependency(\.devicePermissions) var devicePermissions

    public var body: some Feature {
        let _ = Self._logChanges()

        Update { state, action in
            switch action {
            case .enterAuthoringButtonTapped:
                store.addTask {
                    let task = try store.post(key: AuthoringRequested.self, value: ())
                    await task?.value
                }

            case .eventPoliciesButtonTapped:
                let eventID = state.eventID
                store.addTask {
                    let task = try store.post(
                        key: EventEditingRequested.self,
                        value: .editEventPolicies(eventID)
                    )
                    await task?.value
                }

            case .exitAuthoringButtonTapped:
                store.addTask {
                    let task = try store.post(key: AuthoringExitRequested.self, value: ())
                    await task?.value
                }

            case .notificationPermissionButtonTapped:
                store.addTask {
                    do {
                        _ = try await devicePermissions.requestNotifications()
                        try await store.state.$permissions.load()
                    } catch {
                        await store.reportError(
                            error,
                            fallbackMessage: .notificationPermissionRequestFailed,
                            operation: .notificationPermissionRequest
                        )
                    }
                }

            case .openNotificationSettingsButtonTapped:
                store.addTask {
                    _ = await devicePermissions.openNotificationSettings()
                }

            case .testErrorButtonTapped:
                store.addTask {
                    _ = await store.withErrorHandling(
                        fallbackMessage: .eventSettingsTestError,
                        operation: .eventSettingsTestError
                    ) {
                        try await throwEventSettingsTestError()
                    }
                }
            }
        }
    }
}

public struct EventSettingsView: View {
    @Bindable var store: StoreOf<EventSettings>
    @Environment(\.openMusicEventAuthoringPhase) var authoringPhase

    public init(store: StoreOf<EventSettings>) {
        self.store = store
    }

    public var body: some View {
        Form {
            switch authoringPhase {
            case .some(.entering):
                Section("Authoring") {
                    ProgressView("Authorizing source access")
                }

            case .some(.restoring):
                Section("Authoring") {
                    ProgressView("Restoring source access")
                }

            case .some(.exiting):
                Section("Authoring") {
                    ProgressView("Exiting authoring")
                }

            case .some(.active):
                Section("Authoring") {
                    Button("Exit Authoring") {
                        store.send(.exitAuthoringButtonTapped)
                    }
                }

            case .some(.inactive(.eligible)):
                Section("Authoring") {
                    Button("Enter Authoring") {
                        store.send(.enterAuthoringButtonTapped)
                    }
                }

            case .some(.inactive), .none:
                EmptyView()
            }

            #if os(iOS) || os(Android)
            Section("Permissions") {
                Text(
                    "Allow device notifications so this event can alert you when organizers publish important schedule or venue updates. You will still choose which updates you receive for each event."
                )

                switch store.permissions.notifications {
                case .authorized:
                    Label("Notifications allowed", systemImage: "bell.fill")

                case .limited:
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Notifications allowed quietly", systemImage: "bell.fill")
                        Text("Your device may deliver these without a sound or visible alert.")
                            .foregroundStyle(.secondary)
                    }

                case .denied, .restricted:
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Notifications not allowed", systemImage: "bell.slash")
                        Text("Open system settings to allow notifications for Open Music Event.")
                            .foregroundStyle(.secondary)
                        Button("Open Notification Settings") {
                            store.send(.openNotificationSettingsButtonTapped)
                        }
                    }

                case .unknown:
                    Button {
                        store.send(.notificationPermissionButtonTapped)
                    } label: {
                        Label("Allow Notifications", systemImage: "bell")
                    }
                }
            }
            #endif

            if case let .some(.active(grant)) = authoringPhase,
               grant.access.canEditContent
            {
                Section("Policies") {
                    Button {
                        store.send(.eventPoliciesButtonTapped)
                    } label: {
                        Label("Event Policies", systemImage: "slider.horizontal.3")
                    }
                }

                Section("Error Handling") {
                    Button {
                        store.send(.testErrorButtonTapped)
                    } label: {
                        Label("Send Test Error", systemImage: "exclamationmark.triangle")
                    }
                }
            }
        }
        .navigationTitle("Event Settings")
    }
}

private struct EventSettingsTestError: UserFacingErrorConvertible {
    func userFacingError(in context: ErrorHandlingContext) -> ParsedError {
        ParsedError(
            message: .eventSettingsTestError,
            kind: .eventSettingsTestError,
            debugDescription: "Event settings test error"
        )
    }
}

private func throwEventSettingsTestError() async throws {
    throw EventSettingsTestError()
}

private extension UserFacingText {
    static let eventSettingsTestError = Self(
        "Test error.",
        fallback: "Test error."
    )

    static let notificationPermissionRequestFailed = Self(
        "Open Music Event could not request notification permission.",
        fallback: "Open Music Event could not request notification permission."
    )
}

private extension ErrorOperation {
    static let eventSettingsTestError = Self("event.settings.test-error")
    static let notificationPermissionRequest = Self("event.settings.notification-permission")
}

private extension ErrorKind {
    static let eventSettingsTestError = Self("event.settings.test-error")
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
