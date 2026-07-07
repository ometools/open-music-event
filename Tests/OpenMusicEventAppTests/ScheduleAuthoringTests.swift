import ATProto
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import ScheduleComponents
import SQLiteData
import Testing
import XRPCClient

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
        ) { _ in }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let schedule = try await database.read { db in
            try #require(OMERecord.Schedule.fetchAll(db).first)
        }
        #expect(schedule.id.organizerID == eventID.organizerID)
        #expect(schedule.id.eventID == eventID.eventID)
        #expect(schedule.id.scheduleID.rawValue.rawValue == "2026-08-01")
        #expect(schedule.date == scheduleDate)
        #expect(schedule.startsAt == nil)
        #expect(schedule.endsAt == nil)
        #expect(schedule.customTitle == nil)
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
    func dateSelectionUpdatesGeneratedSourceFileName() throws {
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

        expectNoDifference(store.state.customTitle, "")
        expectNoDifference(store.state.inferredTitle, "Friday")
        expectNoDifference(store.state.sourceFileName, "2026-08-07")

        store.modify {
            $0.dateSelection = saturdaySelection
        } changes: {
            $0.sourceFileName = "2026-08-08"
        }
        expectNoDifference(store.state.inferredTitle, "Saturday")
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
    func scheduleViewerAddPerformanceRequestUsesSelectedScheduleAndStage() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let selectedContext = try await seedAdditionalScheduleContext(
            database: database,
            eventID: fixture.eventID
        )
        let store = makeScheduleViewerStore(
            database: database,
            eventID: fixture.eventID,
            timeZone: timeZone
        )
        store.modify {
            $0.selectedStageID = selectedContext.stage.id.stageID
        }

        let addTask = store.send(
            .addPerformanceButtonTapped(selectedContext.schedule.id.scheduleID)
        )
        await store.receive(
            key: EventEditingRequested.self,
            value: .equals(
                .addPerformance(
                    eventID: fixture.eventID,
                    scheduleID: selectedContext.schedule.id.scheduleID,
                    stageID: selectedContext.stage.id.stageID
                )
            ),
            timeout: .seconds(1)
        )
        await addTask?.value
    }

    @Test
    func scheduleViewerCanAddPerformanceWhileSchedulelessEventIsLoading() throws {
        let eventID = OMERecord.Event.ID(
            organizerID: OMERecord.Organizer.ID("did:web:wickedwoods.example")!,
            eventID: eventLocalID("wicked-woods-2026")
        )
        let stage = OMERecord.Stage(
            id: OMERecord.Stage.ID(
                organizerID: eventID.organizerID,
                eventID: eventID.eventID,
                stageID: stageLocalID("main-stage")
            ),
            name: "Main Stage",
            color: 0x00bbcc,
            category: nil,
            sortIndex: nil,
            images: nil,
            systemIconName: nil,
            iconShortCode: nil,
            lineup: nil
        )

        expectNoDifference(
            ScheduleViewer.canAddPerformance(
                selectedScheduleID: nil,
                schedules: [],
                stages: [stage],
                event: nil
            ),
            true
        )
    }

    @Test
    func eventViewerAddPerformanceIntentSeedsSelectedScheduleAndStage() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let selectedContext = try await seedAdditionalScheduleContext(
            database: database,
            eventID: fixture.eventID
        )
        let expectedStart = try #require(
            selectedContext.schedule.date.at(hour: 19, minute: 30, in: timeZone)
        )
        _ = try await seedPerformance(
            database: database,
            eventID: fixture.eventID,
            schedule: selectedContext.schedule,
            stage: selectedContext.stage,
            performanceID: OMERecord.Performance.ID(
                organizerID: fixture.eventID.organizerID,
                eventID: fixture.eventID.eventID,
                performanceID: performanceLocalID("meadow-opener")
            ),
            title: "Meadow Opener",
            startTime: try #require(
                selectedContext.schedule.date.at(hour: 18, in: timeZone)
            ),
            endTime: expectedStart
        )
        let expectedEnd = expectedStart.addingTimeInterval(60 * 60)
        let editPerformance = try addPerformanceEditorState(
            database: database,
            eventID: fixture.eventID,
            timeZone: timeZone,
            scheduleID: selectedContext.schedule.id.scheduleID,
            stageID: selectedContext.stage.id.stageID
        )
        expectNoDifference(
            editPerformance.schedule.id.scheduleID,
            selectedContext.schedule.id.scheduleID
        )
        expectNoDifference(
            editPerformance.selectedStageID,
            selectedContext.stage.id.stageID
        )
        expectNoDifference(editPerformance.startTimeSelection, expectedStart)
        expectNoDifference(editPerformance.endTimeSelection, expectedEnd)
    }

    @Test
    func eventViewerAddPerformanceIntentIgnoresLaterSetsOnOtherStages() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let selectedContext = try await seedAdditionalScheduleContext(
            database: database,
            eventID: fixture.eventID
        )
        let expectedStart = try #require(
            selectedContext.schedule.date.at(hour: 19, in: timeZone)
        )
        _ = try await seedPerformance(
            database: database,
            eventID: fixture.eventID,
            schedule: selectedContext.schedule,
            stage: selectedContext.stage,
            performanceID: OMERecord.Performance.ID(
                organizerID: fixture.eventID.organizerID,
                eventID: fixture.eventID.eventID,
                performanceID: performanceLocalID("active-stage-set")
            ),
            title: "Active Stage Set",
            startTime: try #require(
                selectedContext.schedule.date.at(hour: 18, in: timeZone)
            ),
            endTime: expectedStart
        )
        _ = try await seedPerformance(
            database: database,
            eventID: fixture.eventID,
            schedule: selectedContext.schedule,
            stage: fixture.stage,
            performanceID: OMERecord.Performance.ID(
                organizerID: fixture.eventID.organizerID,
                eventID: fixture.eventID.eventID,
                performanceID: performanceLocalID("other-stage-late-set")
            ),
            title: "Other Stage Late Set",
            startTime: try #require(
                selectedContext.schedule.date.at(hour: 22, in: timeZone)
            ),
            endTime: try #require(
                selectedContext.schedule.date.at(hour: 23, in: timeZone)
            )
        )
        let editPerformance = try addPerformanceEditorState(
            database: database,
            eventID: fixture.eventID,
            timeZone: timeZone,
            scheduleID: selectedContext.schedule.id.scheduleID,
            stageID: selectedContext.stage.id.stageID
        )
        expectNoDifference(editPerformance.startTimeSelection, expectedStart)
        expectNoDifference(
            editPerformance.endTimeSelection,
            expectedStart.addingTimeInterval(60 * 60)
        )
    }

    @Test
    func eventViewerAddPerformanceIntentKeepsNoonDefaultWithoutPriorStageSet() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let selectedContext = try await seedAdditionalScheduleContext(
            database: database,
            eventID: fixture.eventID
        )
        let expectedStart = try #require(
            selectedContext.schedule.date.at(hour: 12, in: timeZone)
        )
        let expectedEnd = try #require(
            selectedContext.schedule.date.at(hour: 13, in: timeZone)
        )
        let editPerformance = try addPerformanceEditorState(
            database: database,
            eventID: fixture.eventID,
            timeZone: timeZone,
            scheduleID: selectedContext.schedule.id.scheduleID,
            stageID: selectedContext.stage.id.stageID
        )
        expectNoDifference(editPerformance.startTimeSelection, expectedStart)
        expectNoDifference(editPerformance.endTimeSelection, expectedEnd)
    }

    @Test
    func eventViewerAddPerformanceIntentCreatesSingletonScheduleWhenEventHasNoSchedule() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let scheduleDate = try #require(LocalDate("2026-08-01"))
        let eventID = try await seedEvent(
            database: database,
            timeZone: timeZone,
            startDate: scheduleDate
        )
        let stageID = OMERecord.Stage.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            stageID: stageLocalID("main-stage")
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
        }
        var state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.defaultEventTimeZone = timeZone
        } operation: {
            EventViewer.State(eventID: eventID)
        }

        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.defaultEventTimeZone = timeZone
        } operation: {
            state.handleEditingIntent(
                .addPerformance(
                    eventID: eventID,
                    scheduleID: nil,
                    stageID: stageID.stageID
                )
            )
        }

        let editPerformance = try #require(state.destination?.performanceForm)
        expectNoDifference(
            editPerformance.schedule.id.scheduleID,
            OMERecord.Schedule.singletonID
        )
        expectNoDifference(editPerformance.schedule.date, scheduleDate)
        expectNoDifference(editPerformance.selectedStageID, stageID.stageID)
        let schedules = try await database.read { db in
            try OMERecord.Schedule.fetchAll(db)
        }
        expectNoDifference(schedules.map(\.id.scheduleID), [OMERecord.Schedule.singletonID])
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
        let store = try makePerformanceStore(
            database: database,
            fixture: fixture,
            timeZone: timeZone
        ) {
            $0.title = "Evening Set"
            $0.description = "Main stage performance."
            $0.appendContribution(
                selection: .existingContributor(fixture.contributor.id.contributorID)
            )
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
                contributors: try OMERecord.Performance.Contributors.fetchAll(db),
                relationships: try OMERecord.Relationship.fetchAll(db)
            )
        }
        let performance = try #require(rows.performances.first)
        let contributor = try #require(rows.contributors.first)
        let relationship = try #require(rows.relationships.first)
        #expect(rows.performances.count == 1)
        #expect(rows.contributors.count == 1)
        #expect(rows.relationships.count == 1)
        #expect(performance.id.performanceID.rawValue.rawValue == "saturday-main-stage-evening-set")
        #expect(performance.stageID == fixture.stage.id.stageID)
        #expect(performance.scheduleID == fixture.schedule.id.scheduleID)
        #expect(performance.startTime == startTime)
        #expect(performance.endTime == endTime)
        #expect(performance.title == "Evening Set")
        #expect(performance.description == "Main stage performance.")
        #expect(contributor.performanceID == performance.id)
        #expect(contributor.contributorID == fixture.contributor.id.contributorID)
        #expect(contributor.anonymousName == nil)
        #expect(contributor.contributorActor == nil)
        #expect(contributor.role == nil)
        #expect(
            relationship.subject
                == .known(.record(.init(contributorID: fixture.contributor.id)))
        )
        #expect(relationship.role == .performer)
        #expect(
            relationship.object
                == .known(.record(.init(performanceID: performance.id)))
        )
    }

    @Test
    func createsPerformanceRowsWithMultipleContributors() async throws {
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
            $0.title = "Shared Set"
            $0.appendContribution(
                selection: .existingContributor(fixture.contributor.id.contributorID)
            )
            $0.appendContribution(
                selection: .performanceDisplayName(name: "Mystery Guest"),
                billing: .supporting
            )
            $0.startTimeSelection = try #require(scheduleDate.at(hour: 22, in: timeZone))
            $0.endTimeSelection = try #require(scheduleDate.at(hour: 23, in: timeZone))
        }

        await store.send(.saveButtonTapped)?.value

        let rows = try await database.read { db in
            (
                performance: try #require(OMERecord.Performance.fetchAll(db).first),
                contributors: try OMERecord.Performance.Contributors
                    .fetchAll(db)
                    .sorted { $0.sortIndex < $1.sortIndex },
                relationships: try OMERecord.Relationship.fetchAll(db)
            )
        }
        #expect(rows.contributors.count == 2)
        #expect(rows.contributors[0].performanceID == rows.performance.id)
        #expect(rows.contributors[0].contributorID == fixture.contributor.id.contributorID)
        #expect(rows.contributors[0].anonymousName == nil)
        #expect(rows.contributors[0].billing == .primary)
        #expect(rows.contributors[0].role == nil)
        #expect(rows.contributors[0].sortIndex == 0)
        #expect(rows.contributors[1].performanceID == rows.performance.id)
        #expect(rows.contributors[1].contributorID == nil)
        #expect(rows.contributors[1].anonymousName == "Mystery Guest")
        #expect(rows.contributors[1].billing == .supporting)
        #expect(rows.contributors[1].role == nil)
        #expect(rows.contributors[1].sortIndex == 1)
        #expect(rows.relationships.count == 1)
        #expect(
            rows.relationships.first?.subject
                == .known(.record(.init(contributorID: fixture.contributor.id)))
        )
    }

    @Test
    func createsPerformanceRowWithNewManualContributor() async throws {
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
            $0.title = "Manual Contributor Set"
            $0.appendContribution(selection: .newContributor(name: "Guest Artist"))
            $0.startTimeSelection = try #require(scheduleDate.at(hour: 22, in: timeZone))
            $0.endTimeSelection = try #require(scheduleDate.at(hour: 23, in: timeZone))
        }

        await store.send(.saveButtonTapped)?.value

        let rows = try await database.read { db in
            (
                contributors: try OMERecord.Contributor.fetchAll(db),
                performanceContributors: try OMERecord.Performance.Contributors.fetchAll(db),
                relationships: try OMERecord.Relationship.fetchAll(db)
            )
        }
        let newContributor = try #require(
            rows.contributors.first { $0.name == "Guest Artist" }
        )
        let performanceContributor = try #require(rows.performanceContributors.first)
        let relationship = try #require(rows.relationships.first)
        #expect(rows.contributors.count == 2)
        #expect(newContributor.id.contributorID.rawValue.rawValue == "guest-artist")
        #expect(newContributor.did == nil)
        #expect(performanceContributor.contributorID == newContributor.id.contributorID)
        #expect(performanceContributor.anonymousName == nil)
        #expect(performanceContributor.contributorActor == nil)
        #expect(
            relationship.subject
                == .known(.record(.init(contributorID: newContributor.id)))
        )
        #expect(relationship.role == .performer)
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
        let store = try makePerformanceStore(
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
        let store = try makePerformanceStore(
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
            $0.appendContribution(
                selection: .performanceDisplayName(name: "Surprise Guest")
            )
            $0.startTimeSelection = try #require(scheduleDate.at(hour: 22, in: timeZone))
            $0.endTimeSelection = try #require(scheduleDate.at(hour: 23, in: timeZone))
        }

        await store.send(.saveButtonTapped)?.value

        let rows = try await database.read { db in
            (
                performances: try OMERecord.Performance.fetchAll(db),
                contributors: try OMERecord.Performance.Contributors.fetchAll(db),
                relationships: try OMERecord.Relationship.fetchAll(db)
            )
        }
        let performance = try #require(rows.performances.first)
        let contributor = try #require(rows.contributors.first)
        #expect(rows.performances.count == 1)
        #expect(rows.contributors.count == 1)
        #expect(rows.relationships.isEmpty)
        #expect(performance.title == "Surprise Set")
        #expect(contributor.performanceID == performance.id)
        #expect(contributor.contributorID == nil)
        #expect(contributor.anonymousName == "Surprise Guest")
        #expect(contributor.contributorActor == nil)
    }

    @Test
    func createsPerformanceRowWithIdentityRelationship() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let artistDID = try #require(DID("did:plc:artist123"))
        let artistActor = try #require(OMERecord.Contributor.Actor("did:plc:artist123"))
        let scheduleDate = fixture.schedule.date
        let store = try makePerformanceStore(
            database: database,
            fixture: fixture,
            timeZone: timeZone
        ) {
            $0.title = "Identity Set"
            $0.appendContribution(
                selection: .identityOnly(
                    actor: artistActor,
                    displayTitle: "Artist"
                ),
                roleSelection: .dj
            )
            $0.startTimeSelection = try #require(scheduleDate.at(hour: 22, in: timeZone))
            $0.endTimeSelection = try #require(scheduleDate.at(hour: 23, in: timeZone))
        }

        await store.send(.saveButtonTapped)?.value

        let rows = try await database.read { db in
            (
                performances: try OMERecord.Performance.fetchAll(db),
                contributors: try OMERecord.Performance.Contributors.fetchAll(db),
                relationships: try OMERecord.Relationship.fetchAll(db)
            )
        }
        let performance = try #require(rows.performances.first)
        let contributor = try #require(rows.contributors.first)
        let relationship = try #require(rows.relationships.first)
        #expect(rows.performances.count == 1)
        #expect(rows.contributors.count == 1)
        #expect(rows.relationships.count == 1)
        #expect(contributor.performanceID == performance.id)
        #expect(contributor.contributorID == nil)
        #expect(contributor.anonymousName == nil)
        #expect(contributor.contributorActor == artistActor)
        #expect(contributor.role == "dj")
        #expect(relationship.subject == .known(.identity(did: artistDID)))
        #expect(relationship.role == .dj)
        #expect(relationship.object == .known(.record(.init(performanceID: performance.id))))
    }

    @Test
    func createsPerformanceRowWithContributorFromIdentity() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let identity = ActorIdentity(
            did: try #require(DID("did:plc:identityartist")),
            handle: Atmosphere.Account.Handle(rawValue: "identityartist.bsky.social"),
            displayName: "Identity Artist",
            source: .typeahead
        )
        let scheduleDate = fixture.schedule.date
        let store = try makePerformanceStore(
            database: database,
            fixture: fixture,
            timeZone: timeZone
        ) {
            $0.title = "Identity Contributor Set"
            $0.appendContribution(
                selection: .newContributorFromIdentity(
                    ContributorRelationshipPicker.SelectedActorIdentity(identity)
                ),
                roleSelection: .dj
            )
            $0.startTimeSelection = try #require(scheduleDate.at(hour: 22, in: timeZone))
            $0.endTimeSelection = try #require(scheduleDate.at(hour: 23, in: timeZone))
        }

        await store.send(.saveButtonTapped)?.value

        let rows = try await database.read { db in
            (
                contributors: try OMERecord.Contributor.fetchAll(db),
                performanceContributors: try OMERecord.Performance.Contributors.fetchAll(db),
                relationships: try OMERecord.Relationship.fetchAll(db)
            )
        }
        let createdContributor = try #require(
            rows.contributors.first { $0.did == identity.did }
        )
        let performanceContributor = try #require(rows.performanceContributors.first)
        let relationship = try #require(rows.relationships.first)
        #expect(rows.contributors.count == 2)
        #expect(createdContributor.name == "Identity Artist")
        #expect(createdContributor.id.contributorID.rawValue.rawValue == "identity-artist")
        #expect(performanceContributor.contributorID == createdContributor.id.contributorID)
        #expect(performanceContributor.anonymousName == nil)
        #expect(performanceContributor.contributorActor == nil)
        #expect(performanceContributor.role == "dj")
        #expect(
            relationship.subject
                == .known(.record(.init(contributorID: createdContributor.id)))
        )
        #expect(relationship.role == .dj)
    }

    @Test
    func reusesContributorWithMatchingIdentityDid() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let did = try #require(DID("did:plc:knownartist"))
        let knownContributorID = OMERecord.Contributor.ID(
            organizerID: fixture.eventID.organizerID,
            eventID: fixture.eventID.eventID,
            contributorID: contributorLocalID("known-artist")
        )
        try await database.write { db in
            try OMERecord.Contributor.insert {
                OMERecord.Contributor.Draft(
                    id: knownContributorID,
                    name: "Known Artist",
                    did: did,
                    bio: nil,
                    images: nil,
                    links: nil
                )
            }
            .execute(db)
        }
        let identity = ActorIdentity(
            did: did,
            handle: Atmosphere.Account.Handle(rawValue: "knownartist.bsky.social"),
            displayName: "Known Artist Profile",
            source: .typeahead
        )
        let scheduleDate = fixture.schedule.date
        let store = try makePerformanceStore(
            database: database,
            fixture: fixture,
            timeZone: timeZone
        ) {
            $0.title = "Known Identity Set"
            $0.appendContribution(
                selection: .newContributorFromIdentity(
                    ContributorRelationshipPicker.SelectedActorIdentity(identity)
                )
            )
            $0.startTimeSelection = try #require(scheduleDate.at(hour: 22, in: timeZone))
            $0.endTimeSelection = try #require(scheduleDate.at(hour: 23, in: timeZone))
        }

        await store.send(.saveButtonTapped)?.value

        let rows = try await database.read { db in
            (
                contributors: try OMERecord.Contributor.fetchAll(db),
                performanceContributor: try #require(OMERecord.Performance.Contributors.fetchAll(db).first),
                relationship: try #require(OMERecord.Relationship.fetchAll(db).first)
            )
        }
        #expect(rows.contributors.count == 2)
        #expect(rows.performanceContributor.contributorID == knownContributorID.contributorID)
        #expect(rows.relationship.subject == .known(.record(.init(contributorID: knownContributorID))))
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
        let store = try makePerformanceStore(
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
        #expect(rows.contributors.first?.performanceID == performance.id)
        #expect(rows.contributors.first?.contributorID == fixture.contributor.id.contributorID)
    }

    @Test
    func editsPerformanceContributorRelationship() async throws {
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
        let artistDID = try #require(DID("did:plc:artist456"))
        let artistActor = try #require(OMERecord.Contributor.Actor("did:plc:artist456"))
        let store = try makePerformanceStore(
            database: database,
            fixture: fixture,
            timeZone: timeZone,
            performance: performance
        ) {
            #expect(
                $0.contributions.map(\.selection)
                    == [.existingContributor(fixture.contributor.id.contributorID)]
            )
            let contributionID = try #require($0.contributions.first?.id)
            $0.contributions[0].selection = .identityOnly(
                actor: artistActor,
                displayTitle: "Artist"
            )
            $0.setContributionRole(id: contributionID, roleSelection: .dj)
        }

        await store.send(.saveButtonTapped)?.value

        let rows = try await database.read { db in
            (
                contributors: try OMERecord.Performance.Contributors.fetchAll(db),
                relationships: try OMERecord.Relationship.fetchAll(db)
            )
        }
        let contributor = try #require(rows.contributors.first)
        let relationship = try #require(rows.relationships.first)
        #expect(rows.contributors.count == 1)
        #expect(rows.relationships.count == 1)
        #expect(contributor.performanceID == performance.id)
        #expect(contributor.contributorID == nil)
        #expect(contributor.contributorActor == artistActor)
        #expect(contributor.role == "dj")
        #expect(relationship.subject == .known(.identity(did: artistDID)))
        #expect(relationship.role == .dj)
        #expect(relationship.object == .known(.record(.init(performanceID: performance.id))))
    }

    @Test
    func loadsCommonAndCustomRelationshipRoles() async throws {
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

        try await database.write { db in
            try #sql("""
                UPDATE "performanceContributors"
                SET "role" = 'dj'
                WHERE "organizerID" = \(fixture.eventID.organizerID)
                  AND "eventID" = \(fixture.eventID.eventID)
                  AND "performanceID" = \(performance.id.performanceID)
                """)
                .execute(db)
        }

        _ = try makePerformanceStore(
            database: database,
            fixture: fixture,
            timeZone: timeZone,
            performance: performance
        ) {
            let contribution = try #require($0.contributions.first)
            #expect(contribution.roleSelection == .dj)
            #expect(contribution.customRelationshipRole == "")
        }

        try await database.write { db in
            try #sql("""
                UPDATE "performanceContributors"
                SET "role" = 'lightingDesigner'
                WHERE "organizerID" = \(fixture.eventID.organizerID)
                  AND "eventID" = \(fixture.eventID.eventID)
                  AND "performanceID" = \(performance.id.performanceID)
                """)
                .execute(db)
        }

        _ = try makePerformanceStore(
            database: database,
            fixture: fixture,
            timeZone: timeZone,
            performance: performance
        ) {
            let contribution = try #require($0.contributions.first)
            #expect(contribution.roleSelection == .custom)
            #expect(contribution.customRelationshipRole == "lightingDesigner")
        }
    }

    @Test
    func contributorRelationshipPickerSearchesLocalFirstAndLooksUpExactIdentityOnSubmit() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let contributors = try await database.read { db in
            try ContributorProfile
                .all(eventID: fixture.eventID, hydration: .none)
                .fetchAll(db)
        }
        let exactLookupInputs = ScheduleAuthoringObservationRecorder<String>()
        let typeaheadQueries = ScheduleAuthoringObservationRecorder<String>()
        let exactIdentity = ActorIdentity(
            did: try #require(DID("did:plc:exactartist")),
            handle: Atmosphere.Account.Handle(rawValue: "exactartist.bsky.social"),
            displayName: "Exact Artist",
            source: .canonicalResolution
        )
        let typeaheadIdentity = ActorIdentity(
            did: try #require(DID("did:plc:typeaheadartist")),
            handle: Atmosphere.Account.Handle(rawValue: "typeaheadartist.bsky.social"),
            displayName: "Typeahead Artist",
            source: .typeahead
        )
        let store = withDependencies {
            $0.context = .test
            $0.actorTypeaheadSearch.search = { query in
                await typeaheadQueries.record(query.normalizedText)
                return [typeaheadIdentity]
            }
            $0.actorIdentityLookup.resolve = { input in
                await exactLookupInputs.record(input)
                return exactIdentity
            }
        } operation: {
            TestStore(initialState: ContributorRelationshipPicker.State(contributors: contributors)) {
                ContributorRelationshipPicker()
            }
        }
        expectNoDifference(store.state.filteredContributors.map(\.name), [])

        await store.send(.searchQueryChanged(" artist "))?.value

        expectNoDifference(
            store.state.filteredContributors.map(\.name),
            ["Artist One"]
        )
        expectNoDifference(store.state.actorSearchSections.map(\.title), ["Profiles"])
        expectNoDifference(
            store.state.actorSearchSections.flatMap(\.results),
            [typeaheadIdentity]
        )
        #expect(await typeaheadQueries.values == ["artist"])
        #expect(await exactLookupInputs.values == [])

        await store.send(.actorSearchSubmitted)?.value

        expectNoDifference(store.state.actorSearchSections.map(\.title), ["Exact match"])
        expectNoDifference(
            store.state.actorSearchSections.flatMap(\.results),
            [exactIdentity]
        )
        #expect(await exactLookupInputs.values == ["artist"])
    }

    @Test
    func contributorRelationshipPickerRowActionsSelectExpectedSubjectKinds() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let contributors = try await database.read { db in
            try ContributorProfile
                .all(eventID: fixture.eventID, hydration: .none)
                .fetchAll(db)
        }
        var initialState = ContributorRelationshipPicker.State(contributors: contributors)
        initialState.searchQuery = "Guest Artist"
        let identity = ActorIdentity(
            did: try #require(DID("did:plc:rowactionartist")),
            handle: Atmosphere.Account.Handle(rawValue: "rowactionartist.bsky.social"),
            displayName: "Row Action Artist",
            source: .typeahead
        )
        let actor = try #require(OMERecord.Contributor.Actor(identity.did.description))
        let selectedIdentity = ContributorRelationshipPicker.SelectedActorIdentity(identity)
        let store = TestStore(initialState: initialState) {
            ContributorRelationshipPicker()
        }

        store.send(.existingContributorTapped(fixture.contributor.id.contributorID)) {
            $0.selection = .existingContributor(fixture.contributor.id.contributorID)
        }
        store.send(.createContributorButtonTapped) {
            $0.selection = .newContributor(name: "Guest Artist")
        }
        store.send(.performanceDisplayNameButtonTapped) {
            $0.selection = .performanceDisplayName(name: "Guest Artist")
        }
        store.send(.identityLinkOnlyButtonTapped(identity)) {
            $0.selection = .identityOnly(
                actor: actor,
                displayTitle: "Row Action Artist"
            )
            $0.actorSearchErrorMessage = nil
        }
        store.send(.identityCreateContributorButtonTapped(identity)) {
            $0.selection = .newContributorFromIdentity(selectedIdentity)
            $0.actorSearchErrorMessage = nil
        }
    }

    @Test
    func performanceContributorSearchSelectionAddsRowWithNilRole() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let contributors = try await database.read { db in
            try ContributorProfile
                .all(eventID: fixture.eventID, hydration: .none)
                .fetchAll(db)
        }
        var initialState = EditPerformance.State(
            eventID: fixture.eventID,
            schedule: fixture.schedule,
            stages: [fixture.stage],
            timeZone: timeZone,
            contributors: contributors
        )
        initialState.contributorRelationshipPicker.searchQuery = "Artist"
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: initialState) {
                EditPerformance()
            }
        }

        store.send(
            .contributorRelationshipPicker(
                .existingContributorTapped(fixture.contributor.id.contributorID)
            )
        ) {
            $0.contributions = [
                EditPerformance.State.Contribution(
                    id: 0,
                    selection: .existingContributor(fixture.contributor.id.contributorID)
                )
            ]
            $0.nextContributionID = 1
            $0.contributorRelationshipPicker.searchQuery = ""
        }

        #expect(store.state.contributions.first?.roleSelection == nil)
    }

    @Test
    func performanceTitleTracksPrimaryContributorNamesUntilEdited() async throws {
        let database = try makePreparedDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let fixture = try await seedScheduleFixture(
            database: database,
            timeZone: timeZone
        )
        let contributors = try await database.read { db in
            try ContributorProfile
                .all(eventID: fixture.eventID, hydration: .none)
                .fetchAll(db)
        }
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: EditPerformance.State(
                    eventID: fixture.eventID,
                    schedule: fixture.schedule,
                    stages: [fixture.stage],
                    timeZone: timeZone,
                    contributors: contributors
                )
            ) {
                EditPerformance()
            }
        }

        store.send(
            .contributorRelationshipPicker(
                .existingContributorTapped(fixture.contributor.id.contributorID)
            )
        ) {
            $0.contributions = [
                EditPerformance.State.Contribution(
                    id: 0,
                    selection: .existingContributor(fixture.contributor.id.contributorID)
                )
            ]
            $0.generatedTitle = "Artist One"
            $0.nextContributionID = 1
            $0.title = "Artist One"
        }

        store.modify {
            $0.contributorRelationshipPicker.searchQuery = "Guest Artist"
        }
        store.send(.contributorRelationshipPicker(.performanceDisplayNameButtonTapped)) {
            $0.contributions = [
                EditPerformance.State.Contribution(
                    id: 0,
                    selection: .existingContributor(fixture.contributor.id.contributorID)
                ),
                EditPerformance.State.Contribution(
                    id: 1,
                    selection: .performanceDisplayName(name: "Guest Artist"),
                    billing: .supporting
                ),
            ]
            $0.contributorRelationshipPicker.searchQuery = ""
            $0.nextContributionID = 2
        }

        store.send(.contributionBillingButtonTapped(1, .primary)) {
            $0.contributions[1].billing = .primary
            $0.generatedTitle = "Artist One b2b Guest Artist"
            $0.title = "Artist One b2b Guest Artist"
        }
        store.send(.titleTextChanged("Custom Set")) {
            $0.title = "Custom Set"
            $0.titleIsGenerated = false
        }
        store.send(.contributionBillingButtonTapped(1, .supporting)) {
            $0.contributions[1].billing = .supporting
            $0.generatedTitle = "Artist One"
        }
        #expect(store.state.title == "Custom Set")
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

        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = fixture.eventID
            $0.defaultEventTimeZone = timeZone
        } operation: {
            state.handleEditingIntent(
                .editPerformance(
                    eventID: fixture.eventID,
                    performanceID: performance.id.performanceID
                )
            )
        }

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
    ) throws -> TestStore<EditPerformance> {
        try withDependencies {
            $0.context = .test
            $0.date.now = Date(timeIntervalSince1970: 1_779_800_000)
            $0.defaultDatabase = database
        } operation: {
            let contributors = try database.read { db in
                try ContributorProfile
                    .all(eventID: fixture.eventID, hydration: .none)
                    .fetchAll(db)
            }
            var state: EditPerformance.State
            if let performance {
                let performanceContributors = try database.read { db in
                    try EditPerformance
                        .performanceContributorsQuery(
                            performanceID: performance.id.performanceID,
                            eventID: fixture.eventID
                        )
                        .fetchAll(db)
                }
                state = EditPerformance.State(
                    eventID: fixture.eventID,
                    schedule: fixture.schedule,
                    stages: [fixture.stage],
                    timeZone: timeZone,
                    performance: performance,
                    contributors: contributors,
                    performanceContributors: performanceContributors
                )
            } else {
                state = EditPerformance.State(
                    eventID: fixture.eventID,
                    schedule: fixture.schedule,
                    stages: [fixture.stage],
                    timeZone: timeZone,
                    contributors: contributors
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

    private func addPerformanceEditorState(
        database: any DatabaseWriter,
        eventID: OMERecord.Event.ID,
        timeZone: TimeZone,
        scheduleID: OMERecord.ID<OMERecord.Schedule>?,
        stageID: OMERecord.ID<OMERecord.Stage>?
    ) throws -> Spawn<EditPerformance> {
        var state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.defaultEventTimeZone = timeZone
        } operation: {
            EventViewer.State(eventID: eventID)
        }

        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.defaultEventTimeZone = timeZone
        } operation: {
            state.handleEditingIntent(
                .addPerformance(
                    eventID: eventID,
                    scheduleID: scheduleID,
                    stageID: stageID
                )
            )
        }

        return try #require(state.destination?.performanceForm)
    }

    private func seedEvent(
        database: any DatabaseWriter,
        timeZone: TimeZone,
        startDate: LocalDate? = nil
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
                    startDate: startDate,
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
        let performance = try await seedPerformance(
            database: database,
            eventID: fixture.eventID,
            schedule: fixture.schedule,
            stage: fixture.stage,
            performanceID: performanceID,
            title: "Opening Set",
            description: "Original description.",
            startTime: startTime,
            endTime: endTime
        )
        try await database.write { db in
            try OMERecord.Performance.Contributors.insert {
                OMERecord.Performance.Contributors.Draft(
                    performanceID: performanceID,
                    contributorID: fixture.contributor.id.contributorID,
                    anonymousName: nil,
                    contributorActor: nil
                )
            }
            .execute(db)
        }
        return performance
    }

    private func seedPerformance(
        database: any DatabaseWriter,
        eventID: OMERecord.Event.ID,
        schedule: OMERecord.Schedule,
        stage: OMERecord.Stage,
        performanceID: OMERecord.Performance.ID,
        title: String,
        description: String? = nil,
        startTime: Date,
        endTime: Date
    ) async throws -> OMERecord.Performance {
        try await database.write { db in
            try OMERecord.Performance.insert {
                OMERecord.Performance.Draft(
                    id: performanceID,
                    stageID: stage.id.stageID,
                    scheduleID: schedule.id.scheduleID,
                    startTime: startTime,
                    endTime: endTime,
                    title: title,
                    description: description,
                    recordings: []
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

    private func seedAdditionalScheduleContext(
        database: any DatabaseWriter,
        eventID: OMERecord.Event.ID
    ) async throws -> (schedule: OMERecord.Schedule, stage: OMERecord.Stage) {
        let scheduleDate = try #require(LocalDate("2026-07-31"))
        let scheduleID = OMERecord.Schedule.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            scheduleID: scheduleLocalID("friday")
        )
        let stageID = OMERecord.Stage.ID(
            organizerID: eventID.organizerID,
            eventID: eventID.eventID,
            stageID: stageLocalID("meadow")
        )
        try await database.write { db in
            try OMERecord.Stage.insert {
                OMERecord.Stage.Draft(
                    id: stageID,
                    name: "Meadow",
                    color: 0x00aa55,
                    sortIndex: 0
                )
            }
            .execute(db)
            try OMERecord.Schedule.insert {
                OMERecord.Schedule.Draft(
                    id: scheduleID,
                    date: scheduleDate,
                    startsAt: nil,
                    endsAt: nil,
                    customTitle: "Friday"
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
            return (
                schedule: try #require(schedule),
                stage: try #require(stage)
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

private actor ScheduleAuthoringObservationRecorder<Value: Sendable> {
    private var recordedValues: [Value] = []

    var values: [Value] {
        recordedValues
    }

    func record(_ value: Value) {
        recordedValues.append(value)
    }
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
