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

    public enum Strategy: Equatable, Sendable {
        case blank
        case rollover
    }

    public struct RolloverChecklist: Equatable, Sendable {
        public var carriedForward: [String]
        public var startFresh: [String]

        public init(
            carriedForward: [String],
            startFresh: [String]
        ) {
            self.carriedForward = carriedForward
            self.startFresh = startFresh
        }
    }

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
            eventDirectoryName: String = "2026",
            strategy: Strategy = .blank
        ) {
            @Dependency(\.date) var date
            let now = date()
            self.sourceBaselineID = sourceBaselineID
            self.calendarID = calendarID
            self.strategy = strategy
            self.form = FormFeature.State(value: FormValue(now: now))
            self.eventDirectoryName = eventDirectoryName
        }

        public let calendarID: OMERecord.Calendar.ID
        public let sourceBaselineID: SourceBaselineRecord.ID
        public let strategy: Strategy

        var createdEventID: OMERecord.Event.ID?
        var errorMessage: String?
        var form: FormFeature.State
        var isSaving = false
        var isLoadingRolloverOptions = false
        var rolloverChecklist: RolloverChecklist?
        var rolloverErrorMessage: String?
        var rolloverOptions: [OrganizerSourceWorkspaceRolloverSourceEvent] = []
        var selectedRolloverEventID: OMERecord.Event.ID?
        var selectedRolloverStageIDs: Set<OMERecord.Stage.ID> = []
        var copySiteMapAndTheme = true
        var copyChannelDefinitions = true
        var copyVenueDetails = true

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
            if strategy == .rollover {
                if selectedRolloverEvent == nil {
                    return "Choose a previous event."
                }
                if selectedRolloverStageIDs.isEmpty {
                    return "Choose at least one stage to carry forward."
                }
                if !rolloverHasDurableSelection {
                    return "Choose at least one other durable group to carry forward."
                }
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
            rolloverChecklist == nil
                && !isSaving
                && form.canSubmit
                && !trimmedEventName.isEmpty
                && validationMessage == nil
        }

        var selectedRolloverEvent: OrganizerSourceWorkspaceRolloverSourceEvent? {
            rolloverOptions.first { $0.id == selectedRolloverEventID }
        }

        var rolloverHasDurableSelection: Bool {
            copySiteMapAndTheme || copyChannelDefinitions || copyVenueDetails
        }
    }

    public enum Action {
        case form(FormFeature.Action)
        case formSubmitted(FormValue)
        case rolloverChecklistDoneButtonTapped
        case rolloverEventButtonTapped(OMERecord.Event.ID)
        case rolloverStageButtonTapped(OMERecord.Stage.ID)
        case copySiteMapAndThemeToggleChanged(Bool)
        case copyChannelDefinitionsToggleChanged(Bool)
        case copyVenueDetailsToggleChanged(Bool)
        case saveButtonTapped
        case task
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
                    let rollover: OrganizerSourceWorkspaceRollover?
                    if state.strategy == .rollover {
                        guard let sourceEvent = state.selectedRolloverEvent else {
                            state.errorMessage = "Choose a previous event."
                            state.isSaving = false
                            return
                        }
                        rollover = OrganizerSourceWorkspaceRollover(
                            sourceEventID: sourceEvent.id,
                            selectedStageIDs: state.selectedRolloverStageIDs,
                            copyVenueDetails: state.copyVenueDetails,
                            copySiteMapAndTheme: state.copySiteMapAndTheme,
                            copyChannelDefinitions: state.copyChannelDefinitions
                        )
                    } else {
                        rollover = nil
                    }
                    let request = OrganizerSourceWorkspaceCreateEventRequest(
                        calendarID: state.calendarID,
                        endDate: state.endDate,
                        eventDirectoryName: state.trimmedEventDirectoryName,
                        eventName: state.trimmedEventName,
                        organizerID: state.calendarID.ownerID,
                        rollover: rollover,
                        sourceBaselineID: state.sourceBaselineID,
                        startDate: state.startDate,
                        timeZone: state.timeZone
                    )
                    let organizerSourceWorkspace = organizerSourceWorkspace
                    let strategy = state.strategy
                    let checklist = state.strategy == .rollover
                        ? makeRolloverChecklist(
                            sourceEventName: state.selectedRolloverEvent?.name ?? "previous event",
                            copiedStages: state.selectedRolloverStageIDs.count,
                            copyVenueDetails: state.copyVenueDetails,
                            copySiteMapAndTheme: state.copySiteMapAndTheme,
                            copyChannelDefinitions: state.copyChannelDefinitions
                        )
                        : nil

                    store.addTask {
                        do {
                            let eventID = try await organizerSourceWorkspace.createEvent(request)
                            try store.modify {
                                $0.createdEventID = eventID
                                $0.errorMessage = nil
                                $0.isSaving = false
                                $0.rolloverChecklist = checklist
                            }
                            if strategy == .blank {
                                try store.post(
                                    key: NavigationRequested.self,
                                    value: .event(eventID, .workspace)
                                )
                                try store.dismiss()
                            }
                        } catch OrganizerSourceWorkspaceError.eventDirectoryAlreadyExists(_) {
                            try store.modify {
                                $0.errorMessage = "An event already exists at that directory."
                                $0.isSaving = false
                            }
                        } catch OrganizerSourceWorkspaceError.rolloverRequiresStages {
                            try store.modify {
                                $0.errorMessage = "Choose at least one stage to carry forward."
                                $0.isSaving = false
                            }
                        } catch OrganizerSourceWorkspaceError.rolloverRequiresDurableSelection {
                            try store.modify {
                                $0.errorMessage = "Choose at least one other durable group to carry forward."
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

            case .rolloverChecklistDoneButtonTapped:
                guard let eventID = state.createdEventID else { return }
                store.addTask {
                    try store.post(
                        key: NavigationRequested.self,
                        value: .event(eventID, .workspace)
                    )
                    try store.dismiss()
                }

            case let .rolloverEventButtonTapped(eventID):
                guard let sourceEvent = state.rolloverOptions.first(where: { $0.id == eventID }) else {
                    return
                }
                state.selectedRolloverEventID = eventID
                state.selectedRolloverStageIDs = Set(sourceEvent.stages.map(\.id))
                state.rolloverErrorMessage = nil

            case let .rolloverStageButtonTapped(stageID):
                guard state.selectedRolloverEvent?.stages.contains(where: { $0.id == stageID }) == true else {
                    return
                }
                if state.selectedRolloverStageIDs.contains(stageID) {
                    state.selectedRolloverStageIDs.remove(stageID)
                } else {
                    state.selectedRolloverStageIDs.insert(stageID)
                }

            case let .copySiteMapAndThemeToggleChanged(isOn):
                state.copySiteMapAndTheme = isOn

            case let .copyChannelDefinitionsToggleChanged(isOn):
                state.copyChannelDefinitions = isOn

            case let .copyVenueDetailsToggleChanged(isOn):
                state.copyVenueDetails = isOn

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

            case .task:
                guard state.strategy == .rollover,
                      !state.isLoadingRolloverOptions,
                      state.rolloverOptions.isEmpty
                else { return }

                state.isLoadingRolloverOptions = true
                state.rolloverErrorMessage = nil
                let organizerSourceWorkspace = organizerSourceWorkspace
                let request = OrganizerSourceWorkspaceRolloverOptionsRequest(
                    organizerID: state.calendarID.ownerID,
                    sourceBaselineID: state.sourceBaselineID
                )
                store.addTask {
                    do {
                        let options = try await organizerSourceWorkspace.loadRolloverOptions(request)
                        try store.modify {
                            $0.isLoadingRolloverOptions = false
                            $0.rolloverOptions = options.sourceEvents
                            if let sourceEvent = options.sourceEvents.first {
                                $0.selectedRolloverEventID = sourceEvent.id
                                $0.selectedRolloverStageIDs = Set(sourceEvent.stages.map(\.id))
                            }
                        }
                    } catch {
                        try store.modify {
                            $0.isLoadingRolloverOptions = false
                            $0.rolloverErrorMessage = "Unable to load previous events."
                        }
                    }
                }
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

private func makeRolloverChecklist(
    sourceEventName: String,
    copiedStages: Int,
    copyVenueDetails: Bool,
    copySiteMapAndTheme: Bool,
    copyChannelDefinitions: Bool
) -> TeamWorkspaceCreateEvent.RolloverChecklist {
    var carriedForward = [
        "\(copiedStages) stage\(copiedStages == 1 ? "" : "s") from \(sourceEventName)",
    ]
    if copyVenueDetails {
        carriedForward.append("Venue and location details")
    }
    if copySiteMapAndTheme {
        carriedForward.append("Site map and theme/branding")
    }
    if copyChannelDefinitions {
        carriedForward.append("Channel definitions without message history")
    }
    return TeamWorkspaceCreateEvent.RolloverChecklist(
        carriedForward: carriedForward,
        startFresh: [
            "Artist and contributor roster",
            "Schedule performances",
            "Announcements and alerts",
            "Credentials and authoring permissions",
        ]
    )
}

struct TeamWorkspaceCreateEventView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var store: StoreOf<TeamWorkspaceCreateEvent>
    @State var isTimeZonePickerPresented = false

    var body: some View {
        Group {
            if let checklist = store.rolloverChecklist {
                rolloverChecklistView(checklist)
            } else {
                formView
            }
        }
        .task {
            await store.send(.task)?.value
        }
        .sheet(isPresented: $isTimeZonePickerPresented) {
            TimeZonePicker(selection: $store.timeZoneSelection)
        }
        .toolbar {
            if store.rolloverChecklist != nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.send(.rolloverChecklistDoneButtonTapped)
                    }
                }
            } else {
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

    @ViewBuilder
    var formView: some View {
        SwiftUI.Form {
            if store.strategy == .rollover {
                previousEventSelectionSection
            }

            Section {
                Text("Start with the basics. This creates files in the active organizer workspace so the event can be edited locally.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                Text(store.strategy == .rollover ? "New Dates" : "Dates")
            } footer: {
                Text("Dates are saved as local calendar dates in \(store.timeZone.identifier).")
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

            if let validationMessage = store.validationMessage {
                Section {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if store.strategy == .rollover {
                rolloverCarryForwardSections
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
    }

    @ViewBuilder
    var previousEventSelectionSection: some View {
        Section("Previous Event") {
            if store.isLoadingRolloverOptions && store.rolloverOptions.isEmpty {
                ProgressView("Loading previous events…")
            } else if store.rolloverOptions.isEmpty {
                ContentUnavailableView(
                    "No Previous Events",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Only events with stages can seed a rollover.")
                )
            } else {
                ForEach(store.rolloverOptions) { sourceEvent in
                    Button {
                        store.send(.rolloverEventButtonTapped(sourceEvent.id))
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(sourceEvent.name)
                                Text(sourceEvent.sourceEventDirectory)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.selectedRolloverEventID == sourceEvent.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    var rolloverCarryForwardSections: some View {
        if let sourceEvent = store.selectedRolloverEvent {
            Section {
                ForEach(sourceEvent.stages) { stage in
                    Button {
                        store.send(.rolloverStageButtonTapped(stage.id))
                    } label: {
                        HStack {
                            Text(stage.name)
                            Spacer()
                            Image(
                                systemName: store.selectedRolloverStageIDs.contains(stage.id)
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .foregroundStyle(
                                store.selectedRolloverStageIDs.contains(stage.id)
                                    ? Color.accentColor
                                    : Color.secondary
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Stages to Carry Forward")
            }

            Section("Durable Details") {
                Toggle("Venue and location details", isOn: $store.copyVenueDetails)
                Toggle("Site map and theme/branding", isOn: $store.copySiteMapAndTheme)
                Toggle("Channel definitions", isOn: $store.copyChannelDefinitions)
                Text("Messages, announcements, and alert history are never carried forward.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        if let rolloverErrorMessage = store.rolloverErrorMessage {
            Section {
                Text(rolloverErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    func rolloverChecklistView(
        _ checklist: TeamWorkspaceCreateEvent.RolloverChecklist
    ) -> some View {
        List {
            Section {
                Text("The new event is ready in the organizer workspace. Review these items before building the season.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("Carried Forward") {
                ForEach(checklist.carriedForward, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle.fill")
                }
            }
            Section("Start Fresh") {
                ForEach(checklist.startFresh, id: \.self) { item in
                    Label(item, systemImage: "arrow.right.circle")
                }
            }
        }
        .navigationTitle("Event Ready")
    }
}
