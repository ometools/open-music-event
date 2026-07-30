import ComposableArchitecture2
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
            _sourceProvenance = FetchOne(
                EventSourceProvenanceRecord.where { $0.id.eq(eventID) }
            )
        }

        @FetchOne public var event: OMERecord.Event?
        @FetchOne public var sourceProvenance: EventSourceProvenanceRecord?
        public var eventID: OMERecord.Event.ID
        public var isDeleteEventConfirmationPresented = false

        public var canDeleteEvent: Bool {
            event != nil && sourceProvenance == nil
        }
    }

    public enum Action {
        case deleteEventButtonTapped
        case deleteEventConfirmationDeleteButtonTapped
        case deleteEventConfirmationPresentedChanged(Bool)
        case enterAuthoringButtonTapped
        case eventPoliciesButtonTapped
        case exitAuthoringButtonTapped
        case testErrorButtonTapped
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .deleteEventButtonTapped:
                guard state.canDeleteEvent else { return }
                state.isDeleteEventConfirmationPresented = true

            case .deleteEventConfirmationDeleteButtonTapped:
                let eventID = state.eventID
                state.isDeleteEventConfirmationPresented = false
                store.addTask {
                    let task = try store.post(
                        key: LocalEventDeletionRequested.self,
                        value: eventID
                    )
                    await task?.value
                }

            case let .deleteEventConfirmationPresentedChanged(isPresented):
                state.isDeleteEventConfirmationPresented = isPresented

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
    let authoringAccess: AuthoringAccess
    let authoringAdmission: AuthoringAdmission?

    public init(
        store: StoreOf<EventSettings>,
        authoringAccess: AuthoringAccess,
        authoringAdmission: AuthoringAdmission?
    ) {
        self.store = store
        self.authoringAccess = authoringAccess
        self.authoringAdmission = authoringAdmission
    }

    public var body: some View {
        Form {
            if authoringAccess.canEditContent {
                Section("Authoring") {
                    Button("Exit Authoring") {
                        store.send(.exitAuthoringButtonTapped)
                    }
                }
            } else if case .granted = authoringAdmission {
                Section("Authoring") {
                    Button("Enter Authoring") {
                        store.send(.enterAuthoringButtonTapped)
                    }
                }
            }

            if authoringAccess.canEditContent {
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

                if store.canDeleteEvent {
                    Section {
                        Button(role: .destructive) {
                            store.send(.deleteEventButtonTapped)
                        } label: {
                            Label("Delete Event", systemImage: "trash")
                        }
                    } header: {
                        Text("Danger Zone")
                    } footer: {
                        Text("This permanently deletes the event data from this device. Created events are not cached off device.")
                    }
                }
            }
        }
        .navigationTitle("Event Settings")
        .confirmationDialog(
            "Delete Event?",
            isPresented: deleteEventConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Event", role: .destructive) {
                store.send(.deleteEventConfirmationDeleteButtonTapped)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the event data from this device. Created events are not cached off device.")
        }
    }

    private var deleteEventConfirmationPresented: Binding<Bool> {
        Binding(
            get: { store.isDeleteEventConfirmationPresented },
            set: { store.send(.deleteEventConfirmationPresentedChanged($0)) }
        )
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
