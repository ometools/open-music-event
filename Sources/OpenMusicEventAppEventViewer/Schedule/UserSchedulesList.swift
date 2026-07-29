import ATProto
import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventComponents
import Sharing
import SQLiteData
import SwiftUI

@Feature
public struct UserScheduleForm {
    public init() {}

    public struct State: Identifiable {
        public init(
            eventID: OMERecord.Event.ID,
            schedule: UserSchedule? = nil,
            performanceID: OMERecord.ID<OMERecord.Performance>? = nil
        ) {
            self.eventID = eventID
            self._eventViewerState = Shared(.eventViewerState(eventID))
            self.scheduleID = schedule?.id
            self.title = schedule?.title ?? ""
            self.performanceID = performanceID
        }

        public let eventID: OMERecord.Event.ID
        @Shared public var eventViewerState: EventViewerState
        public let scheduleID: UserSchedule.ID?
        public var title: String
        public let performanceID: OMERecord.ID<OMERecord.Performance>?
        public var errorMessage: String?
        public var isSaving = false

        public var id: UserSchedule.ID? { scheduleID }
        public var isCreating: Bool { scheduleID == nil }
        public var navigationTitle: String {
            isCreating ? "New Schedule" : "Rename Schedule"
        }
        public var canSave: Bool {
            !isSaving && (try? UserSchedule.normalizedTitle(title)) != nil
        }
    }

    public enum Action {
        case cancelButtonTapped
        case saveButtonTapped
    }

    @Dependency(\.defaultDatabase) var database
    @Dependency(\.getSelectedOAuthSessionID) var getSelectedOAuthSessionID
    @Dependency(\.uuid) var uuid

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .cancelButtonTapped:
                store.addTask {
                    try store.dismiss()
                }

            case .saveButtonTapped:
                guard !state.isSaving else { return }
                let title: String
                do {
                    title = try UserSchedule.normalizedTitle(state.title)
                } catch {
                    state.errorMessage = "Enter a schedule name between 1 and 80 characters."
                    return
                }

                let eventID = state.eventID
                let scheduleID = state.scheduleID ?? uuid()
                let performanceID = state.performanceID
                let isCreating = state.isCreating
                let userDID = isCreating
                    ? getSelectedOAuthSessionID()?.rawValue
                    : nil
                state.errorMessage = nil
                state.isSaving = true

                store.addTask {
                    do {
                        try await database.write { db in
                            if isCreating {
                                try UserSchedule.insert {
                                    UserSchedule(
                                        id: scheduleID,
                                        eventID: eventID,
                                        title: title,
                                        userDID: userDID
                                    )
                                }
                                .execute(db)

                                if let performanceID {
                                    try UserSchedule.Performance.insert {
                                        UserSchedule.Performance(
                                            scheduleID: scheduleID,
                                            performanceID: performanceID
                                        )
                                    }
                                    .execute(db)
                                }

                                var viewerState = try EventViewerStateRequest(eventID: eventID).fetch(db)
                                viewerState.selectedUserScheduleID = scheduleID
                                try EventViewerState.upsert { viewerState }.execute(db)
                            } else {
                                try UserSchedule
                                    .where { $0.id.eq(scheduleID) }
                                    .where { $0.eventID.eq(eventID) }
                                    .update {
                                        $0.title = title
                                    }
                                    .execute(db)
                            }
                        }
                        if isCreating {
                            try store.modify {
                                $0.$eventViewerState.withLock {
                                    $0.selectedUserScheduleID = scheduleID
                                }
                            }
                        }
                        try store.dismiss()
                    } catch {
                        try store.modify {
                            $0.errorMessage = "A schedule with that name already exists for this event."
                            $0.isSaving = false
                        }
                    }
                }
            }
        }
    }
}

public struct UserScheduleFormView: View {
    @Bindable var store: StoreOf<UserScheduleForm>

    public init(store: StoreOf<UserScheduleForm>) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("Name") {
                TextField("Schedule Name", text: $store.title)
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
        .navigationTitle(store.navigationTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    store.send(.cancelButtonTapped)
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                SubmitButton(
                    isInProgress: store.isSaving,
                    isDisabled: !store.canSave
                ) {
                    store.send(.saveButtonTapped)
                }
            }
        }
    }
}

@Feature
public struct UserSchedulesList {
    public init() {}

