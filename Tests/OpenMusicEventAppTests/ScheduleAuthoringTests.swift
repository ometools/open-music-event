import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import ScheduleComponents
import SQLiteData
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventEditors
@testable import OpenMusicEventLexicon

@MainActor
@Suite(.tcaExhaustivity(.off))
struct ScheduleAuthoringTests {
    @Test
    func createsScheduleDay() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let eventID = try await seedEvent(database: database, timeZone: timeZone)
        let scheduleDate = try #require(LocalDate("2026-08-01"))
        let store = makeScheduleStore(
            database: database,
            eventID: eventID,
            timeZone: timeZone,
            now: try #require(scheduleDate.at(hour: 12, in: timeZone))
        ) {
            $0.customTitle = "Saturday"
            $0.sourceFileName = "saturday"
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let schedule = try await database.read { db in
            try #require(OMERecord.Schedule.fetchAll(db).first)
        }
        #expect(schedule.id.organizerID == eventID.organizerID)
        #expect(schedule.id.eventID == eventID.eventID)
        #expect(schedule.id.scheduleID.rawValue.rawValue == "saturday")
        #expect(schedule.date == scheduleDate)
        #expect(schedule.startsAt == nil)
        #expect(schedule.endsAt == nil)
        #expect(schedule.customTitle == "Saturday")
    }

    @Test
    func suffixesDuplicateScheduleSourceFileNames() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let eventID = try await seedEvent(database: database, timeZone: timeZone)
        let scheduleDate = try #require(LocalDate("2026-08-01"))
        try await database.write { db in
            try OMERecord.Schedule.insert {
                OMERecord.Schedule.Draft(
                    id: OMERecord.Schedule.ID(
                        organizerID: eventID.organizerID,
                        eventID: eventID.eventID,
                        scheduleID: scheduleLocalID("saturday")
                    ),
                    date: scheduleDate,
                    startsAt: nil,
                    endsAt: nil,
                    customTitle: "Existing Saturday"
                )
            }
            .execute(db)
        }
        let store = makeScheduleStore(
            database: database,
            eventID: eventID,
            timeZone: timeZone,
            now: try #require(scheduleDate.at(hour: 12, in: timeZone))
        ) {
            $0.customTitle = "Second Saturday"
            $0.sourceFileName = "saturday"
        }

        await store.send(.saveButtonTapped)?.value

