import ATProto
import ComposableArchitecture2
import Dependencies
import Foundation
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
            let firstVisit = TestStore(
                initialState: ScheduleViewer.State(eventID: eventID)
            ) {
                ScheduleViewer()
            }

            // On the attendee's first visit, the app offers one personal schedule without
            // hiding the full published schedule behind it.
            try await waitUntil {
                firstVisit.state.userSchedules.map(\.title) == ["My Schedule"]
            }
            let schedule = try #require(firstVisit.state.userSchedules.first)
            #expect(schedule.userDID == userDID)
            #expect(firstVisit.state.userScheduleOverlay.selectedSchedule == nil)

            // The attendee chooses My Schedule from the schedule picker.
            let selectionTask = firstVisit.send(.userScheduleButtonTapped(schedule.id))
            #expect(firstVisit.state.userScheduleOverlay.selectedSchedule?.title == "My Schedule")
            await selectionTask?.value
            try await waitUntil {
                firstVisit.state.userScheduleOverlay.selectedSchedule?.title == "My Schedule"
            }
            await firstVisit.dismount(timeout: .seconds(1))

            // Returning to the event restores the attendee's chosen personal schedule.
            let returnVisit = TestStore(
                initialState: ScheduleViewer.State(eventID: eventID)
            ) {
                ScheduleViewer()
            }
            try await waitUntil {
                returnVisit.state.userScheduleOverlay.selectedSchedule?.title == "My Schedule"
            }

            // The attendee opens Schedules and confirms deletion of My Schedule.
            returnVisit.send(.schedulesButtonTapped)
            try await waitUntil {
                returnVisit.state.destination?.userSchedulesList?.schedules.map(\.title)
                    == ["My Schedule"]
            }
            returnVisit.send(
                to: \.destination!.userSchedulesList!,
                .deleteButtonTapped(schedule.id)
            )
            #expect(
                returnVisit.state.destination?.userSchedulesList?
                    .destination?.deleteConfirmation?.scheduleID
                    == schedule.id
            )
            await returnVisit.send(
                to: \.destination!.userSchedulesList!,
                .destination(.deleteConfirmation(.deleteButtonTapped(schedule.id)))
            )?.value
            try await waitUntil {
                returnVisit.state.userSchedules.isEmpty
                    && returnVisit.state.userScheduleOverlay.selectedSchedule == nil
            }
            await returnVisit.dismount(timeout: .seconds(1))

            // A later visit stays on the full schedule; deleting My Schedule is durable.
            let afterDeletion = TestStore(
                initialState: ScheduleViewer.State(eventID: eventID)
            ) {
                ScheduleViewer()
            }
            await Task.yield()
            await Task.yield()
            await afterDeletion.dismount(timeout: .seconds(1))

            let savedSchedules = try await database.read { db in
                try UserSchedule.all(eventID: eventID).fetchAll(db)
            }
            #expect(savedSchedules.isEmpty)
            #expect(afterDeletion.state.userScheduleOverlay.selectedSchedule == nil)
        }
    }
}

@MainActor
private func waitUntil(
    _ condition: @escaping @MainActor () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(1))
    while clock.now < deadline {
        if condition() { return }
        try await clock.sleep(for: .milliseconds(1))
    }
    Issue.record(
        "Condition was not satisfied within one second",
        sourceLocation: sourceLocation
    )
}
