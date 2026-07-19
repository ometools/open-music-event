import ComposableArchitecture2
import ComposableForms
import Dependencies
import Foundation
import OpenMusicEventAppEventViewer
import OpenMusicEventComponents
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import OpenMusicEventTimeZones
import SwiftUITabFeatures
import SwiftUI

@Feature
public struct TeamWorkspaceCreateEvent {
    public init() {}

    @Dependency(\.organizerSourceWorkspace) var organizerSourceWorkspace

    public struct FormValue: Equatable {
        var endDateSelection: Date
        var eventDirectoryName = "2026"
        var eventName = ""
        var hasEndDate = false
        var hasStartDate = true
        var startDateSelection: Date
        var timeZone: TimeZone = .current

        init(now: Date) {
            self.endDateSelection = now
            self.startDateSelection = now
        }
    }

    public typealias FormFeature = ComposableForms.Form<FormValue>

    public struct State {
        public init(
            sourceBaselineID: SourceBaselineRecord.ID,
            calendarID: OMERecord.Calendar.ID,
            eventDirectoryName: String = "2026"
        ) {
            @Dependency(\.date) var date
            let now = date()
            self.sourceBaselineID = sourceBaselineID
            self.calendarID = calendarID
            self.form = FormFeature.State(value: FormValue(now: now))
            self.eventDirectoryName = eventDirectoryName
        }

        public let calendarID: OMERecord.Calendar.ID
        public let sourceBaselineID: SourceBaselineRecord.ID

        var errorMessage: String?
        var form: FormFeature.State
        var isSaving = false

        var endDateSelection: Date {
            get { form.value.endDateSelection }
            set { form.value.endDateSelection = newValue }
        }

        var startDate: LocalDate? {
            hasStartDate ? LocalDate(startDateSelection, in: timeZone) : nil
        }

        var endDate: LocalDate? {
            hasEndDate ? LocalDate(endDateSelection, in: timeZone) : nil
        }

        var eventDirectoryName: String {
            get { form.value.eventDirectoryName }
            set { form.value.eventDirectoryName = newValue }
        }

        var eventName: String {
            get { form.value.eventName }
            set { form.value.eventName = newValue }
        }

        var hasEndDate: Bool {
            get { form.value.hasEndDate }
            set { form.value.hasEndDate = newValue }
        }

        var hasStartDate: Bool {
            get { form.value.hasStartDate }
            set { form.value.hasStartDate = newValue }
        }

        var startDateSelection: Date {
            get { form.value.startDateSelection }
            set { form.value.startDateSelection = newValue }
        }

        var timeZone: TimeZone {
            get { form.value.timeZone }
            set { form.value.timeZone = newValue }
        }

        var timeZoneSelection: TimeZone {
            get { timeZone }
            set {
                guard newValue.identifier != timeZone.identifier else { return }
                if hasStartDate {
                    startDateSelection = LocalDate(startDateSelection, in: timeZone)
                        .atStartOfDay(in: newValue)
                }
                if hasEndDate {
                    endDateSelection = LocalDate(endDateSelection, in: timeZone)
                        .atStartOfDay(in: newValue)
                }
                timeZone = newValue
            }
        }

        var dateRangeSelection: EventDateRangeSelection {
            get {
                EventDateRangeSelection(
                    hasStartDate: hasStartDate,
                    startDateSelection: startDateSelection,
                    hasEndDate: hasEndDate,
                    endDateSelection: endDateSelection,
                    timeZone: timeZone
                )
            }
            set {
                hasStartDate = newValue.hasStartDate
                startDateSelection = newValue.startDateSelection
                hasEndDate = newValue.hasEndDate
                endDateSelection = newValue.endDateSelection
            }
        }

