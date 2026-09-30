import ATProto
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventLexicon
import OpenMusicEventTimeZones
import SQLiteData
import SwiftUITabFeatures
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct EditEventInfo {
    public init() {}

    public struct State {
        public init(event: Event) {
            @Dependency(\.date.now) var now
            self.original = event
            self.draft = event
            self.defaultDate = now
        }

        let original: Event
        @DebugSnapshotTracked var draft: Event
        let defaultDate: Date
        @DebugSnapshotTracked var isSaving = false
        @DebugSnapshotTracked var errorMessage: String?

        public var eventID: Event.ID { original.id }

        var preparedRecord: Event {
            var record = draft
            if record.name != original.name {
                record.name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if record.description != original.description {
                record.description = record.description?
                    .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
            if record.status != original.status, let custom = record.status?.customValue {
                record.status = .unknown(.string(custom.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            if record.mode != original.mode, let custom = record.mode?.customValue {
                record.mode = .unknown(.string(custom.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            return record
        }

        var validationMessage: String? {
            let record = preparedRecord
            if record.name.isEmpty { return "Enter an event name." }
            if record.status?.customValue == "" { return "Enter a custom event status." }
            if record.mode?.customValue == "" { return "Enter a custom event mode." }
            if let start = record.start?.date(in: record.timeZone),
               let end = record.end?.date(in: record.timeZone),
               (record.start.precision == .day || record.end.precision == .day
                ? LocalDate(end, in: record.timeZone) < LocalDate(start, in: record.timeZone)
                : end < start) {
                return "End must be on or after the start."
            }
            do {
                try record.validateReferences()
            } catch {
                return "Check the event values: \(error.localizedDescription)"
            }
            return nil
        }

        var canSubmit: Bool { !isSaving && validationMessage == nil }
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
                store.addTask { try store.dismiss() }

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                if let message = state.validationMessage {
                    state.errorMessage = message
                    return
                }
                let record = state.preparedRecord
                let original = state.original
                state.errorMessage = nil
                state.isSaving = true
                store.addTask {
                    do {
                        try database.write { db in
                            guard let current = try Event.find(original.id).fetchOne(db) else {
                                throw SaveError.deleted
                            }
                            guard current == original else { throw SaveError.changed }
                            try record.validateReferences()
                            try Event.upsert { record }.execute(db)
                        }
                        try store.modify { $0.isSaving = false }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = (error as? SaveError)?.message
                                ?? "Unable to save event changes."
                            $0.isSaving = false
                        }
                    }
                }
            }
        }
    }

    private enum SaveError: Error {
        case changed, deleted

        var message: String {
            switch self {
            case .changed: "This event changed while you were editing. Reopen the form to edit the latest version."
            case .deleted: "This event is no longer available."
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
                TextField("Event Name", text: $store.draft.name)
            }
            Section("Description") {
                PortableTextField("Description", text: $store.draft.description[coalesce: ""], axis: .vertical)
                    .portableLineLimit(4...8)
            }
            Section("Times") {
                EventBoundaryPicker(
                    title: "Start", value: $store.draft.start,
                    timeZone: store.draft.timeZone, defaultDate: store.defaultDate
                )
                EventBoundaryPicker(
                    title: "End", value: $store.draft.end,
                    timeZone: store.draft.timeZone, defaultDate: store.defaultDate
                )
                NavigationLink {
                    TimeZonePicker(selection: $store.draft.timeZone)
                } label: {
                    LabeledContent("Time Zone", value: store.draft.timeZone.identifier)
                }
                .navigationLinkListRowStyle()
            }
            Section("Details") {
                Picker("Status", selection: $store.draft.editStatus) {
                    ForEach(EditEventInfoStatus.allCases, id: \.self) { status in
                        Text(status.title).tag(status)
                    }
                }
                if store.draft.editStatus == .custom {
                    TextField("Custom Status", text: $store.draft.customStatusText)
                }
                Picker("Mode", selection: $store.draft.editMode) {
                    ForEach(EditEventInfoMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                if store.draft.editMode == .custom {
                    TextField("Custom Mode", text: $store.draft.customModeText)
                }
            }
            if let message = store.errorMessage ?? store.validationMessage {
                Section {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .disabled(store.isSaving)
        .navigationTitle("Edit Event Info")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { store.send(.cancelButtonTapped) } label: {
                    Label("Cancel", systemImage: "xmark").labelStyle(.iconOnly)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                SubmitButton(isInProgress: store.isSaving, isDisabled: !store.canSubmit) {
                    store.send(.saveButtonTapped)
                }
            }
        }
    }
}

struct EventBoundaryPicker: View {
    let title: String
    @Binding var value: Open<Event.Time>?
    let timeZone: TimeZone
    let defaultDate: Date

    var body: some View {
        Picker(title, selection: Binding(
            get: { value.precision },
            set: { precision in
                let date = value?.date(in: timeZone) ?? defaultDate
                switch precision {
                case .unspecified: value = nil
                case .day: value = .known(.day(.init(value: LocalDate(date, in: timeZone))))
                case .time: value = .known(.time(.init(value: .init(date.ISO8601Format()))))
                case .unknown: break
                }
            }
        )) {
            Text("Unspecified").tag(EventBoundaryPrecision.unspecified)
            Text("Day").tag(EventBoundaryPrecision.day)
            Text("Exact time").tag(EventBoundaryPrecision.time)
            if value.precision == .unknown {
                Text("Unsupported format").tag(EventBoundaryPrecision.unknown)
            }
        }
        if value.precision == .day || value.precision == .time {
            DatePicker(
                title,
                selection: Binding(
                    get: { value?.date(in: timeZone) ?? defaultDate },
                    set: { date in
                        if value.precision == .day {
                            value = .known(.day(.init(value: LocalDate(date, in: timeZone))))
                        } else {
                            value = .known(.time(.init(value: .init(date.ISO8601Format()))))
                        }
                    }
                ),
                displayedComponents: value.precision == .day ? [.date] : [.date, .hourAndMinute]
            )
            .environment(\.timeZone, timeZone)
        }
    }
}

private enum EventBoundaryPrecision: Hashable {
    case unspecified, day, time, unknown
}

private extension Optional where Wrapped == Open<Event.Time> {
    var precision: EventBoundaryPrecision {
        switch self {
        case nil: .unspecified
        case .known(.day): .day
        case .known(.time): .time
        case .unknown: .unknown
        }
    }
}

extension Open where Known == Event.Time {
    public func date(in timeZone: TimeZone) -> Date? {
        switch self {
        case let .known(.day(day)):
            day.value.atStartOfDay(in: timeZone)
        case let .known(.time(instant)):
            (try? Date(instant.value.rawValue, strategy: .iso8601.time(includingFractionalSeconds: true)))
                ?? (try? Date(instant.value.rawValue, strategy: .iso8601))
        case .unknown:
            nil
        }
    }
}

public enum EditEventInfoStatus: String, CaseIterable, Hashable, Sendable {
    case unspecified
    case planned
    case scheduled
    case rescheduled
    case cancelled
    case postponed
    case custom

    init(_ status: Open<Event.Status>?) {
        guard let status else {
            self = .unspecified
            return
        }

        switch status {
        case .known(.planned):
            self = .planned
        case .known(.scheduled):
            self = .scheduled
        case .known(.rescheduled):
            self = .rescheduled
        case .known(.cancelled):
            self = .cancelled
        case .known(.postponed):
            self = .postponed
        case .unknown:
            self = .custom
        }
    }

    var title: String {
        switch self {
        case .unspecified:
            "Unspecified"
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
        case .custom:
            "Custom"
        }
    }

    func openValue(customValue: String) -> Open<Event.Status>? {
        switch self {
        case .unspecified:
            nil
        case .planned:
            .known(.planned)
        case .scheduled:
            .known(.scheduled)
        case .rescheduled:
            .known(.rescheduled)
        case .cancelled:
            .known(.cancelled)
        case .postponed:
            .known(.postponed)
        case .custom:
            .unknown(.string(customValue))
        }
    }
}

public enum EditEventInfoMode: String, CaseIterable, Hashable, Sendable {
    case unspecified
    case inPerson
    case virtual
    case hybrid
    case custom

    init(_ mode: Open<Event.Mode>?) {
        guard let mode else {
            self = .unspecified
            return
        }

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
        case .unspecified:
            "Unspecified"
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

    func openValue(customValue: String) -> Open<Event.Mode>? {
        switch self {
        case .unspecified:
            nil
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

private extension Open where Known == Event.Status {
    var customValue: String? {
        guard case let .unknown(value) = self else { return nil }
        return value.string
    }
}

private extension Open where Known == Event.Mode {
    var customValue: String? {
        guard case let .unknown(value) = self else { return nil }
        return value.string
    }
}

private extension Event {
    var editStatus: EditEventInfoStatus {
        get { .init(status) }
        set { status = newValue.openValue(customValue: status?.customValue ?? "") }
    }

    var customStatusText: String {
        get { status?.customValue ?? "" }
        set { status = .some(.unknown(.string(newValue))) }
    }

    var editMode: EditEventInfoMode {
        get { .init(mode) }
        set { mode = newValue.openValue(customValue: mode?.customValue ?? "") }
    }

    var customModeText: String {
        get { mode?.customValue ?? "" }
        set { mode = .some(.unknown(.string(newValue))) }
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
