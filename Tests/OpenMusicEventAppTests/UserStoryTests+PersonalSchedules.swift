import ATProto
import ComposableArchitecture2
import Dependencies
import Foundation
import Observation
import OpenMusicEventAuthentication
import SQLiteData
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

extension UserStoryTests {
    @MainActor
    @Test
    func `an attendee keeps a personal schedule across visits until deleting it`() async throws {
        let database = try UserStory.makePreparedStoryDatabase()
        try await UserStory.seedDefault(in: database)
        let eventID = UserStory.eventID
        let userDID = try #require(DID("did:plc:attendee"))

        try await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.getSelectedOAuthSessionID = { Atmosphere.Account.ID(userDID) }
            $0.uuid = .incrementing
        } operation: {
            let firstVisit = Store(
                initialState: ScheduleViewer.State(eventID: eventID)
            ) {
                ScheduleViewer()
            }

            // On the attendee's first visit, the app offers one personal schedule without
            // hiding the full published schedule behind it.
            await waitUntil {
                firstVisit.state.userSchedules.map(\.title) == ["My Schedule"]
            }
            let schedule = try #require(firstVisit.state.userSchedules.first)
            #expect(schedule.userDID == userDID)
            #expect(firstVisit.state.userScheduleOverlay.selectedSchedule == nil)

            // The attendee chooses My Schedule from the schedule picker.
            let selectionTask = firstVisit.send(.userScheduleButtonTapped(schedule.id))
            await selectionTask?.value
            #expect(firstVisit.state.userScheduleOverlay.selectedSchedule?.title == "My Schedule")

            // Returning to the event restores the attendee's chosen personal schedule.
            let returnVisit = Store(
                initialState: ScheduleViewer.State(eventID: eventID)
            ) {
                ScheduleViewer()
            }
            await waitUntil {
                returnVisit.state.userScheduleOverlay.selectedSchedule?.title == "My Schedule"
            }

            // The attendee opens Schedules and confirms deletion of My Schedule.
            returnVisit.send(.schedulesButtonTapped)
            await waitUntil {
                returnVisit.state.destination?.userSchedulesList?.schedules.map(\.title)
                    == ["My Schedule"]
            }
            let schedules = try #require(
                returnVisit.spawn(\.destination?.userSchedulesList)
            )
            schedules.send(.deleteButtonTapped(schedule.id))
            #expect(
                schedules.destination?.deleteConfirmation?.scheduleID
                    == schedule.id
            )
            await schedules.send(
                .destination(.deleteConfirmation(.deleteButtonTapped(schedule.id)))
            )?.value
            await waitUntil {
                returnVisit.state.userSchedules.isEmpty
                    && returnVisit.state.userScheduleOverlay.selectedSchedule == nil
            }

            // A later visit stays on the full schedule; deleting My Schedule is durable.
            let afterDeletion = Store(
                initialState: ScheduleViewer.State(eventID: eventID)
            ) {
                ScheduleViewer()
            }
            await waitUntil {
                afterDeletion.state.eventViewerState.didInitializeUserSchedules
            }

            let (savedSchedules, savedViewerState) = try await database.read { db in
                (
                    try UserSchedule.all(eventID: eventID).fetchAll(db),
                    try EventViewerStateRequest(eventID: eventID).fetch(db)
                )
            }
            #expect(savedSchedules.isEmpty)
            #expect(afterDeletion.state.userScheduleOverlay.selectedSchedule == nil)
            #expect(savedViewerState.selectedUserScheduleID == nil)
            #expect(savedViewerState.didInitializeUserSchedules)
        }
    }
}

@MainActor
private func waitUntil(
    _ condition: @escaping @MainActor () -> Bool
) async {
    while !condition() {
        await withCheckedContinuation { continuation in
            withObservationTracking {
                _ = condition()
            } onChange: {
                continuation.resume()
            }
        }
    }
}
