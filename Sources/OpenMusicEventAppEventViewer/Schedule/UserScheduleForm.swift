import OpenMusicEventLexicon
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
            eventID: Event.ID,
            schedule: UserSchedule? = nil,
            performanceID: ProgramItem.ID? = nil
        ) {
            self.eventID = eventID
            self.scheduleID = schedule?.id
            self.title = schedule?.title ?? ""
            self.performanceID = performanceID
        }

        public let eventID: Event.ID
        public let scheduleID: UserSchedule.ID?
        public var title: String
        public let performanceID: ProgramItem.ID?
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

                                var viewerState = try EventDetailStateRequest(eventID: eventID).fetch(db)
                                viewerState.selectedUserScheduleID = scheduleID
                                try EventDetailState.upsert { viewerState }.execute(db)
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

