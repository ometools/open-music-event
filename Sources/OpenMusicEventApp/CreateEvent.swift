//
//  CreateEvent.swift
//  open-music-event
//
//  Created by Woodrow Melling on 5/2/26.
//

import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventLexicon
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
    @Dependency(\.uuid) var uuid

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
            self.startDateSelection = now
            self.endDateSelection = now
        }

        var organizerID: OMERecord.Organizer.ID
        var eventOrganizerID: OMERecord.Organizer.ID?

        var eventName = ""
        var hasStartDate = false
        var startDateSelection: Date
        var hasEndDate = false
        var endDateSelection: Date
        var timeZone: TimeZone = .current

        var isSaving = false
        var errorMessage: String?

        var trimmedEventName: String {
            eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var startDate: LocalDate? {
            hasStartDate ? LocalDate(startDateSelection, in: timeZone) : nil
        }

        var endDate: LocalDate? {
            hasEndDate ? LocalDate(endDateSelection, in: timeZone) : nil
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

        var validationMessage: String? {
            if !eventName.isEmpty && trimmedEventName.isEmpty {
                return "Enter an event name."
            }
            if let startDate, let endDate, endDate < startDate {
                return "End date must be on or after the start date."
            }
            return nil
        }

        var canSubmit: Bool {
            !isSaving
                && !trimmedEventName.isEmpty
                && validationMessage == nil
        }
    }

    public enum Action {
        case saveButtonTapped
    }


    public var body: some Feature {
        Update { state, action in
            switch action {
            case .saveButtonTapped:
                guard !state.isSaving else { return }

                guard !state.trimmedEventName.isEmpty else {
                    state.errorMessage = "Enter an event name."
                    return
                }

                guard let validationMessage = state.validationMessage else {
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

                    state.errorMessage = nil
                    state.isSaving = true
                    let organizerID = state.organizerID
                    let eventOrganizerID = state.eventOrganizerID

                    store.addTask {
                        do {
                            try database.write { db in
                                try OMERecord.Organizer.insert {
                                    OMERecord.Organizer.Draft(id: organizerID)
                                }
                                .execute(db)

                                if let eventOrganizerID, eventOrganizerID != organizerID {
                                    try OMERecord.Organizer.insert {
                                        OMERecord.Organizer.Draft(id: eventOrganizerID)
                                    }
                                    .execute(db)
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
                            }
                            try store.modify {
                                $0.errorMessage = nil
                                $0.isSaving = false

                            }
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
        }
    }

    static func makeLocalEventID(from uuid: UUID) -> OMERecord.ID<OMERecord.Event> {
        OMERecord.ID<OMERecord.Event>(.init(uuid.uuidString.lowercased()))
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

struct CreateEventView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var store: StoreOf<CreateEvent>
    @State var isTimeZonePickerPresented = false

    var body: some View {
        Form {
            Section {
                Text("Start with the basics. This creates the event now so you can come back and fill in artwork, schedule, locations, and the rest later")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Event Name") {
                TextField("Event Name", text: $store.eventName, prompt: Text("Testival 2026"))

                if let validationMessage = store.validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Start Date", isOn: $store.hasStartDate.animation())
                if store.hasStartDate {
                    DatePicker(
                        "Start Date",
                        selection: $store.startDateSelection,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .environment(\.timeZone, store.timeZone)
                }

                Toggle("Add End Date", isOn: $store.hasEndDate.animation())
                if store.hasEndDate {
                    DatePicker(
                        "End Date",
                        selection: $store.endDateSelection,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .environment(\.timeZone, store.timeZone)
                }

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