        let scheduleIDs = try await database.read { db in
            try OMERecord.Schedule
                .fetchAll(db)
                .map { $0.id.scheduleID.rawValue.rawValue }
                .sorted()
        }
        expectNoDifference(scheduleIDs, ["saturday", "saturday-2"])
    }

    @Test
    func dateSelectionUpdatesGeneratedTitleAndSourceFileName() throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let eventID = OMERecord.Event.ID(
            organizerID: OMERecord.Organizer.ID("did:web:wickedwoods.example")!,
            eventID: eventLocalID("wicked-woods-2026")
        )
        let friday = try #require(LocalDate("2026-08-07"))
        let saturday = try #require(LocalDate("2026-08-08"))
        let saturdaySelection = try #require(saturday.at(hour: 12, in: timeZone))
        let store = makeScheduleStore(
            database: database,
            eventID: eventID,
            timeZone: timeZone,
            now: try #require(friday.at(hour: 12, in: timeZone))
        ) { _ in }

        expectNoDifference(store.state.customTitle, "Friday")
        expectNoDifference(store.state.sourceFileName, "friday")

        store.modify {
            $0.dateSelection = saturdaySelection
        } changes: {
            $0.customTitle = "Saturday"
            $0.sourceFileName = "saturday"
        }
    }

    @Test
    func dateSelectionKeepsEditedTitleAndSourceFileName() throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let eventID = OMERecord.Event.ID(
            organizerID: OMERecord.Organizer.ID("did:web:wickedwoods.example")!,
            eventID: eventLocalID("wicked-woods-2026")
        )
        let friday = try #require(LocalDate("2026-08-07"))
        let saturday = try #require(LocalDate("2026-08-08"))
        let saturdaySelection = try #require(saturday.at(hour: 12, in: timeZone))
        let store = makeScheduleStore(
            database: database,
            eventID: eventID,
            timeZone: timeZone,
            now: try #require(friday.at(hour: 12, in: timeZone))
        ) {
            $0.customTitle = "Opening Workshops"
            $0.sourceFileName = "opening-workshops"
        }

        store.modify {
            $0.dateSelection = saturdaySelection
        }

        expectNoDifference(store.state.customTitle, "Opening Workshops")
        expectNoDifference(store.state.sourceFileName, "opening-workshops")
    }

    @Test
    func createsPerformanceRowWithLinkedContributor() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let scheduleDate = fixture.schedule.date
        let startTime = try #require(scheduleDate.at(hour: 20, in: timeZone))
        let endTime = try #require(scheduleDate.at(hour: 21, minute: 30, in: timeZone))
        let store = makePerformanceStore(
            database: database,
            fixture: fixture,
            timeZone: timeZone
        ) {
            $0.title = "Evening Set"
            $0.description = "Main stage performance."
            $0.contributorIDString = "artist-one"
            $0.startTimeSelection = startTime
            $0.endTimeSelection = endTime
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let rows = try await database.read { db in
            (
                performances: try OMERecord.Performance.fetchAll(db),
                contributors: try OMERecord.Performance.Contributors.fetchAll(db)
            )
        }
        let performance = try #require(rows.performances.first)
        let contributor = try #require(rows.contributors.first)
        #expect(rows.performances.count == 1)
        #expect(rows.contributors.count == 1)
        #expect(performance.id.performanceID.rawValue.rawValue == "saturday-main-stage-evening-set")
        #expect(performance.stageID == fixture.stage.id.stageID)
        #expect(performance.scheduleID == fixture.schedule.id.scheduleID)
        #expect(performance.startTime == startTime)
        #expect(performance.endTime == endTime)
        #expect(performance.title == "Evening Set")
        #expect(performance.description == "Main stage performance.")
        #expect(contributor.performanceID == performance.id.performanceID)
        #expect(contributor.contributorID == fixture.contributor.id.contributorID)
        #expect(contributor.anonymousName == nil)
        #expect(contributor.contributorActor == nil)
    }

    @Test
    func rejectsInvalidPerformanceTimeRange() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let startTime = try #require(fixture.schedule.date.at(hour: 20, in: timeZone))
        let store = makePerformanceStore(
            database: database,
            fixture: fixture,
            timeZone: timeZone
        ) {
            $0.title = "Broken Time"
            $0.startTimeSelection = startTime
            $0.endTimeSelection = startTime
        }

        store.send(.saveButtonTapped) {
            $0.errorMessage = "End time must be after the start time."
        }

        let performanceCount = try await database.read { db in
            try OMERecord.Performance.fetchCount(db)
        }
        #expect(performanceCount == 0)
    }

    @Test
    func createsOvernightPerformanceRow() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let scheduleDate = fixture.schedule.date
        let startTime = try #require(scheduleDate.at(hour: 23, minute: 30, in: timeZone))
        let endClockTime = try #require(scheduleDate.at(hour: 1, minute: 15, in: timeZone))
        let expectedEndTime = try localDate(
            scheduleDate,
            atHour: 1,
            minute: 15,
            dayOffset: 1,
            in: timeZone
        )
        let store = makePerformanceStore(
            database: database,
            fixture: fixture,
            timeZone: timeZone
        ) {
            $0.title = "Late Night Set"
            $0.startTimeSelection = startTime
            $0.timeRangeSelection.endClockTimeSelection = endClockTime
        }

        await store.send(.saveButtonTapped)?.value

        let performance = try await database.read { db in
            try #require(OMERecord.Performance.fetchAll(db).first)
        }
        #expect(performance.startTime == startTime)
        #expect(performance.endTime == expectedEndTime)
        #expect(performance.title == "Late Night Set")
    }

    @Test
    func createsPerformanceRowWithAnonymousName() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let scheduleDate = fixture.schedule.date
        let store = try makePerformanceStore(
            database: database,
            fixture: fixture,
            timeZone: timeZone
        ) {
            $0.title = "Surprise Set"
            $0.anonymousContributorName = "Surprise Guest"
            $0.startTimeSelection = try #require(scheduleDate.at(hour: 22, in: timeZone))
            $0.endTimeSelection = try #require(scheduleDate.at(hour: 23, in: timeZone))
        }

        await store.send(.saveButtonTapped)?.value

        let rows = try await database.read { db in
            (
                performances: try OMERecord.Performance.fetchAll(db),
                contributors: try OMERecord.Performance.Contributors.fetchAll(db)
            )
        }
        let performance = try #require(rows.performances.first)
        let contributor = try #require(rows.contributors.first)
        #expect(rows.performances.count == 1)
        #expect(rows.contributors.count == 1)
        #expect(performance.title == "Surprise Set")
        #expect(contributor.performanceID == performance.id.performanceID)
        #expect(contributor.contributorID == nil)
        #expect(contributor.anonymousName == "Surprise Guest")
        #expect(contributor.contributorActor == nil)
    }

    @Test
    func editsPerformanceRowWithoutDroppingContributors() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let performance = try await seedPerformance(
            database: database,
            fixture: fixture,
            timeZone: timeZone
        )
        let updatedStartTime = try #require(fixture.schedule.date.at(hour: 21, in: timeZone))
        let updatedEndTime = try #require(fixture.schedule.date.at(hour: 22, in: timeZone))
        let store = makePerformanceStore(
            database: database,
            fixture: fixture,
            timeZone: timeZone,
            performance: performance
        ) {
            #expect($0.title == "Opening Set")
            #expect($0.description == "Original description.")
            #expect($0.selectedStageID == fixture.stage.id.stageID)
            $0.title = "Updated Set"
            $0.description = "Updated description."
            $0.startTimeSelection = updatedStartTime
            $0.endTimeSelection = updatedEndTime
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let rows = try await database.read { db in
            (
                performance: try #require(OMERecord.Performance.fetchAll(db).first),
                contributors: try OMERecord.Performance.Contributors.fetchAll(db)
            )
        }
        #expect(rows.performance.id.performanceID == performance.id.performanceID)
        #expect(rows.performance.title == "Updated Set")
        #expect(rows.performance.description == "Updated description.")
        #expect(rows.performance.startTime == updatedStartTime)
        #expect(rows.performance.endTime == updatedEndTime)
        #expect(rows.contributors.count == 1)
        #expect(rows.contributors.first?.performanceID == performance.id.performanceID)
        #expect(rows.contributors.first?.contributorID == fixture.contributor.id.contributorID)
    }

    @Test
    func eventViewerPerformanceEditIntentPresentsEditor() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let performance = try await seedPerformance(
            database: database,
            fixture: fixture,
            timeZone: timeZone
        )
        var state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = fixture.eventID
            $0.defaultEventTimeZone = timeZone
        } operation: {
            EventViewer.State(eventID: fixture.eventID)
        }
        state.selectedFeature = .contributors

        state.handleEditingIntent(
            .editPerformance(
                eventID: fixture.eventID,
                performanceID: performance.id.performanceID
            )
        )

        let editPerformance = try #require(state.destination?.performanceForm)
        #expect(state.selectedFeature == .contributors)
        #expect(editPerformance.performanceID == performance.id.performanceID)
        #expect(editPerformance.title == "Opening Set")
        #expect(editPerformance.description == "Original description.")
        #expect(editPerformance.startTimeSelection == performance.startTime)
        #expect(editPerformance.endTimeSelection == performance.endTime)
        #expect(editPerformance.selectedStageID == fixture.stage.id.stageID)
    }

    @Test
    func performanceDetailEditActionEmitsEditorRequest() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let performance = try await seedPerformance(
            database: database,
            fixture: fixture,
            timeZone: timeZone
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventTimeZone = timeZone
        } operation: {
            TestStore(
                initialState: PerformanceDetail.State(
                    performanceID: performance.id.performanceID,
                    eventID: fixture.eventID
                )
            ) {
                PerformanceDetail()
            }
        }

        let editTask = store.send(.editButtonTapped)
        await store.receive(
            key: EventEditingRequested.self,
            value: .equals(
                .editPerformance(
                    eventID: fixture.eventID,
                    performanceID: performance.id.performanceID
                )
            ),
            timeout: .seconds(1)
        )
        await editTask?.value
    }

    @Test
    func scheduleViewerDeletesPerformanceAfterConfirmation() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let performance = try await seedPerformance(
            database: database,
            fixture: fixture,
            timeZone: timeZone
        )
        let store = makeScheduleViewerStore(
            database: database,
            eventID: fixture.eventID,
            timeZone: timeZone
        )

        store.send(.deletePerformanceButtonTapped(performance.id.performanceID))

        #expect(
            store.state.destination?.deletePerformanceConfirmation?.performanceID
                == performance.id.performanceID
        )

        await store.send(
            .destination(
                .deletePerformanceConfirmation(
                    .deleteButtonTapped(performance.id.performanceID)
                )
            )
        )?.value

        let rows = try await database.read { db in
            (
                performances: try OMERecord.Performance.fetchAll(db),
                contributors: try OMERecord.Performance.Contributors.fetchAll(db)
            )
        }
        #expect(rows.performances.isEmpty)
        #expect(rows.contributors.isEmpty)
    }

    private func makePreparedDatabase() throws -> any DatabaseWriter {
        try withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
        } operation: {
            @Dependency(\.defaultDatabase) var database
            return database
        }
    }

    private func makeScheduleStore(
        database: any DatabaseWriter,
        eventID: OMERecord.Event.ID,
        timeZone: TimeZone,
        now: Date,
        update: (inout EditSchedule.State) -> Void
    ) -> TestStore<EditSchedule> {
        withDependencies {
            $0.context = .test
            $0.date = .constant(now)
            $0.defaultDatabase = database
        } operation: {
            var state = EditSchedule.State(eventID: eventID, timeZone: timeZone)
            update(&state)
            return TestStore(initialState: state) {
                EditSchedule()
            }
        }
    }

    private func makePerformanceStore(
        database: any DatabaseWriter,
        fixture: ScheduleAuthoringFixture,
        timeZone: TimeZone,
        performance: OMERecord.Performance? = nil,
        update: (inout EditPerformance.State) throws -> Void
    ) rethrows -> TestStore<EditPerformance> {
        try withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var state: EditPerformance.State
            if let performance {
                state = EditPerformance.State(
                    eventID: fixture.eventID,
                    schedule: fixture.schedule,
                    stages: [fixture.stage],
                    timeZone: timeZone,
                    performance: performance
                )
            } else {
                state = EditPerformance.State(
                    eventID: fixture.eventID,
                    schedule: fixture.schedule,
                    stages: [fixture.stage],
                    timeZone: timeZone
                )
            }
            try update(&state)
            return TestStore(initialState: state) {
                EditPerformance()
            }
        }
    }

    private func makeScheduleViewerStore(
        database: any DatabaseWriter,
        eventID: OMERecord.Event.ID,
        timeZone: TimeZone
    ) -> TestStore<ScheduleViewer> {
        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventTimeZone = timeZone
        } operation: {
            TestStore(initialState: ScheduleViewer.State(eventID: eventID)) {
                ScheduleViewer()
            }
        }
    }

    private func seedEvent(
        database: any DatabaseWriter,
        timeZone: TimeZone
    ) async throws -> OMERecord.Event.ID {
        let eventID = OMERecord.Event.ID(
            organizerID: OMERecord.Organizer.ID("did:web:wickedwoods.example")!,
            eventID: eventLocalID("wicked-woods-2026")
        )
        try await database.write { db in
            try OMERecord.Organizer.insert {
                OMERecord.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OMERecord.Event.insert {
                OMERecord.Event.Draft(
                    id: eventID,
                    name: "Wicked Woods 2026",
                    description: nil,
                    startDate: nil,
                    endDate: nil,
                    status: .known(.planned),
                    mode: .known(.inPerson),
                    locations: nil,
                    uris: nil,
                    timeZone: timeZone,
                    imageURL: nil,
                    iconImageURL: nil,
                    siteMapImageURL: nil,
                    contactNumbers: nil,
                    categoryConfigs: nil
                )
            }
            .execute(db)
        }
        return eventID
    }

    private func seedScheduleFixture(
        database: any DatabaseWriter,
        timeZone: TimeZone
    ) async throws -> ScheduleAuthoringFixture {
        let eventID = try await seedEvent(database: database, timeZone: timeZone)
        let scheduleDate = try #require(LocalDate("2026-08-01"))
        let stageID = OMERecord.Stage.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            stageID: stageLocalID("main-stage")
        )
        let scheduleID = OMERecord.Schedule.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            scheduleID: scheduleLocalID("saturday")
        )
        let contributorID = OMERecord.Contributor.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            contributorID: contributorLocalID("artist-one")
        )
        try await database.write { db in
            try OMERecord.Stage.insert {
                OMERecord.Stage.Draft(
                    id: stageID,
                    name: "Main Stage",
                    color: 0x00bbcc,
                    sortIndex: 1
                )
            }
            .execute(db)
            try OMERecord.Schedule.insert {
                OMERecord.Schedule.Draft(
                    id: scheduleID,
                    date: scheduleDate,
                    startsAt: nil,
                    endsAt: nil,
                    customTitle: "Saturday"
                )
            }
            .execute(db)
            try OMERecord.Contributor.insert {
                OMERecord.Contributor.Draft(
                    id: contributorID,
                    name: "Artist One",
                    bio: nil,
                    images: nil,
                    kind: nil,
                    links: nil
                )
            }
            .execute(db)
        }
        return try await database.read { db in
            let schedule = try OMERecord.Schedule
                .where { $0.id.eq(scheduleID) }
                .fetchOne(db)
            let stage = try OMERecord.Stage
                .where { $0.id.eq(stageID) }
                .fetchOne(db)
            let contributor = try OMERecord.Contributor
                .where { $0.id.eq(contributorID) }
                .fetchOne(db)
            return ScheduleAuthoringFixture(
                eventID: eventID,
                schedule: try #require(schedule),
                stage: try #require(stage),
                contributor: try #require(contributor)
            )
        }
    }

    private func seedPerformance(
        database: any DatabaseWriter,
        fixture: ScheduleAuthoringFixture,
        timeZone: TimeZone
    ) async throws -> OMERecord.Performance {
        let startTime = try #require(fixture.schedule.date.at(hour: 20, in: timeZone))
        let endTime = try #require(fixture.schedule.date.at(hour: 21, in: timeZone))
        let performanceID = OMERecord.Performance.ID(
            organizerID: fixture.eventID.organizerID,
            eventID: fixture.eventID.eventID,
            performanceID: performanceLocalID("opening-set")
        )
        try await database.write { db in
            try OMERecord.Performance.insert {
                OMERecord.Performance.Draft(
                    id: performanceID,
                    stageID: fixture.stage.id.stageID,
                    scheduleID: fixture.schedule.id.scheduleID,
                    startTime: startTime,
                    endTime: endTime,
                    title: "Opening Set",
                    description: "Original description.",
                    recordings: []
                )
            }
            .execute(db)
            try OMERecord.Performance.Contributors.insert {
                OMERecord.Performance.Contributors.Draft(
                    organizerID: fixture.eventID.organizerID,
                    eventID: fixture.eventID.eventID,
                    performanceID: performanceID.performanceID,
                    contributorID: fixture.contributor.id.contributorID,
                    anonymousName: nil,
                    contributorActor: nil
                )
            }
            .execute(db)
        }
        return try await database.read { db in
            try #require(
                try OMERecord.Performance
                    .where { $0.id.eq(performanceID) }
                    .fetchOne(db)
            )
        }
    }
}