    public struct State {
        public init(eventID: OMERecord.Event.ID) {
            self.eventID = eventID
            self._eventViewerState = Shared(.eventViewerState(eventID))
            self._schedules = FetchAll(UserSchedule.all(eventID: eventID))
            self._memberships = FetchAll(UserSchedule.Performance.all)
            self._performanceRows = FetchAll(PerformanceRow.all(eventID: eventID))
        }

        public let eventID: OMERecord.Event.ID
        public var destination: Destination.State?
        @Shared public var eventViewerState: EventViewerState
        @FetchAll public var schedules: [UserSchedule]
        @FetchAll public var memberships: [UserSchedule.Performance]
        @FetchAll public var performanceRows: [PerformanceRow]

        public func performanceCount(for scheduleID: UserSchedule.ID) -> Int {
            memberships.count { $0.id.scheduleID == scheduleID }
        }

        public func unavailableCount(for scheduleID: UserSchedule.ID) -> Int {
            let availablePerformanceIDs = Set(performanceRows.map(\.performanceID))
            return memberships.count {
                $0.id.scheduleID == scheduleID
                    && !availablePerformanceIDs.contains($0.id.performanceID)
            }
        }
    }

    public enum Action {
        case addButtonTapped
        case deleteButtonTapped(UserSchedule.ID)
        case destination(Destination.Action)
        case removeUnavailableButtonTapped(UserSchedule.ID)
        case renameButtonTapped(UserSchedule.ID)
        case scheduleButtonTapped(UserSchedule.ID)
    }

    @Feature
    public enum Destination {
        case deleteConfirmation(DeleteConfirmation)
        case form(Spawn<UserScheduleForm>)
        case removeUnavailableConfirmation(RemoveUnavailableConfirmation)
    }

    @Feature
    public struct DeleteConfirmation: Prompt {
        public struct State: Identifiable {
            public init(scheduleID: UserSchedule.ID) {
                self.scheduleID = scheduleID
            }

            public let scheduleID: UserSchedule.ID
            public var id: UserSchedule.ID { scheduleID }
        }

        public enum Action {
            case deleteButtonTapped(UserSchedule.ID)
        }
    }

    @Feature
    public struct RemoveUnavailableConfirmation: Prompt {
        public struct State: Identifiable {
            public init(scheduleID: UserSchedule.ID) {
                self.scheduleID = scheduleID
            }

            public let scheduleID: UserSchedule.ID
            public var id: UserSchedule.ID { scheduleID }
        }

        public enum Action {
            case removeButtonTapped(UserSchedule.ID)
        }
    }

    @Dependency(\.defaultDatabase) var database

    public var body: some Feature {
        Update { state, action in
            switch action {
            case .addButtonTapped:
                state.destination = .form(
                    Spawn(UserScheduleForm.State(eventID: state.eventID))
                )

            case let .deleteButtonTapped(scheduleID):
                guard state.schedules.contains(where: { $0.id == scheduleID }) else { return }
                state.destination = .deleteConfirmation(
                    DeleteConfirmation.State(scheduleID: scheduleID)
                )

            case let .destination(.deleteConfirmation(.deleteButtonTapped(scheduleID))):
                guard state.schedules.contains(where: { $0.id == scheduleID }) else { return }
                let eventID = state.eventID
                store.addTask {
                    do {
                        try await database.write { db in
                            try UserSchedule
                                .where { $0.id.eq(scheduleID) }
                                .where { $0.eventID.eq(eventID) }
                                .delete()
                                .execute(db)

                            var viewerState = try EventViewerStateRequest(eventID: eventID).fetch(db)
                            if viewerState.selectedUserScheduleID == scheduleID {
                                viewerState.selectedUserScheduleID = nil
                                try EventViewerState.upsert { viewerState }.execute(db)
                            }
                        }
                        try store.modify {
                            if $0.eventViewerState.selectedUserScheduleID == scheduleID {
                                $0.$eventViewerState.withLock {
                                    $0.selectedUserScheduleID = nil
                                }
                            }
                        }
                    } catch {
                        reportIssue(error)
                    }
                }

            case let .destination(.removeUnavailableConfirmation(.removeButtonTapped(scheduleID))):
                guard state.schedules.contains(where: { $0.id == scheduleID }) else { return }
                let availablePerformanceIDs = Set(state.performanceRows.map(\.performanceID))
                let unavailableMembershipIDs = state.memberships
                    .filter {
                        $0.id.scheduleID == scheduleID
                            && !availablePerformanceIDs.contains($0.id.performanceID)
                    }
                    .map(\.id)
                guard !unavailableMembershipIDs.isEmpty else { return }
                store.addTask {
                    do {
                        try await database.write { db in
                            for membershipID in unavailableMembershipIDs {
                                try UserSchedule.Performance
                                    .find(membershipID)
                                    .delete()
                                    .execute(db)
                            }
                        }
                    } catch {
                        reportIssue(error)
                    }
                }

            case .destination:
                break

            case let .removeUnavailableButtonTapped(scheduleID):
                guard state.unavailableCount(for: scheduleID) > 0 else { return }
                state.destination = .removeUnavailableConfirmation(
                    RemoveUnavailableConfirmation.State(scheduleID: scheduleID)
                )

            case let .renameButtonTapped(scheduleID):
                guard let schedule = state.schedules.first(where: { $0.id == scheduleID }) else {
                    return
                }
                state.destination = .form(
                    Spawn(
                        UserScheduleForm.State(
                            eventID: state.eventID,
                            schedule: schedule
                        )
                    )
                )

            case let .scheduleButtonTapped(scheduleID):
                guard state.schedules.contains(where: { $0.id == scheduleID }) else { return }
                state.$eventViewerState.withLock {
                    $0.selectedUserScheduleID = scheduleID
                }
                store.addTask {
                    try store.dismiss()
                }
            }
        }
        .ifLet(\.destination, action: \.destination) {
            Destination.body
        }
    }
}

