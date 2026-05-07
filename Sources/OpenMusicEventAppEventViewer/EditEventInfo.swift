import ComposableArchitecture2
import Dependencies
import Foundation
import IssueReporting
import Lexicon
import SQLiteData
import SwiftUI

@Feature
public struct EditEventInfo {
    public init() {}

    public struct State {
        public init() {
            self.draft = .placeholder
            self.timeZoneIdentifier = TimeZone.current.identifier
        }

        var draft: OMERecord.Event.Draft
        var timeZoneIdentifier: String
        var hasLoadedDraft = false
        var isSaving = false
        var errorMessage: String?

        var trimmedEventName: String {
            draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var trimmedDescription: String {
            draft.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        var trimmedCustomMode: String {
            draft.mode.customValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        var trimmedTimeZone: String {
            timeZoneIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var mode: EditEventInfoMode {
            EditEventInfoMode(draft.mode)
        }

        var validationMessage: String? {
            guard hasLoadedDraft else { return nil }
            if trimmedEventName.isEmpty {
                return "Enter an event name."
            }
            if mode == .custom && trimmedCustomMode.isEmpty {
                return "Enter a custom event mode."
            }
            if trimmedTimeZone.isEmpty || TimeZone(identifier: trimmedTimeZone) == nil {
                return "Enter a valid time zone identifier."
            }
            if let startDate = draft.startsAt, let endDate = draft.endsAt, endDate < startDate {
                return "End date must be on or after the start date."
            }
            return nil
        }

        var canSubmit: Bool {
            hasLoadedDraft && !isSaving && validationMessage == nil
        }

        var preparedDraft: OMERecord.Event.Draft {
            var draft = draft
            draft.name = trimmedEventName
            draft.description = trimmedDescription.nilIfEmpty
            if mode == .custom {
                draft.mode = .unknown(.string(trimmedCustomMode))
            }
            draft.timeZone = TimeZone(identifier: trimmedTimeZone) ?? .current
            return draft
        }
    }

    public enum Action {
        case cancelButtonTapped
        case saveButtonTapped
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.defaultEventID) var defaultEventID

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

                let draft = state.preparedDraft

                guard let validationMessage = state.validationMessage else {
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
        .onMount { state in
            guard !state.hasLoadedDraft else { return }

            do {
                if let event = try database.read({ db in
                    try OMERecord.Event.where { $0.id.eq(defaultEventID) }.fetchOne(db)
                }) {
                    state.draft = .init(event)
                    state.timeZoneIdentifier = event.timeZone.identifier
                    state.hasLoadedDraft = true
                    state.errorMessage = nil
                } else {
                    reportIssue("Unable to load the event draft for editing.")
                    state.errorMessage = "This event could not be loaded."
                }
            } catch {
                reportIssue(error)
                state.errorMessage = "This event could not be loaded."
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
        Group {
            if store.hasLoadedDraft {
                Form {
                    Section("Event Name") {
                        TextField("Event Name", text: $store.draft.name)
                    }

                    Section("Description") {
                        TextField("Description", text: $store.draft.description[coalesce: ""], axis: .vertical)
                            .lineLimit(4...8)
                    }

                    Section("Times") {
                        Toggle("Start Date", isOn: $store.draft.hasStartDate.animation())
                        if store.draft.hasStartDate {
                            DatePicker(
                                "Start Date",
                                selection: $store.draft.startsAt[coalesce: Date()],
                                displayedComponents: .date
                            )
                        }

                        Toggle("End Date", isOn: $store.draft.hasEndDate.animation())
                        if store.draft.hasEndDate {
                            DatePicker(
                                "End Date",
                                selection: $store.draft.endsAt[coalesce: Date()],
                                displayedComponents: .date
                            )
                        }

                        TextField("Time Zone", text: $store.timeZoneIdentifier)
                    }

                    Section("Details") {
                        Picker("Status", selection: $store.draft.status) {
                            ForEach(OMERecord.Event.Status.allCases, id: \.self) { status in
                                Text(status.editTitle)
                                    .tag(status)
                            }
                        }

                        Picker("Mode", selection: $store.draft.editMode) {
                            ForEach(EditEventInfoMode.allCases, id: \.self) { mode in
                                Text(mode.title)
                                    .tag(mode)
                            }
                        }

                        if store.draft.editMode == .custom {
                            TextField("Custom Mode", text: $store.draft.customModeText)
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
                    title: "Edit Event Info",
                    systemImage: "pencil",
                    description: "This event could not be loaded."
                )
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

private extension OMERecord.Event.Draft {
    static var placeholder: Self {
        .init(
            id: .init("-1"),
            name: "",
            description: nil,
            startsAt: nil,
            endsAt: nil,
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

    var hasStartDate: Bool {
        get { startsAt != nil }
        set { startsAt = newValue ? (startsAt ?? Date()) : nil }
    }

    var hasEndDate: Bool {
        get { endsAt != nil }
        set { endsAt = newValue ? (endsAt ?? Date()) : nil }
    }

    var editMode: EditEventInfoMode {
        get { .init(mode) }
        set { mode = newValue.openValue(customValue: mode.customValue ?? "") }
    }

    var customModeText: String {
        get { mode.customValue ?? "" }
        set { mode = .unknown(.string(newValue)) }
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Optional {
    subscript(coalesce coalesce: Wrapped) -> Wrapped {
        get { self ?? coalesce }
        set { self = newValue }
    }
}