        var trimmedEventDirectoryName: String {
            eventDirectoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var trimmedEventName: String {
            eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var validationMessage: String? {
            if !eventName.isEmpty && trimmedEventName.isEmpty {
                return "Enter an event name."
            }
            if trimmedEventDirectoryName.isEmpty {
                return "Enter an event directory."
            }
            if !OrganizerSourcePathComponent.isValid(trimmedEventDirectoryName) {
                return "Use a single directory name like 2026-pre-party-kelowna."
            }
            if !hasStartDate {
                return "Choose a start date."
            }
            if let startDate, let endDate, endDate < startDate {
                return "End date must be on or after the start date."
            }
            return nil
        }

        var submitValidationMessage: String? {
            if trimmedEventName.isEmpty {
                return "Enter an event name."
            }
            return validationMessage
        }

        var canSubmit: Bool {
            !isSaving
                && form.canSubmit
                && !trimmedEventName.isEmpty
                && validationMessage == nil
        }
    }

    public enum Action {
        case form(FormFeature.Action)
        case formSubmitted(FormValue)
        case saveButtonTapped
    }

    public var body: some Feature {
        Scope(\.form, action: \.form) {
            FormFeature()
                .onSubmit { value in
                    try store.send(.formSubmitted(value))
                }
        }
        Update { state, action in
            func submit(_ state: inout State) {
                guard !state.isSaving else { return }

                guard let validationMessage = state.submitValidationMessage else {
                    state.errorMessage = nil
                    state.isSaving = true
                    let request = OrganizerSourceWorkspaceCreateEventRequest(
                        calendarID: state.calendarID,
                        endDate: state.endDate,
                        eventDirectoryName: state.trimmedEventDirectoryName,
                        eventName: state.trimmedEventName,
                        organizerID: state.calendarID.ownerID,
                        sourceBaselineID: state.sourceBaselineID,
                        startDate: state.startDate,
                        timeZone: state.timeZone
                    )
                    let organizerSourceWorkspace = organizerSourceWorkspace

                    store.addTask {
                        do {
                            let eventID = try await organizerSourceWorkspace.createEvent(request)
                            try store.modify {
                                $0.errorMessage = nil
                                $0.isSaving = false
                            }
                            try store.post(
                                key: NavigationRequested.self,
                                value: .event(eventID, .workspace)
                            )
                            try store.dismiss()
                        } catch OrganizerSourceWorkspaceError.eventDirectoryAlreadyExists(_) {
                            try store.modify {
                                $0.errorMessage = "An event already exists at that directory."
                                $0.isSaving = false
                            }
                        } catch {
                            try store.modify {
                                $0.errorMessage = "Unable to create event in workspace."
                                $0.isSaving = false
                            }
                        }
                    }
                    return
                }

                state.errorMessage = validationMessage
            }

            switch action {
            case .form:
                break

            case let .formSubmitted(value):
                guard !state.isSaving else { return }
                state.form.value = value

                guard state.form.canSubmit else {
                    state.errorMessage = state.submitValidationMessage ?? "Fix the highlighted fields."
                    return
                }

                submit(&state)

            case .saveButtonTapped:
                submit(&state)
            }
        }
    }
}

private enum TeamWorkspaceCreateEventFormFieldID {
    static var eventDirectoryName: AnyHashable {
        AnyHashable(\TeamWorkspaceCreateEvent.FormValue.eventDirectoryName)
    }
    static var eventName: AnyHashable {
        AnyHashable(\TeamWorkspaceCreateEvent.FormValue.eventName)
    }
}

private extension TeamWorkspaceCreateEvent.FormFeature {
    init() {
        self.init {
            Self.Field(\.eventName) {
                Validation(error: "Enter an event name.") { value in
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }

            Self.Field(\.eventDirectoryName) {
                Validation { value -> ValidationResult in
                    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedValue.isEmpty else {
                        return .invalid("Enter an event directory.")
                    }
                    guard OrganizerSourcePathComponent.isValid(trimmedValue) else {
                        return .invalid("Use a single directory name like 2026-pre-party-kelowna.")
                    }
                    return .valid
                }
            }
        }
    }
}

struct TeamWorkspaceCreateEventView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var store: StoreOf<TeamWorkspaceCreateEvent>
    @State var isTimeZonePickerPresented = false

    var body: some View {
        SwiftUI.Form {
            Section {
                Text("Start with the basics. This creates files in the active organizer workspace so the event can be edited locally.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Event Name") {
                TextField("Event Name", text: $store.form.value.eventName, prompt: Text("Wicked Woods 2026"))

                FormFieldValidationStatus(
                    validation: store.form.validation[TeamWorkspaceCreateEventFormFieldID.eventName]
                )
            }

            Section {
                TextField(
                    "Directory",
                    text: $store.eventDirectoryName,
                    prompt: Text("2026")
                )
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()

                FormFieldValidationStatus(
                    validation: store.form.validation[
                        TeamWorkspaceCreateEventFormFieldID.eventDirectoryName
                    ]
                )
            } header: {
                Text("Workspace")
            } footer: {
                Text("Creates events/\(store.trimmedEventDirectoryName.isEmpty ? "directory" : store.trimmedEventDirectoryName)/event.yml in the organizer workspace.")
            }

            Section {
                EventDateRangePicker(selection: $store.dateRangeSelection)

                Button {
                    isTimeZonePickerPresented = true
                } label: {
                    HStack {
                        Text("Time Zone")
                        Spacer()
                        Text(store.timeZone.identifier)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationLinkListRowStyle()
            } header: {
                Text("Dates")
            } footer: {
                Text("Dates are saved as local calendar dates in \(store.timeZone.identifier).")
            }

            if let validationMessage = store.validationMessage {
                Section {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
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
        .disabled(store.isSaving)
        .navigationTitle("New Event")
        .sheet(isPresented: $isTimeZonePickerPresented) {
            TimeZonePicker(selection: $store.timeZoneSelection)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Label("Cancel", systemImage: "close")
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
