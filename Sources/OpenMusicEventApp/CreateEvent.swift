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
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import OpenMusicEventTimeZones
import SQLiteData
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

    public struct FormValue: Equatable {
        var endDateSelection: Date
        var eventName = ""
        var hasEndDate = false
        var hasStartDate = false
        var sourceEventDirectory: String?
        var startDateSelection: Date
        var timeZone: TimeZone = .current

        init(
            now: Date,
            sourceEventDirectory: String? = nil
        ) {
            self.endDateSelection = now
            self.sourceEventDirectory = sourceEventDirectory
            self.startDateSelection = now
        }
    }

    public typealias FormFeature = ComposableForms.Form<FormValue>

    public struct State {
        public struct SourceContext: Equatable, Sendable {
            public init(
                sourceBaselineID: SourceBaselineRecord.ID,
                sourceKind: OMERecord.SourceDatabaseInsertion.SourceKind,
                sourceReference: String,
                ref: String?,
                calendarID: OMERecord.Calendar.ID,
                sourceEventDirectory: String = ""
            ) {
                self.sourceBaselineID = sourceBaselineID
                self.sourceKind = sourceKind
                self.sourceReference = sourceReference
                self.ref = ref
                self.calendarID = calendarID
                self.sourceEventDirectory = sourceEventDirectory
            }

            public init(
                sourceBaseline: SourceBaselineRecord,
                calendarID: OMERecord.Calendar.ID,
                sourceEventDirectory: String = ""
            ) {
                self.init(
                    sourceBaselineID: sourceBaseline.id,
                    sourceKind: sourceBaseline.sourceKind,
                    sourceReference: sourceBaseline.sourceReference,
                    ref: sourceBaseline.ref,
                    calendarID: calendarID,
                    sourceEventDirectory: sourceEventDirectory
                )
            }

            public var calendarID: OMERecord.Calendar.ID
            public var ref: String?
            public var sourceBaselineID: SourceBaselineRecord.ID
            public var sourceEventDirectory: String
            public var sourceKind: OMERecord.SourceDatabaseInsertion.SourceKind
            public var sourceReference: String

            var sourceProvenance: OMERecord.SourceDatabaseInsertion.SourceProvenance {
                OMERecord.SourceDatabaseInsertion.SourceProvenance(
                    kind: sourceKind,
                    reference: sourceReference,
                    ref: ref
                )
            }

            var trimmedSourceEventDirectory: String {
                sourceEventDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        public init(
            organizerID: OMERecord.Organizer.ID? = nil,
            eventOrganizerID: OMERecord.Organizer.ID? = nil,
            sourceContext: SourceContext? = nil
        ) {
            @Dependency(\.appEventOrganizerID) var appEventOrganizerID
            @Dependency(\.date) var date
            let now = date()
            self.organizerID = organizerID ?? appEventOrganizerID
            self.eventOrganizerID = eventOrganizerID
            self.sourceContext = sourceContext
            self.form = FormFeature.State(
                value: FormValue(
                    now: now,
                    sourceEventDirectory: sourceContext.map(\.sourceEventDirectory)
                )
            )
        }

        var organizerID: OMERecord.Organizer.ID
        var eventOrganizerID: OMERecord.Organizer.ID?
        var sourceContext: SourceContext?

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

        var sourceEventDirectory: String {
            get { form.value.sourceEventDirectory ?? "" }
            set { form.value.sourceEventDirectory = newValue }
        }

        var startDateSelection: Date {
            get { form.value.startDateSelection }
            set { form.value.startDateSelection = newValue }
        }

        var trimmedSourceEventDirectory: String {
            sourceEventDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
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
            if let startDate, let endDate, endDate < startDate {
                return "End date must be on or after the start date."
            }
            if sourceContext != nil {
                if trimmedSourceEventDirectory.isEmpty {
                    return "Enter a source slug."
                }
                if !CreateEvent.isValidSourceEventDirectory(trimmedSourceEventDirectory) {
                    return "Use a single source slug like 2026-pre-party-kelowna."
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
                    let sourceContext = state.sourceContext
                    let sourceEventDirectory = state.trimmedSourceEventDirectory
                    let localEventID = sourceContext.map {
                        OMERecord.SourceDatabaseInsertion.inferredEventID(
                            eventDirectoryName: sourceEventDirectory,
                            sourceProvenance: $0.sourceProvenance
                        )
                    } ?? Self.makeLocalEventID(from: uuid())
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

                    state.errorMessage = nil
                    state.isSaving = true
                    let organizerID = state.organizerID
                    let eventOrganizerID = state.eventOrganizerID
                    let createdAt = date()

                    store.addTask {
                        do {
                            try database.write { db in
                                if let sourceContext {
                                    let duplicateCount = try EventSourceProvenanceRecord
                                        .where { $0.sourceBaselineID.eq(sourceContext.sourceBaselineID) }
                                        .where { $0.sourceEventDirectory.eq(sourceEventDirectory) }
                                        .fetchCount(db)
                                    guard duplicateCount == 0 else {
                                        throw SaveError.duplicateSourceEventDirectory
                                    }
                                }

                                try Self.insertOrganizerIfNeeded(organizerID, in: db)

                                if let eventOrganizerID, eventOrganizerID != organizerID {
                                    try Self.insertOrganizerIfNeeded(eventOrganizerID, in: db)
                                }

                                try OMERecord.Event.insert {
                                    event
                                }
                                .execute(db)

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

                                if let sourceContext {
                                    try OMERecord.CalendarEntry.insert {
                                        OMERecord.CalendarEntry.Draft(
                                            id: .init(
                                                calendarOwnerID: sourceContext.calendarID.ownerID,
                                                calendarID: sourceContext.calendarID.calendarID,
                                                entryID: OMERecord.ID<OMERecord.CalendarEntry>(
                                                    localEventID.rawValue
                                                )
                                            ),
                                            event: OMERecord.Event.reference(id: eventID),
                                            createdAt: createdAt,
                                            note: nil,
                                            pinned: false
                                        )
                                    }
                                    .execute(db)

                                    try EventSourceProvenanceRecord.insert {
                                        EventSourceProvenanceRecord(
                                            id: eventID,
                                            sourceBaselineID: sourceContext.sourceBaselineID,
                                            sourceKind: sourceContext.sourceKind,
                                            sourceReference: sourceContext.sourceReference,
                                            ref: sourceContext.ref,
                                            eventIDOrigin: .inferred,
                                            sourceEventDirectory: sourceEventDirectory
                                        )
                                    }
                                    .execute(db)
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
                        } catch SaveError.duplicateSourceEventDirectory {
                            try store.modify {
                                $0.errorMessage = "An event already uses that source slug."
                                $0.isSaving = false
                            }
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

    private enum SaveError: Error, Sendable {
        case duplicateSourceEventDirectory
    }

    static func isValidSourceEventDirectory(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
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
    static var sourceEventDirectory: AnyHashable { AnyHashable(\CreateEvent.FormValue.sourceEventDirectory) }
}

private extension CreateEvent.FormFeature {
    init() {
        self.init {
            Self.Field(\.eventName) {
                Validation(error: "Enter an event name.") { value in
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }

            Self.Field(\.sourceEventDirectory) {
                Validation { value -> ValidationResult in
                    guard let value else { return .valid }

                    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedValue.isEmpty else {
                        return .invalid("Enter a source slug.")
                    }
                    guard CreateEvent.isValidSourceEventDirectory(trimmedValue) else {
                        return .invalid("Use a single source slug like 2026-pre-party-kelowna.")
                    }
                    return .valid
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

            if store.sourceContext != nil {
                Section {
                    TextField(
                        "Slug",
                        text: $store.sourceEventDirectory,
                        prompt: Text("2026-pre-party-kelowna")
                    )
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()

                    FormFieldValidationStatus(
                        validation: store.form.validation[CreateEventFormFieldID.sourceEventDirectory]
                    )
                } header: {
                    Text("Source")
                } footer: {
                    Text("The proposal will add this event under events/\(store.trimmedSourceEventDirectory.isEmpty ? "slug" : store.trimmedSourceEventDirectory).")
                }
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
                .buttonStyle(.plain)
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
