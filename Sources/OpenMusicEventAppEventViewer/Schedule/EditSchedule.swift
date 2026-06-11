import ComposableArchitecture2
import Dependencies
import Foundation
import SQLiteData
import SwiftUI

@Feature
public struct EditSchedule {
    public init() {}

    @Dependency(\.defaultDatabase) var database

    public struct State: Identifiable {
        public init(eventID: OMERecord.Event.ID, timeZone: TimeZone) {
            @Dependency(\.date) var date

            let now = date()
            self.dateSelection = now
            self.eventID = eventID
            self.sourceFileName = LocalDate(now, in: timeZone).description
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

        public var id: OMERecord.Event.ID { eventID }

        public var canSubmit: Bool {
            !isSaving && validationMessage == nil
        }

        public var scheduleDate: LocalDate {
            LocalDate(dateSelection, in: timeZone)
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
                TextField("Title", text: $store.customTitle, prompt: Text("Friday"))
                TextField("Source File", text: $store.sourceFileName, prompt: Text("friday"))
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
