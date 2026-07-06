//
//  CreateEvent.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/2/26.
//

import ComposableArchitecture2
import ComposableForms
import Dependencies
import Foundation
import OpenMusicEventAppEventViewer
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import OpenMusicEventTimeZones
import SQLiteData
import SwiftUITabFeatures
import SwiftUI

private enum AppEventOrganizerIDKey: DependencyKey {
    static let liveValue = OMERecord.Organizer.ID("did:web:local.openmusicevent")!
    static let testValue = OMERecord.Organizer.ID("did:web:local.openmusicevent")!
}

extension DependencyValues {
    var appEventOrganizerID: OMERecord.Organizer.ID {
        get { self[AppEventOrganizerIDKey.self] }
        set { self[AppEventOrganizerIDKey.self] = newValue }
    }
}

@Feature
public struct CreateEvent {
    public init() {}

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date) var date
    @Dependency(\.uuid) var uuid
    @Dependency(\.workspaceReferenceDatabase) var workspaceReferenceDatabase

    public struct FormValue: Equatable {
        var endDateSelection: Date
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
            organizerID: OMERecord.Organizer.ID? = nil,
            eventOrganizerID: OMERecord.Organizer.ID? = nil
        ) {
            @Dependency(\.appEventOrganizerID) var appEventOrganizerID
            @Dependency(\.date) var date
            let now = date()
            self.organizerID = organizerID ?? appEventOrganizerID
            self.eventOrganizerID = eventOrganizerID
            self.form = FormFeature.State(
                value: FormValue(now: now)
            )
        }

        var organizerID: OMERecord.Organizer.ID
        var eventOrganizerID: OMERecord.Organizer.ID?

        var isSaving = false
        var errorMessage: String?
        var form: FormFeature.State

        var trimmedEventName: String {
            eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

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

        var validationMessage: String? {
            if !eventName.isEmpty && trimmedEventName.isEmpty {
                return "Enter an event name."
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
                    let localEventID = Self.makeLocalEventID(from: uuid())
                    let eventID = OMERecord.Event.ID(
                        organizerID: state.organizerID,
                        eventID: localEventID
                    )
                    let event = Self.makeEventDraft(
                        id: eventID,
                        name: state.trimmedEventName,
                        startDate: state.startDate,
                        endDate: state.endDate,
                        timeZone: state.timeZone
                    )
                    let createdAt = date()
                    let workspace = EditingWorkspaceRecord(
                        localEventID: eventID,
                        createdAt: createdAt
                    )
                    let eventWorkspace = EventEditingWorkspaceRecord(
                        id: eventID,
                        workspaceID: workspace.id
                    )

                    state.errorMessage = nil
                    state.isSaving = true
                    let organizerID = state.organizerID
                    let eventOrganizerID = state.eventOrganizerID
                    let workspaceReferenceDatabase = workspaceReferenceDatabase

                    store.addTask {
                        do {
                            try await database.write { db in
                                try Self.insertOrganizerIfNeeded(organizerID, in: db)

                                if let eventOrganizerID, eventOrganizerID != organizerID {
                                    try Self.insertOrganizerIfNeeded(eventOrganizerID, in: db)
                                }

                                try Self.insertCreatedEvent(
                                    event,
                                    eventID: eventID,
                                    eventOrganizerID: eventOrganizerID,
                                    workspace: workspace,
                                    eventWorkspace: eventWorkspace,
                                    in: db
                                )

                                let baselineDatabase = try workspaceReferenceDatabase.prepare(workspace)
                                try baselineDatabase.write { baselineDB in
                                    try Self.insertOrganizerIfNeeded(organizerID, in: baselineDB)

                                    if let eventOrganizerID, eventOrganizerID != organizerID {
                                        try Self.insertOrganizerIfNeeded(eventOrganizerID, in: baselineDB)
                                    }

                                    try Self.insertCreatedEvent(
                                        event,
                                        eventID: eventID,
                                        eventOrganizerID: eventOrganizerID,
                                        workspace: workspace,
                                        eventWorkspace: eventWorkspace,
                                        in: baselineDB
                                    )
                                }
                            }
                            try store.modify {
                                $0.errorMessage = nil
                                $0.isSaving = false
                            }
                            try store.post(
                                key: NavigationRequested.self,
                                value: .event(eventID, nil)
                            )
                            try store.dismiss()
                        } catch {
                            try store.modify {
                                $0.errorMessage = "Unable to create event."
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

    static func makeLocalEventID(from uuid: UUID) -> OMERecord.ID<OMERecord.Event> {
        OMERecord.ID<OMERecord.Event>(.init(uuid.uuidString.lowercased()))
    }

    static func insertOrganizerIfNeeded(
        _ organizerID: OMERecord.Organizer.ID,
        in db: Database
    ) throws {
        let exists = try OMERecord.Organizer
            .where { $0.id.eq(organizerID) }
            .fetchOne(db) != nil
        guard !exists else { return }

        try OMERecord.Organizer.insert {
            OMERecord.Organizer.Draft(id: organizerID)
        }
        .execute(db)
    }

    static func insertCreatedEvent(
        _ event: OMERecord.Event.Draft,
        eventID: OMERecord.Event.ID,
        eventOrganizerID: OMERecord.Organizer.ID?,
        workspace: EditingWorkspaceRecord,
        eventWorkspace: EventEditingWorkspaceRecord,
        in db: Database
    ) throws {
        try OMERecord.Event.insert {
            event
        }
        .execute(db)

        try EventSingletonStage.insert(
            eventID: eventID,
            in: db
        )

        if let startDate = event.startDate {
            try EventSingletonSchedule.insert(
                eventID: eventID,
                date: startDate,
                in: db
            )
        }

        if let eventOrganizerID {
            try OMERecord.EventOrganizer.insert {
                OMERecord.EventOrganizer.Draft(
                    id: .init(
                        organizerID: eventID.organizerID,
                        eventID: eventID.eventID,
                        eventOrganizerID: eventOrganizerID
                    )
                )
            }
            .execute(db)
        }

        try EditingWorkspaceRecord.insert {
            workspace
        }
        .execute(db)

        try EventEditingWorkspaceRecord.insert {
            eventWorkspace
        }
        .execute(db)
    }

    static func makeEventDraft(
        id: OMERecord.Event.ID,
        name: String,
        startDate: LocalDate? = nil,
        endDate: LocalDate? = nil,
        timeZone: TimeZone = .current
    ) -> OMERecord.Event.Draft {
        OMERecord.Event.Draft(
            id: id,
            name: name,
            description: nil,
            startDate: startDate,
            endDate: endDate,
            status: .known(.planned),
            mode: .known(.inPerson),
            locations: nil,
            uris: nil,
            timeZone: timeZone,
            imageURL: nil,
            iconImageURL: nil,
            siteMapImageURL: nil,
            contactNumbers: nil,
            categoryConfigs: nil
        )
    }
}

private enum CreateEventFormFieldID {
    static var eventName: AnyHashable { AnyHashable(\CreateEvent.FormValue.eventName) }
}

private extension CreateEvent.FormFeature {
    init() {
        self.init {
            Self.Field(\.eventName) {
                Validation(error: "Enter an event name.") { value in
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
        }
    }
}

struct CreateEventView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var store: StoreOf<CreateEvent>
    @State var isTimeZonePickerPresented = false

    var body: some View {
        SwiftUI.Form {
            Section {
                Text("Start with the basics. This creates the event now so you can come back and fill in artwork, schedule, locations, and the rest later")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Event Name") {
                TextField("Event Name", text: $store.form.value.eventName, prompt: Text("Testival 2026"))

                FormFieldValidationStatus(validation: store.form.validation[CreateEventFormFieldID.eventName])
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
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if store.isSaving {
                    ProgressView()
                } else {
                    Button("Create") {
                        store.send(.saveButtonTapped)
                    }
                    .disabled(!store.canSubmit)
                }
            }
        }

    }
}
