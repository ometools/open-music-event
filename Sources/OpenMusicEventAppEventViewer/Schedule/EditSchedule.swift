import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
import SQLiteData
import SwiftUI

@Feature
public struct EditSchedule {
    public init() {}

    @Dependency(\.defaultDatabase) var database

    public struct State: Identifiable {
        public init(
            eventID: OMERecord.Event.ID,
            initialDate: LocalDate? = nil,
            timeZone: TimeZone
        ) {
            @Dependency(\.date) var date

            let dateSelection = initialDate?.atStartOfDay(in: timeZone) ?? date()
            let scheduleDate = LocalDate(dateSelection, in: timeZone)
            let defaults = Self.defaults(for: scheduleDate, in: timeZone)
            self.dateSelection = dateSelection
            self.eventID = eventID
            self.generatedScheduleDate = scheduleDate
            self.customTitle = defaults.customTitle
            self.sourceFileName = defaults.sourceFileName
            self.timeZone = timeZone
        }

        public let eventID: OMERecord.Event.ID
        @DebugSnapshotIgnored
        public let timeZone: TimeZone

        public var customTitle = ""
        public var dateSelection: Date
        public var errorMessage: String?
        public var isSaving = false
        public var sourceFileName: String
        private var generatedScheduleDate: LocalDate

        public var id: OMERecord.Event.ID { eventID }

        public var canSubmit: Bool {
            !isSaving && validationMessage == nil
        }

        public var scheduleDate: LocalDate {
            LocalDate(dateSelection, in: timeZone)
        }

        public var inferredTitle: String {
            Self.weekdayTitle(for: scheduleDate, in: timeZone)
        }

        public var trimmedCustomTitle: String {
            customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public var trimmedSourceFileName: String {
            sourceFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public var validationMessage: String? {
            if trimmedSourceFileName.isEmpty {
                return "Enter a source file name."
            }
            if !Self.isValidSourceFileName(trimmedSourceFileName) {
                return "Use a file name like friday or 2026-08-01."
            }
            return nil
        }

        mutating func dateSelectionChanged() {
            let newScheduleDate = scheduleDate
            guard generatedScheduleDate != newScheduleDate else { return }

            let oldDefaults = Self.defaults(for: generatedScheduleDate, in: timeZone)
            let newDefaults = Self.defaults(for: newScheduleDate, in: timeZone)
            if customTitle == oldDefaults.customTitle {
                customTitle = newDefaults.customTitle
            }
            if sourceFileName == oldDefaults.sourceFileName {
                sourceFileName = newDefaults.sourceFileName
            }
            generatedScheduleDate = newScheduleDate
        }

        fileprivate struct SaveRequest: Sendable {
            var customTitle: String?
            var eventID: OMERecord.Event.ID
            var scheduleDate: LocalDate
            var sourceFileName: String

            init(state: State) {
                self.customTitle = state.trimmedCustomTitle.nilIfEmpty
                self.eventID = state.eventID
                self.scheduleDate = state.scheduleDate
                self.sourceFileName = state.trimmedSourceFileName
            }
        }

        fileprivate static func scheduleID(
            for request: SaveRequest,
            in db: Database
        ) throws -> OMERecord.ID<OMERecord.Schedule> {
            let base = request.sourceFileName
            var candidate = base
            var suffix = 2

            while true {
                let exists = try OMERecord.Schedule
                    .where { $0.id.organizerID.eq(request.eventID.organizerID) }
                    .where { $0.id.eventID.eq(request.eventID.eventID) }
                    .where { $0.id.scheduleID.eq(localID(candidate)) }
                    .fetchOne(db) != nil
                guard exists else { return localID(candidate) }
                candidate = "\(base)-\(suffix)"
                suffix += 1
            }
        }

        fileprivate static func scheduleDraft(
            for request: SaveRequest,
            scheduleID: OMERecord.ID<OMERecord.Schedule>
        ) -> OMERecord.Schedule.Draft {
            OMERecord.Schedule.Draft(
                id: OMERecord.Schedule.ID(
                    organizerID: request.eventID.organizerID,
                    eventID: request.eventID.eventID,
                    scheduleID: scheduleID
                ),
                date: request.scheduleDate,
                startsAt: nil,
                endsAt: nil,
                customTitle: request.customTitle
            )
        }
        private static func isValidSourceFileName(_ value: String) -> Bool {
            !value.isEmpty
                && value != "."
                && value != ".."
                && !value.contains("/")
                && !value.contains("\\")
        }

        private static func localID(_ string: String) -> OMERecord.ID<OMERecord.Schedule> {
            OMERecord.ID<OMERecord.Schedule>(.init(string))
        }

        private struct Defaults: Equatable {
            var customTitle: String
            var sourceFileName: String
        }

        private static func defaults(
            for scheduleDate: LocalDate,
            in timeZone: TimeZone
        ) -> Defaults {
            return Defaults(
                customTitle: "",
                sourceFileName: scheduleDate.description
            )
        }

        private static func weekdayTitle(
            for scheduleDate: LocalDate,
            in timeZone: TimeZone
        ) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "EEEE"
            return formatter.string(from: scheduleDate.atStartOfDay(in: timeZone))
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
                guard let validationMessage = state.validationMessage else {
                    state.errorMessage = nil
                    state.isSaving = true
                    let request = State.SaveRequest(state: state)

                    store.addTask {
                        do {
                            try database.write { db in
                                try EditScheduleDrafts.insert(request, in: db)
                            }
                            try store.modify {
                                $0.errorMessage = nil
                                $0.isSaving = false
                            }
                            try store.dismiss()
                        } catch {
                            try store.modify {
                                $0.errorMessage = "Unable to create schedule."
                                $0.isSaving = false
                            }
                        }
                    }
                    return
                }

                state.errorMessage = validationMessage
            }
        }
        .onChange(of: store.dateSelection) { state in
            state.dateSelectionChanged()
        }
    }
}

fileprivate enum EditScheduleDrafts {
    static func insert(_ request: EditSchedule.State.SaveRequest, in db: Database) throws {
        let scheduleID = try EditSchedule.State.scheduleID(for: request, in: db)
        try OMERecord.Schedule.insert {
            EditSchedule.State.scheduleDraft(
                for: request,
                scheduleID: scheduleID
            )
        }
        .execute(db)
    }
}

public struct EditScheduleView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var store: StoreOf<EditSchedule>

    public init(store: StoreOf<EditSchedule>) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("Date") {
                DatePicker(
                    "Date",
                    selection: $store.dateSelection,
                    displayedComponents: .date
                )
                .environment(\.timeZone, store.timeZone)
            }

            Section("Details") {
                TextField("Title", text: $store.customTitle, prompt: Text(store.inferredTitle))
                TextField("Source File", text: $store.sourceFileName, prompt: Text(store.scheduleDate.description))
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
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
        .navigationTitle("New Schedule")
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