public struct UserSchedulesListView: View {
    @Bindable var store: StoreOf<UserSchedulesList>

    public init(store: StoreOf<UserSchedulesList>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.schedules.isEmpty {
                ContentUnavailableView(
                    "No Personal Schedules",
                    systemImage: "calendar",
                    description: Text("Create a schedule for the performances you do not want to miss.")
                )
            } else {
                List(store.schedules) { schedule in
                    HStack(spacing: 12) {
                        Button {
                            store.send(.scheduleButtonTapped(schedule.id))
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(schedule.title)
                                    Text(countDescription(for: schedule.id))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if store.eventViewerState.selectedUserScheduleID == schedule.id {
                                    Image(systemName: "checkmark-circle")
                                        .accessibilityLabel("Selected schedule")
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button {
                                store.send(.renameButtonTapped(schedule.id))
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }

                            if store.state.unavailableCount(for: schedule.id) > 0 {
                                Button(role: .destructive) {
                                    store.send(.removeUnavailableButtonTapped(schedule.id))
                                } label: {
                                    Label("Remove Unavailable Performances", systemImage: "trash")
                                }
                            }

                            Button(role: .destructive) {
                                store.send(.deleteButtonTapped(schedule.id))
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Label("Schedule actions", systemImage: "ellipsis")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Schedules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.send(.addButtonTapped)
                } label: {
                    Label("New Schedule", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
            }
        }
        .confirmationDialog(
            "Delete Schedule?",
            isPresented: $store.scope(\.destination, action: \.destination).deleteConfirmation.isPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Schedule", role: .destructive) {
                if let scheduleID = store.destination?.deleteConfirmation?.scheduleID {
                    store.send(
                        .destination(
                            .deleteConfirmation(
                                .deleteButtonTapped(scheduleID)
                            )
                        )
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the schedule and its saved performances.")
        }
        .confirmationDialog(
            "Remove Unavailable Performances?",
            isPresented: $store.scope(
                \.destination,
                action: \.destination
            ).removeUnavailableConfirmation.isPresented,
            titleVisibility: .visible
        ) {
            Button("Remove Unavailable Performances", role: .destructive) {
                if let scheduleID = store.destination?.removeUnavailableConfirmation?.scheduleID {
                    store.send(
                        .destination(
                            .removeUnavailableConfirmation(
                                .removeButtonTapped(scheduleID)
                            )
                        )
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes saved performances that are no longer in the published event.")
        }
        .navigationDestination(item: $store.scope(\.destination, action: \.destination).form) { formStore in
            UserScheduleFormView(store: formStore)
        }
    }

    func countDescription(for scheduleID: UserSchedule.ID) -> String {
        let performanceCount = store.state.performanceCount(for: scheduleID)
        let unavailableCount = store.state.unavailableCount(for: scheduleID)
        let performanceDescription = performanceCount == 1
            ? "1 performance"
            : "\(performanceCount) performances"
        guard unavailableCount > 0 else { return performanceDescription }
        return "\(performanceDescription), \(unavailableCount) unavailable"
    }
}