private struct ScheduleAuthoringFixture {
    var eventID: OMERecord.Event.ID
    var schedule: OMERecord.Schedule
    var stage: OMERecord.Stage
    var contributor: OMERecord.Contributor
}

private func eventLocalID(_ string: String) -> OMERecord.ID<OMERecord.Event> {
    OMERecord.ID<OMERecord.Event>(.init(string))
}

private func scheduleLocalID(_ string: String) -> OMERecord.ID<OMERecord.Schedule> {
    OMERecord.ID<OMERecord.Schedule>(.init(string))
}

private func performanceLocalID(_ string: String) -> OMERecord.ID<OMERecord.Performance> {
    OMERecord.ID<OMERecord.Performance>(.init(string))
}

private func stageLocalID(_ string: String) -> OMERecord.ID<OMERecord.Stage> {
    OMERecord.ID<OMERecord.Stage>(.init(string))
}

private func contributorLocalID(_ string: String) -> OMERecord.ID<OMERecord.Contributor> {
    OMERecord.ID<OMERecord.Contributor>(.init(string))
}

private func localDate(
    _ date: LocalDate,
    atHour hour: Int,
    minute: Int = 0,
    dayOffset: Int = 0,
    in timeZone: TimeZone
) throws -> Date {
    let resolvedDate = try #require(date.at(hour: hour, minute: minute, in: timeZone))
    guard dayOffset != 0 else { return resolvedDate }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return try #require(calendar.date(byAdding: .day, value: dayOffset, to: resolvedDate))
}
