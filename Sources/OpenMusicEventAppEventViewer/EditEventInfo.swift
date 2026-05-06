import ComposableArchitecture2
import Dependencies
import Foundation
import Lexicon
import SQLiteData
import SwiftUI

@Feature
public struct EditEventInfo {
    public init() {}

    public struct State {
        @FetchOne(OMERecord.Event.defaultEvent) public var event: OMERecord.Event?

        public init() {
            @Dependency(\.date) var date
            self.startDate = date()
            self.endDate = date()
            self.timeZone = TimeZone.current.identifier
        }

        var eventName = ""
        var eventDescription = ""
        var hasLoadedFormValues = false
        var hasStartDate = false
        var startDate: Date
        var hasEndDate = false
        var endDate: Date
        var status: OMERecord.Event.Status = .planned
        var mode = EditEventInfoMode.inPerson
        var customMode = ""
        var timeZone: String
        var isSaving = false
        var errorMessage: String?

        var trimmedEventName: String {
            eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var trimmedDescription: String {
            eventDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var trimmedCustomMode: String {
            customMode.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var trimmedTimeZone: String {
            timeZone.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var descriptionValue: String? {
            trimmedDescription.isEmpty ? nil : trimmedDescription
        }

        var modeValue: Open<OMERecord.Event.Mode> {
            mode.openValue(customValue: trimmedCustomMode)
        }

        var startDateValue: Date? {
            hasStartDate ? startDate : nil
        }

        var endDateValue: Date? {
            hasEndDate ? endDate : nil
        }

        var validationMessage: String? {
            if trimmedEventName.isEmpty {
                return "Enter an event name."
            }
            if mode == .custom && trimmedCustomMode.isEmpty {
                return "Enter a custom event mode."
            }
            if trimmedTimeZone.isEmpty {
                return "Enter a time zone."
            }
            if let startDate = startDateValue, let endDate = endDateValue, endDate < startDate {
                return "End date must be on or after the start date."
            }
            return nil
        }

        var canSubmit: Bool {
            !isSaving && validationMessage == nil
        }

        mutating func hydrate(from event: OMERecord.Event) {
            guard !hasLoadedFormValues else { return }
            eventName = event.name
            eventDescription = event.description ?? ""
            hasStartDate = event.startsAt != nil
            startDate = event.startsAt ?? startDate
            hasEndDate = event.endsAt != nil
            endDate = event.endsAt ?? endDate
            status = event.status
            mode = EditEventInfoMode(event.mode)
            customMode = event.mode.customValue ?? ""
            timeZone = event.timeZone
            hasLoadedFormValues = true
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

                guard let event = state.event else {
                    state.errorMessage = "This event could not be loaded."
                    return
                }

                guard let validationMessage = state.validationMessage else {
                    let updatedEvent = OMERecord.Event.Draft(
                        id: event.id,
                        name: state.trimmedEventName,
                        description: state.descriptionValue,
                        startsAt: state.startDateValue,
                        endsAt: state.endDateValue,
                        status: state.status,
                        mode: state.modeValue,
                        locations: event.locations,
                        uris: event.uris,
                        timeZone: state.trimmedTimeZone,
                        imageURL: event.imageURL,
                        iconImageURL: event.iconImageURL,
                        siteMapImageURL: event.siteMapImageURL,
                        contactNumbers: event.contactNumbers,
                        categoryConfigs: event.categoryConfigs
                    )

                    state.errorMessage = nil
                    state.isSaving = true

                    store.addTask {
                        do {
                            try database.write { db in
                                try OMERecord.Event.upsert {
                                    updatedEvent
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
                                $0.errorMessage = "Unable to save event changes."
                                $0.isSaving = false
                            }
                        }
                    }
                    return
                }

                state.errorMessage = validationMessage
            }
        }
        .onChange(of: store.event, initial: true) { _, event, state in
            if let event {
                state.hydrate(from: event)
            }
        }
    }
}

public struct EditEventInfoView: View {
    @Bindable var store: StoreOf<EditEventInfo>

    public init(store: StoreOf<EditEventInfo>) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("Event Name") {
                TextField("Event Name", text: $store.eventName)
            }

            Section("Description") {
                TextField("Description", text: $store.eventDescription, axis: .vertical)
                    .lineLimit(4...8)
            }

            Section("Dates") {
                Toggle("Start Date", isOn: $store.hasStartDate.animation())
                if store.hasStartDate {
                    DatePicker(
                        "Start Date",
                        selection: $store.startDate,
                        displayedComponents: .date
                    )
                }

                Toggle("End Date", isOn: $store.hasEndDate.animation())
                if store.hasEndDate {
                    DatePicker(
                        "End Date",
                        selection: $store.endDate,
                        displayedComponents: .date
                    )
                }
            }

            Section("Details") {
                Picker("Status", selection: $store.status) {
                    ForEach(OMERecord.Event.Status.allCases, id: \.self) { status in
                        Text(status.editTitle)
                            .tag(status)
                    }
                }

                Picker("Mode", selection: $store.mode) {
                    ForEach(EditEventInfoMode.allCases, id: \.self) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }

                if store.mode == .custom {
                    TextField("Custom Mode", text: $store.customMode)
                }

                TextField("Time Zone", text: $store.timeZone)
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
        .navigationTitle("Edit Event Info")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    store.send(.cancelButtonTapped)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if store.isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        store.send(.saveButtonTapped)
                    }
                    .disabled(!store.canSubmit)
                }
            }
        }
    }
}

public enum EditEventInfoMode: String, CaseIterable, Hashable, Sendable {
    case inPerson
    case virtual
    case hybrid
    case custom

    init(_ mode: Open<OMERecord.Event.Mode>) {
        switch mode {
        case .known(.inPerson):
            self = .inPerson
        case .known(.virtual):
            self = .virtual
        case .known(.hybrid):
            self = .hybrid
        case .unknown:
            self = .custom
        }
    }

    var title: String {
        switch self {
        case .inPerson:
            "In Person"
        case .virtual:
            "Virtual"
        case .hybrid:
            "Hybrid"
        case .custom:
            "Custom"
        }
    }

    func openValue(customValue: String) -> Open<OMERecord.Event.Mode> {
        switch self {
        case .inPerson:
            .known(.inPerson)
        case .virtual:
            .known(.virtual)
        case .hybrid:
            .known(.hybrid)
        case .custom:
            .unknown(.string(customValue))
        }
    }
}

private extension Open where Known == OMERecord.Event.Mode {
    var customValue: String? {
        guard case let .unknown(value) = self else { return nil }
        return value.stringValue
    }
}

extension OMERecord.Event.Status: CaseIterable {
    public static var allCases: [Self] {
        [
            .planned,
            .scheduled,
            .rescheduled,
            .cancelled,
            .postponed,
        ]
    }
}

private extension OMERecord.Event.Status {
    var editTitle: String {
        switch self {
        case .planned:
            "Planned"
        case .scheduled:
            "Scheduled"
        case .rescheduled:
            "Rescheduled"
        case .cancelled:
            "Cancelled"
        case .postponed:
            "Postponed"
        }
    }
}
