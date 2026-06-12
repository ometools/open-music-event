import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventLexicon

@MainActor
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
        update: (inout EditPerformance.State) throws -> Void
    ) rethrows -> TestStore<EditPerformance> {
        try withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var state = EditPerformance.State(
                eventID: fixture.eventID,
                schedule: fixture.schedule,
                stages: [fixture.stage],
                timeZone: timeZone
            )
            try update(&state)
            return TestStore(initialState: state) {
                EditPerformance()
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

private func stageLocalID(_ string: String) -> OMERecord.ID<OMERecord.Stage> {
    OMERecord.ID<OMERecord.Stage>(.init(string))
}

private func contributorLocalID(_ string: String) -> OMERecord.ID<OMERecord.Contributor> {
    OMERecord.ID<OMERecord.Contributor>(.init(string))
}
