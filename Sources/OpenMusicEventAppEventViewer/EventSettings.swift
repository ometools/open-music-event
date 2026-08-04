import ComposableArchitecture2
import ComposableAuthoring
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventEditors
import OpenMusicEventSourceEditing
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
    }

    public enum Action {
        case enterAuthoringButtonTapped
        case eventPoliciesButtonTapped
        case exitAuthoringButtonTapped
        case testErrorButtonTapped
    }

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
}

private extension ErrorOperation {
    static let eventSettingsTestError = Self("event.settings.test-error")
}

private extension ErrorKind {
    static let eventSettingsTestError = Self("event.settings.test-error")
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
