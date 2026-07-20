import ComposableArchitecture2
import Dependencies
import ErrorHandling
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import OpenMusicEventEditors
import SQLiteData
import SwiftUI

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
        case eventPoliciesButtonTapped
        case reportingLinkButtonTapped
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

            case .eventPoliciesButtonTapped:
                let eventID = state.eventID
                store.addTask {
                    let task = try store.post(
                        key: EventEditingRequested.self,
                        value: .editEventPolicies(eventID)
                    )
                    await task?.value
                }

            case .reportingLinkButtonTapped:
                let eventID = state.eventID
                store.addTask {
                    let task = try store.post(
                        key: EventEditingRequested.self,
                        value: .editReportingLink(eventID)
                    )
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

    public init(store: StoreOf<EventSettings>) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("Integrations") {
                Button {
                    store.send(.reportingLinkButtonTapped)
                } label: {
                    HStack {
                        Text("Reporting Link")
                        Spacer()
                        Text(store.event?.reportingLink == nil ? "Not configured" : "Configured")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

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

@Feature
public struct EditReportingLink {
    public init() {}

    public struct State {
        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
        }

        let eventID: OMERecord.Event.ID
        var description = ""
        var draft: OMERecord.Event.Draft?
        var errorMessage: String?
        var hasLoadedDraft = false
        var isEnabled = false
        var isSaving = false
        var name = ""
        var urlString = ""

        var canSubmit: Bool {
            hasLoadedDraft && !isSaving && validationMessage == nil
        }

        var preparedDraft: OMERecord.Event.Draft? {
            guard var draft else { return nil }

            if isEnabled {
                guard let url = preparedURL else { return nil }
                draft.reportingLink = OMERecord.Event.ReportingLink(
                    name: trimmedName,
                    url: url,
                    description: trimmedDescription.nilIfEmpty
                )
            } else {
                draft.reportingLink = nil
            }

            return draft
        }

        var preparedURL: URL? {
            guard let components = URLComponents(string: trimmedURLString),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  components.host?.isEmpty == false,
                  let url = components.url
            else { return nil }

            return url
        }

        var trimmedDescription: String {
            description.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var trimmedName: String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var trimmedURLString: String {
            urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var validationMessage: String? {
            guard hasLoadedDraft, isEnabled else { return nil }
            guard !trimmedName.isEmpty else {
                return "Enter a reporting link name."
            }
            guard preparedURL != nil else {
                return "Enter a valid http or https URL."
            }
            return nil
        }

        mutating func apply(_ reportingLink: OMERecord.Event.ReportingLink?) {
            isEnabled = reportingLink != nil
            name = reportingLink?.name ?? ""
            urlString = reportingLink?.url.absoluteString ?? ""
            description = reportingLink?.description ?? ""
        }
    }

    public enum Action {
        case cancelButtonTapped
        case saveButtonTapped
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                guard state.hasLoadedDraft else {
                    state.errorMessage = "This event could not be loaded."
                    return
                }
                guard let validationMessage = state.validationMessage else {
                    guard let draft = state.preparedDraft else {
                        state.errorMessage = "Unable to save reporting link."
                        return
                    }

                    state.errorMessage = nil
                    state.isSaving = true

                    store.addTask {
                        do {
                            try database.write { db in
                                try OMERecord.Event.upsert {
                                    draft
                                }
                                .execute(db)
                            }
                            try store.modify {
                                $0.errorMessage = nil
                                $0.isSaving = false
                            }
                            try store.dismiss()
                        } catch {
                            try store.modify {
                                $0.errorMessage = "Unable to save reporting link."
                                $0.isSaving = false
                            }
                        }
                    }
                    return
                }

                state.errorMessage = validationMessage
            }
        }
        .onMount { state in
            guard !state.hasLoadedDraft else { return }

            do {
                if let event = try database.read({ db in
                    try OMERecord.Event.where { $0.id.eq(state.eventID) }.fetchOne(db)
                }) {
                    state.draft = .init(event)
                    state.apply(event.reportingLink)
                    state.hasLoadedDraft = true
                    state.errorMessage = nil
                } else {
                    state.errorMessage = "This event could not be loaded."
                }
            } catch {
                state.errorMessage = "This event could not be loaded."
            }
        }
    }
}

public struct EditReportingLinkView: View {
    @Bindable var store: StoreOf<EditReportingLink>

    public init(store: StoreOf<EditReportingLink>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.hasLoadedDraft {
                Form {
                    Section("Reporting Link") {
                        Toggle("Enable Reporting Link", isOn: $store.isEnabled)

                        if store.isEnabled {
                            TextField("Name", text: $store.name)
                            TextField("URL", text: $store.urlString)
                                #if os(iOS)
                                .keyboardType(.URL)
                                #endif
                        }
                    }

                    if store.isEnabled {
                        Section("Description") {
                            TextField("Description", text: $store.description, axis: .vertical)
                                .lineLimit(2...5)
                        }
                    }

                    if let errorMessage = store.errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            } else {
                ViewerPlaceholderView(
                    title: "Reporting Link",
                    systemImage: "link",
                    description: "This event could not be loaded."
                )
            }
        }
        .disabled(store.isSaving)
        .navigationTitle("Reporting Link")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    store.send(.cancelButtonTapped)
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                SubmitButton(
                    isInProgress: store.isSaving,
                    isDisabled: !store.canSubmit
                ) {
                    store.send(.saveButtonTapped)
                }
            }
        }
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
