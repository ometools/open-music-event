import OpenMusicEventLexicon
import ATProtoTypes
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventComponents
import OpenMusicEventDatabase
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@Feature
public struct EditSchedule {
    public init() {}

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.date) var date

    public struct State: Identifiable {
        public init(
            eventID: Event.ID,
            initialDate: LocalDate? = nil,
            timeZone: TimeZone
        ) {
            @Dependency(\.date) var date

            let dateSelection = initialDate?.atStartOfDay(in: timeZone) ?? date()
            self.dateSelection = dateSelection
            self.eventID = eventID
            self.scheduleID = nil
            self.customTitle = ""
            self.timeZone = timeZone
        }

        public init(schedule: Schedule, timeZone: TimeZone) {
            self.dateSelection = schedule.date.atStartOfDay(in: timeZone)
            self.eventID = schedule.event
            self.scheduleID = schedule.id
            self.customTitle = schedule.title ?? ""
            self.timeZone = timeZone
        }

        public let eventID: Event.ID
        public let scheduleID: Schedule.ID?
        @DebugSnapshotIgnored
        public let timeZone: TimeZone

        public var customTitle: String
        public var dateSelection: Date
        public var errorMessage: String?
        public var isSaving = false

        public var id: Schedule.ID { scheduleID ?? eventID }

        public var canSubmit: Bool {
            !isSaving
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

        fileprivate struct SaveRequest: Sendable {
            var title: String?
            var eventID: Event.ID
            var scheduleID: Schedule.ID?
            var scheduleDate: LocalDate
            var createdAt: Date

            init(state: State, createdAt: Date) {
                self.title = state.trimmedCustomTitle.nilIfEmpty
                self.eventID = state.eventID
                self.scheduleID = state.scheduleID
                self.scheduleDate = state.scheduleDate
                self.createdAt = createdAt
            }
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
        case deleteButtonTapped
    }

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .saveButtonTapped:
                guard !state.isSaving else { return }
                state.errorMessage = nil
                state.isSaving = true
                let request = State.SaveRequest(state: state, createdAt: date())

                store.addTask {
                    do {
                        try database.write { db in
                            if let scheduleID = request.scheduleID {
                                try ScheduleRecordEditing.update(
                                    scheduleID,
                                    eventID: request.eventID,
                                    date: request.scheduleDate,
                                    title: request.title,
                                    in: db
                                )
                            } else {
                                _ = try ScheduleRecordEditing.create(
                                    eventID: request.eventID,
                                    date: request.scheduleDate,
                                    title: request.title,
                                    createdAt: request.createdAt,
                                    in: db
                                )
                            }
                        }
                        try store.modify {
                            $0.errorMessage = nil
                            $0.isSaving = false
                        }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "Unable to save schedule."
                            $0.isSaving = false
                        }
                    }
                }

            case .deleteButtonTapped:
                guard !state.isSaving, let scheduleID = state.scheduleID else { return }
                state.errorMessage = nil
                state.isSaving = true
                let eventID = state.eventID
                store.addTask {
                    do {
                        try database.write { db in
                            try ScheduleRecordEditing.delete(scheduleID, eventID: eventID, in: db)
                        }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = (error as? ScheduleRecordEditing.Error) == .scheduleInUse
                                ? "Move or delete scheduled items before deleting this schedule."
                                : "Unable to delete schedule."
                            $0.isSaving = false
                        }
                    }
                }
            }
        }
    }
}

public struct EditScheduleView: View {
    @Environment(\.dismiss) var dismiss
    @State var isDeleteConfirmationPresented = false
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
        .navigationTitle(store.scheduleID == nil ? "New Schedule" : "Edit Schedule")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Label("Cancel", systemImage: "xmark")
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
            if store.scheduleID != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Delete Schedule", role: .destructive) {
                            isDeleteConfirmationPresented = true
                        }
                    } label: {
                        Label("Schedule actions", systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete Schedule?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Schedule", role: .destructive) {
                store.send(.deleteButtonTapped)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Scheduled items must be moved or deleted first.")
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
