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
import SQLiteData
import SwiftUI

@Feature
public struct CreateEvent {
    public init() {}

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.uuid) var uuid

    public struct State {
        public init() {
            @Dependency(\.date) var date
            let now = date()
            self.startDateSelection = now
            self.endDateSelection = now
        }

        var eventName = ""
        var hasStartDate = false
        var startDateSelection: Date
        var hasEndDate = false
        var endDateSelection: Date

        var isSaving = false
        var errorMessage: String?

        var trimmedEventName: String {
            eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var startDate: LocalDate? {
            hasStartDate ? LocalDate(startDateSelection, in: .current) : nil
        }

        var endDate: LocalDate? {
            hasEndDate ? LocalDate(endDateSelection, in: .current) : nil
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
                    let eventID = Self.makeEventID(from: uuid())
                    let event = Self.makeEventDraft(
                        id: eventID,
                        name: state.trimmedEventName,
                        startDate: state.startDate,
                        endDate: state.endDate
                    )

                    state.errorMessage = nil
                    state.isSaving = true

                    store.addTask {
                        do {
                            try database.write { db in
                                try OMERecord.Event.insert {
                                    event
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

    static func makeEventID(from uuid: UUID) -> OMERecord.Event.ID {
        OMERecord.Event.ID(.init(uuid.uuidString.lowercased()))
    }

    static func makeEventDraft(
        id: OMERecord.Event.ID,
        name: String,
        startDate: LocalDate? = nil,
        endDate: LocalDate? = nil
    ) -> OMERecord.Event.Draft {
        OMERecord.Event.Draft(
            id: id,
            name: name,
            description: nil,
            startDate: startDate,
            endDate: endDate,
            status: .planned,
            mode: .known(.inPerson),
            locations: nil,
            uris: nil,
            timeZone: TimeZone.current,
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
                }

                Toggle("Add End Date", isOn: $store.hasEndDate.animation())
                if store.hasEndDate {
                    DatePicker(
                        "End Date",
                        selection: $store.endDateSelection,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                }
            } header: {
                Text("Dates")
            } footer: {
                Text("Dates are saved as local calendar dates in \(TimeZone.current.identifier).")
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
