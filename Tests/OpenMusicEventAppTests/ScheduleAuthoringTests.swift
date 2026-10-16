import ATProto
import Bluesky
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import OpenMusicEventDatabase
import ScheduleComponents
import Sharing
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
    func dateSelectionUpdatesInferredScheduleTitle() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let eventID = try #require(Event.ID(
            "at://did:web:wickedwoods.example/events.openmusic.event/3mrdbziccpcah"
        ))
        let friday = try #require(LocalDate("2026-08-07"))
        let saturday = try #require(LocalDate("2026-08-08"))
        let store = TestStore(
            initialState: ScheduleForm.State(
                eventID: eventID,
                initialDate: friday,
                timeZone: timeZone
            )
        ) { ScheduleForm() }

        expectNoDifference(store.state.customTitle, "")
        expectNoDifference(store.state.inferredTitle, "Friday")
        expectNoDifference(store.state.scheduleDate, friday)

        store.modify {
            $0.dateSelection = saturday.atStartOfDay(in: timeZone)
        }
        expectNoDifference(store.state.scheduleDate, saturday)
        expectNoDifference(store.state.inferredTitle, "Saturday")
    }

    @Test
    func dateSelectionKeepsEditedScheduleTitle() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let eventID = try #require(Event.ID(
            "at://did:web:wickedwoods.example/events.openmusic.event/3mrdbziccpcah"
        ))
        let friday = try #require(LocalDate("2026-08-07"))
        let saturday = try #require(LocalDate("2026-08-08"))
        let store = TestStore(
            initialState: ScheduleForm.State(
                eventID: eventID,
                initialDate: friday,
                timeZone: timeZone
            )
        ) { ScheduleForm() }

        store.modify {
            $0.customTitle = "Opening Workshops"
            $0.dateSelection = saturday.atStartOfDay(in: timeZone)
        }

        expectNoDifference(store.state.customTitle, "Opening Workshops")
        expectNoDifference(store.state.scheduleDate, saturday)
        expectNoDifference(store.state.inferredTitle, "Saturday")
    }

    @Test
    func scheduleViewerAddPerformanceRequestUsesSelectedScheduleAndStage() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let fridayID = try #require(Schedule.ID(
            "at://did:plc:organizer/events.openmusic.schedule/3mrdbziccpcan"
        ))
        let meadowID = try #require(EventPlace.ID(
            "at://did:plc:organizer/events.openmusic.eventPlace/3mrdbziccpcae"
        ))
        let friday = try Schedule(
            id: fridayID,
            event: fixture.event.id,
            date: #require(LocalDate("2026-07-31")),
            createdAt: "2026-09-01T12:00:00Z"
        )
        var meadow = try EventPlace(
            id: meadowID,
            event: fixture.event.id,
            name: "Meadow",
            createdAt: "2026-09-01T12:00:00Z"
        )
        meadow.kind = .known(.stage(EventPlace.Kind.Stage()))
        let selectedStage = meadow
        try await database.write { db in
            try Schedule.insert { friday }.execute(db)
            try EventPlace.insert { selectedStage }.execute(db)
            var event = try #require(try Event.find(fixture.event.id).fetchOne(db))
            event.schedules = [fridayID, fixture.schedule.id]
            let updatedEvent = event
            try Event.upsert { updatedEvent }.execute(db)
            var program = try #require(try Program.find(fixture.program.id).fetchOne(db))
            program.eventPlaces = [meadowID, fixture.stage.id]
            let updatedProgram = program
            try Program.upsert { updatedProgram }.execute(db)
        }
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.uuid = .incrementing
        } operation: {
            var state = ScheduleList.State(
                eventID: fixture.event.id,
                scheduleDivision: .init(
                    programID: fixture.program.id,
                    title: fixture.program.title,
                    eventPlaces: [meadowID, fixture.stage.id]
                )
            )
            state.scheduleViewerState.selectedStageID = meadowID
            return TestStore(initialState: state) {
                ScheduleList()
            }
        }
        #expect(store.state.visibleStages.map(\.id).contains(meadowID))
        #expect(store.state.scheduleViewerState.selectedStageID == meadowID)
        #expect(store.state.selectedStageID == meadowID)

        let addTask = store.send(
            .addPerformanceButtonTapped(fridayID)
        )
        await store.receive(
            key: EventEditingRequested.self,
            value: .equals(
                .addPerformance(
                    eventID: fixture.event.id,
                    scheduleID: fridayID,
                    programID: fixture.program.id,
                    stageID: meadowID
                )
            ),
            timeout: .seconds(1)
        )
        await addTask?.value
    }

    @Test
    func emptyScheduleCanStartWithAStageOrPerformance() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        try await database.write { db in
            try ProgramItem.delete().execute(db)
            try Program.delete().execute(db)
            try Schedule.delete().execute(db)
            try EventPlace.delete().execute(db)
            var event = fixture.event
            event.programs = nil
            event.schedules = nil
            try Event.upsert { event }.execute(db)
        }
        let store = withDependencies {
            $0.context = .test
            $0.uuid = .incrementing
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: ScheduleList.State(eventID: fixture.event.id)) {
                ScheduleList()
            }
        }

        // An editor can start an empty event with a stage, without a schedule first.
        let stageTask = store.send(.addStageButtonTapped)
        await store.receive(
            key: EventEditingRequested.self,
            value: .equals(.createPlace(fixture.event.id)),
            timeout: .seconds(1)
        )
        await stageTask?.value

        // Or start with a performance; the existing editor resolves its prerequisites.
        let performanceTask = store.send(.addPerformanceButtonTapped(nil))
        await store.receive(
            key: EventEditingRequested.self,
            value: .equals(.addPerformance(
                eventID: fixture.event.id,
                scheduleID: nil,
                programID: nil,
                stageID: nil
            )),
            timeout: .seconds(1)
        )
        await performanceTask?.value
    }

    @Test
    func emptyStageScheduleCreatesPerformanceOnThatStage() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        try await database.write { db in
            try ProgramItem.delete().execute(db)
        }
        let store = withDependencies {
            $0.context = .test
            $0.uuid = .incrementing
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EventPlaceDetail.State(
                eventPlaceID: fixture.stage.id,
                eventID: fixture.event.id
            )) {
                EventPlaceDetail()
            }
        }

        // Starting from an empty stage retains both its program and selected day.
        let task = store.send(.addPerformanceButtonTapped)
        await store.receive(
            key: EventEditingRequested.self,
            value: .equals(.addPerformance(
                eventID: fixture.event.id,
                scheduleID: fixture.schedule.id,
                programID: fixture.program.id,
                stageID: fixture.stage.id
            )),
            timeout: .seconds(1)
        )
        await task?.value

        let scheduleTask = store.send(.addScheduleButtonTapped)
        await store.receive(
            key: EventEditingRequested.self,
            value: .equals(.addSchedule(fixture.event.id)),
            timeout: .seconds(1)
        )
        await scheduleTask?.value
    }

    @Test
    func scheduleViewerCanAddPerformanceWhileSchedulelessEventIsLoading() {
        expectNoDifference(
            ScheduleList.canAddPerformance(
                selectedScheduleID: nil,
                schedules: [],
                division: .schedule,
                event: nil
            ),
            true
        )
    }

    @Test
    func untimedProgramItemUsesListEvenAfterAssigningAVisiblePlace() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let itemID = try #require(ProgramItem.ID(
            "at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcaq"
        ))
        var item = try ProgramItem(
            id: itemID,
            event: fixture.event.id,
            program: fixture.program.id,
            title: "Location TBA",
            createdAt: "2026-09-01T12:00:00Z"
        )
        item.schedule = fixture.schedule.id
        let unplacedItem = item
        try await database.write { db in
            try ProgramItem.insert { unplacedItem }.execute(db)
        }

        func viewerState() -> ScheduleList.State {
            withDependencies {
                $0.context = .test
                $0.defaultDatabase = database
            } operation: {
                ScheduleList.State(
                    eventID: fixture.event.id,
                    scheduleDivision: .init(program: fixture.program)
                )
            }
        }

        #expect(viewerState().requiresListPresentation(selectedScheduleID: fixture.schedule.id))

        item.eventPlace = fixture.stage.id
        let placedItem = item
        try await database.write { db in
            try ProgramItem.upsert { placedItem }.execute(db)
        }
        #expect(viewerState().requiresListPresentation(selectedScheduleID: fixture.schedule.id))
    }

    @Test
    func eventViewerAddPerformanceIntentSeedsSelectedScheduleAndStage() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let selectedContext = try seedAdditionalCanonicalScheduleContext(
            database: database, fixture: fixture
        )
        let expectedStart = try #require(
            selectedContext.schedule.date.at(hour: 19, minute: 30, in: timeZone)
        )
        let openerID = try #require(ProgramItem.ID(
            "at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcae"
        ))
        try seedCanonicalPerformance(
            database: database, fixture: fixture, id: openerID,
            schedule: selectedContext.schedule,
            stage: selectedContext.stage,
            title: "Meadow Opener",
            startTime: try #require(
                selectedContext.schedule.date.at(hour: 18, in: timeZone)
            ),
            endTime: expectedStart
        )
        let expectedEnd = expectedStart.addingTimeInterval(60 * 60)
        let editPerformance = try addCanonicalPerformanceEditorState(
            database: database,
            fixture: fixture,
            scheduleID: selectedContext.schedule.id,
            stageID: selectedContext.stage.id
        )
        expectNoDifference(
            try #require(editPerformance.schedule).id,
            selectedContext.schedule.id
        )
        expectNoDifference(
            editPerformance.schedules.map(\.id),
            [selectedContext.schedule.id, fixture.schedule.id]
        )
        expectNoDifference(
            editPerformance.selectedStageID,
            selectedContext.stage.id
        )
        expectNoDifference(editPerformance.startTimeSelection, expectedStart)
        expectNoDifference(editPerformance.endTimeSelection, expectedEnd)
    }

    @Test
    func eventViewerAddPerformanceIntentIgnoresLaterSetsOnOtherStages() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let selectedContext = try seedAdditionalCanonicalScheduleContext(
            database: database, fixture: fixture
        )
        let expectedStart = try #require(
            selectedContext.schedule.date.at(hour: 19, in: timeZone)
        )
        let activeStageItemID = try #require(ProgramItem.ID(
            "at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcae"
        ))
        try seedCanonicalPerformance(
            database: database, fixture: fixture, id: activeStageItemID,
            schedule: selectedContext.schedule,
            stage: selectedContext.stage,
            title: "Active Stage Set",
            startTime: try #require(
                selectedContext.schedule.date.at(hour: 18, in: timeZone)
            ),
            endTime: expectedStart
        )
        let otherStageItemID = try #require(ProgramItem.ID(
            "at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpca6"
        ))
        try seedCanonicalPerformance(
            database: database, fixture: fixture, id: otherStageItemID,
            schedule: selectedContext.schedule,
            stage: fixture.stage,
            title: "Other Stage Late Set",
            startTime: try #require(
                selectedContext.schedule.date.at(hour: 22, in: timeZone)
            ),
            endTime: try #require(
                selectedContext.schedule.date.at(hour: 23, in: timeZone)
            )
        )
        let editPerformance = try addCanonicalPerformanceEditorState(
            database: database,
            fixture: fixture,
            scheduleID: selectedContext.schedule.id,
            stageID: selectedContext.stage.id
        )
        expectNoDifference(editPerformance.startTimeSelection, expectedStart)
        expectNoDifference(
            editPerformance.endTimeSelection,
            expectedStart.addingTimeInterval(60 * 60)
        )
    }

    @Test
    func eventViewerAddPerformanceIntentKeepsNoonDefaultWithoutPriorStageSet() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let selectedContext = try seedAdditionalCanonicalScheduleContext(
            database: database, fixture: fixture
        )
        let expectedStart = try #require(
            selectedContext.schedule.date.at(hour: 12, in: timeZone)
        )
        let expectedEnd = try #require(
            selectedContext.schedule.date.at(hour: 13, in: timeZone)
        )
        let editPerformance = try addCanonicalPerformanceEditorState(
            database: database,
            fixture: fixture,
            scheduleID: selectedContext.schedule.id,
            stageID: selectedContext.stage.id
        )
        expectNoDifference(editPerformance.startTimeSelection, expectedStart)
        expectNoDifference(editPerformance.endTimeSelection, expectedEnd)
    }

    @Test
    func eventViewerAddPerformanceIntentCreatesScheduleWhenEventHasNoSchedule() async throws {
        let database = try canonicalPerformanceDatabase()
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let scheduleDate = try #require(LocalDate("2026-08-01"))
        let eventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let programID = try #require(Program.ID(
            "at://did:plc:organizer/events.openmusic.program/3mrdbziccpcai"
        ))
        let stageID = try #require(EventPlace.ID(
            "at://did:plc:organizer/events.openmusic.eventPlace/3mrdbziccpcak"
        ))
        var event = try Event(
            id: eventID,
            name: "Wicked Woods 2026",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: timeZone,
            programs: [programID]
        )
        event.start = .known(.day(Event.Day(value: scheduleDate)))
        let savedEvent = event
        let program = try Program(
            id: programID,
            event: eventID,
            title: "Music",
            createdAt: "2026-09-01T12:00:00Z",
            eventPlaces: [stageID]
        )
        var stage = try EventPlace(
            id: stageID,
            event: eventID,
            name: "Main Stage",
            createdAt: "2026-09-01T12:00:00Z"
        )
        stage.kind = .known(.stage(EventPlace.Kind.Stage()))
        let savedStage = stage
        try await database.write { db in
            try Event.insert { savedEvent }.execute(db)
            try Program.insert { program }.execute(db)
            try EventPlace.insert { savedStage }.execute(db)
        }
        let now = try Date("2026-09-02T18:00:00Z", strategy: .iso8601)
        var state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.defaultEventTimeZone = SharedReader(value: timeZone)
        } operation: {
            EventDetail.State(eventID: eventID)
        }

        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.defaultEventTimeZone = SharedReader(value: timeZone)
            $0.date.now = now
        } operation: {
            state.handleEditingIntent(
                .addPerformance(
                    eventID: eventID,
                    scheduleID: nil,
                    programID: programID,
                    stageID: stageID
                )
            )
        }

        let editPerformance = try #require(state.destination?.performanceForm)
        expectNoDifference(try #require(editPerformance.schedule).date, scheduleDate)
        expectNoDifference(editPerformance.selectedStageID, stageID)
        let saved = try await database.read { db in
            (
                schedules: try Schedule.all.fetchAll(db),
                event: try #require(try Event.find(eventID).fetchOne(db))
            )
        }
        let schedule = try #require(saved.schedules.first)
        #expect(saved.schedules.count == 1)
        #expect(schedule.id == editPerformance.schedule?.id)
        #expect(schedule.date == scheduleDate)
        #expect(schedule.event == eventID)
        expectNoDifference(editPerformance.schedules.map(\.id), [schedule.id])
        expectNoDifference(saved.event.schedules, [schedule.id])
        try schedule.validateReferences()
    }

    @Test
    func createsPerformanceRowWithLinkedContributor() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let scheduleDate = fixture.schedule.date
        let startTime = try #require(scheduleDate.at(hour: 20, in: timeZone))
        let endTime = try #require(scheduleDate.at(hour: 21, minute: 30, in: timeZone))
        let store = try makeCanonicalPerformanceStore(
            database: database,
            fixture: fixture
        ) {
            $0.title = "Evening Set"
            $0.description = "Main stage performance."
            $0.appendContribution(selection: .existingContributor(fixture.contributor.id))
            $0.startTimeSelection = startTime
            $0.endTimeSelection = endTime
        }

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let items = try await database.read { db in
            try ProgramItem.all.fetchAll(db)
        }
        let performance = try #require(items.first)
        let credit = try #require(performance.credits?.first)
        #expect(items.count == 1)
        #expect(performance.credits?.count == 1)
        #expect(performance.event == fixture.event.id)
        #expect(performance.program == fixture.program.id)
        #expect(performance.eventPlace == fixture.stage.id)
        #expect(performance.schedule == fixture.schedule.id)
        #expect(performance.startDate == startTime)
        #expect(performance.endDate == endTime)
        #expect(performance.title == "Evening Set")
        #expect(performance.description == "Main stage performance.")
        #expect(credit.name == fixture.contributor.name)
        #expect(credit.contributor == fixture.contributor.id)
        #expect(credit.billing == .known(.primary))
        #expect(credit.role == nil)
        try performance.validateReferences()
    }

    @Test
    func createsAnUnscheduledProgramItemWithoutInventingATime() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let store = try makeCanonicalPerformanceStore(database: database, fixture: fixture) {
            $0.title = "Lineup TBA"
            $0.isAssignedToSchedule = false
        }

        await store.send(.saveButtonTapped)?.value

        let item = try await database.read { db in
            try #require(ProgramItem.all.fetchAll(db).first)
        }
        #expect(store.state.errorMessage == nil)
        #expect(item.schedule == nil)
        #expect(item.startsAt == nil)
        #expect(item.endsAt == nil)
        #expect(item.eventPlace == fixture.stage.id)
        try item.validateReferences()
    }

    @Test
    func schedulelessEventCanCreateAndReopenAnUnscheduledProgramItem() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        try await database.write { db in
            try ScheduleRecordEditing.delete(
                fixture.schedule.id, eventID: fixture.event.id, in: db
            )
        }
        let editor = try addCanonicalPerformanceEditorState(
            database: database,
            fixture: fixture,
            scheduleID: nil,
            stageID: fixture.stage.id
        )
        #expect(editor.schedule == nil)
        #expect(editor.schedules.isEmpty)
        #expect(!editor.isAssignedToSchedule)
        #expect(!editor.hasStartTime)

        let now = try Date("2026-09-02T18:00:00Z", strategy: .iso8601)
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.date.now = now
        } operation: {
            TestStore(initialState: editor) { ProgramItemForm() }
        }
        store.modify { $0.title = "Location TBA" }
        await store.send(.saveButtonTapped)?.value

        let item = try await database.read { db in
            try #require(ProgramItem.all.fetchAll(db).first)
        }
        #expect(item.schedule == nil)
        #expect(item.startsAt == nil)
        #expect(try await database.read { try Schedule.all.fetchCount($0) } == 0)

        let division = ScheduleList.ScheduleDivision(
            programID: fixture.program.id,
            title: fixture.program.title,
            eventPlaces: fixture.program.eventPlaces
        )
        let scheduleViewer = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            ScheduleList.State(eventID: fixture.event.id, scheduleDivision: division)
        }
        #expect(scheduleViewer.requiresListPresentation(selectedScheduleID: nil))
        #expect(scheduleViewer.unscheduledPerformanceRows.map(\.performanceID) == [item.id])
        let performanceList = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            SchedulePerformanceList.State(eventID: fixture.event.id, scheduleDivision: division)
        }
        #expect(performanceList.unscheduledPerformanceRows.map(\.performanceID) == [item.id])

        var viewer = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = fixture.event.id
            $0.defaultEventTimeZone = SharedReader(value: fixture.event.timeZone)
            $0.date.now = now
        } operation: {
            EventDetail.State(eventID: fixture.event.id)
        }
        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = fixture.event.id
            $0.defaultEventTimeZone = SharedReader(value: fixture.event.timeZone)
            $0.date.now = now
        } operation: {
            viewer.handleEditingIntent(
                .editPerformance(eventID: fixture.event.id, performanceID: item.id)
            )
        }
        let reopened = try #require(viewer.destination?.performanceForm)
        #expect(reopened.performanceID == item.id)
        #expect(reopened.schedule == nil)
        #expect(!reopened.isAssignedToSchedule)
    }

    @Test
    func preservesAScheduleDayWithoutRequiringAnEndTime() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let start = try #require(fixture.schedule.date.at(hour: 20, in: fixture.event.timeZone))
        let store = try makeCanonicalPerformanceStore(database: database, fixture: fixture) {
            $0.title = "Doors"
            $0.startTimeSelection = start
            $0.hasEndTime = false
        }

        await store.send(.saveButtonTapped)?.value

        let item = try await database.read { db in
            try #require(ProgramItem.all.fetchAll(db).first)
        }
        #expect(store.state.errorMessage == nil)
        #expect(item.schedule == fixture.schedule.id)
        #expect(item.startDate == start)
        #expect(item.endsAt == nil)
        try item.validateReferences()

        let division = ScheduleList.ScheduleDivision(
            programID: fixture.program.id,
            title: fixture.program.title,
            eventPlaces: fixture.program.eventPlaces
        )
        let viewer = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            ScheduleList.State(eventID: fixture.event.id, scheduleDivision: division)
        }
        #expect(viewer.requiresListPresentation(selectedScheduleID: fixture.schedule.id))

        let editStore = try makeCanonicalPerformanceStore(
            database: database, fixture: fixture, performance: item
        ) { _ in }
        #expect(editStore.state.isAssignedToSchedule)
        #expect(editStore.state.hasStartTime)
        #expect(!editStore.state.hasEndTime)
    }

    @Test
    func creditRowActionsEditNameAndReorder() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let store = try makeCanonicalPerformanceStore(database: database, fixture: fixture) {
            $0.title = "Shared Set"
            $0.titleIsGenerated = false
            $0.appendContribution(selection: .existingContributor(fixture.contributor.id))
            $0.appendContribution(selection: .performanceDisplayName(name: "Guest"))
        }

        store.send(.contributionEditButtonTapped(1)) {
            $0.contributions[1].creditName = "Guest"
            $0.editingContributionID = 1
        }
        store.send(.contributionNameChanged(1, "Special Guest")) {
            $0.contributions[1].creditName = "Special Guest"
        }
        store.send(.contributionEditDoneButtonTapped) {
            $0.editingContributionID = nil
        }
        await store.send(.contributionMoveButtonTapped(1, -1))?.value
        #expect(store.state.contributions.map(\.id) == [1, 0])

        await store.send(.saveButtonTapped)?.value

        let item = try await database.read { db in
            try #require(ProgramItem.all.fetchAll(db).first)
        }
        #expect(item.credits?.map(\.name) == ["Special Guest", fixture.contributor.name])
        #expect(item.credits?.first?.contributor == nil)
        try item.validateReferences()
    }

    @Test
    func programItemPhotoCanBeRemovedWithoutChangingIdentityOrOtherMedia() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let photo = OME.Image(
            source: .known(.url(try #require(URL(string: "https://example.com/set.jpg")))),
            role: .known(.photo),
            renderingMode: .known(.original)
        )
        let store = try makeCanonicalPerformanceStore(database: database, fixture: fixture) {
            $0.title = "Photo Set"
            $0.mediaEntries = [.init(value: .known(.image(photo)))]
        }
        await store.send(.saveButtonTapped)?.value

        let created = try await database.read { db in
            try #require(ProgramItem.all.fetchAll(db).first)
        }
        #expect(created.media == [.known(.image(photo))])

        let external = OME.Media.External(
            uri: try #require(URL(string: "https://example.com/set-video")),
            title: "Set video"
        )
        let poster = OME.Image(
            source: .known(.url(try #require(URL(string: "https://example.com/set-poster.jpg")))),
            role: .known(.poster),
            renderingMode: .known(.original)
        )
        var updated = created
        updated.media = [.known(.image(photo)), .known(.image(poster)), .known(.external(external))]
        let withExternal = updated
        try await database.write { db in
            try ProgramItem.upsert { withExternal }.execute(db)
        }

        var expectedPoster = poster
        expectedPoster.title = "Updated poster"
        let editStore = try makeCanonicalPerformanceStore(
            database: database, fixture: fixture, performance: withExternal
        ) { state in
            #expect(state.mediaEntries.count == 3)
            state.mediaEntries[1].value = .known(.image(expectedPoster))
        }
        let photoID = try #require(editStore.state.mediaEntries.first?.id)
        await editStore.send(.mediaDeleteButtonTapped(photoID))?.value
        await editStore.send(.saveButtonTapped)?.value

        let edited = try await database.read { db in
            try #require(try ProgramItem.find(created.id).fetchOne(db))
        }
        #expect(edited.id == created.id)
        #expect(edited.createdAt == created.createdAt)
        #expect(edited.media == [.known(.image(expectedPoster)), .known(.external(external))])
    }

    @Test
    func editingExternalThumbnailURLKeepsImageMetadata() throws {
        let originalURL = try #require(URL(string: "https://example.com/original.jpg"))
        let replacementURL = try #require(URL(string: "https://example.com/replacement.jpg"))
        let mediaURL = try #require(URL(string: "https://example.com/video"))
        var thumbnail = OME.Image(
            source: .known(.url(originalURL)),
            role: .known(.poster),
            renderingMode: .known(.original)
        )
        thumbnail.title = "Poster"
        thumbnail.appearance = .known(.dark)
        let external = OME.Media.External(uri: mediaURL, thumbnail: thumbnail)
        var draft = withDependencies {
            $0.uuid = .incrementing
        } operation: {
            RecordMediaEditing.MediaDraft(entryID: UUID(), external: external)
        }
        draft.thumbnailURL = replacementURL.absoluteString

        let imageInfo = try #require(draft.thumbnailImageInfoState(recordID: nil))
        #expect(imageInfo.image.title == "Poster")
        #expect(imageInfo.image.role == .known(.poster))
        #expect(imageInfo.image.appearance == .known(.dark))

        var editedImage = imageInfo.image
        editedImage.title = "New poster"
        editedImage.alt = OME.AltText(rawValue: "Main stage")
        draft.updateThumbnailImageInfo(editedImage)
        guard case let .some(.known(.external(saved))) = draft.value() else {
            Issue.record("Expected external media")
            return
        }
        #expect(saved.thumbnail?.source == .known(.url(replacementURL)))
        #expect(saved.thumbnail?.title == "New poster")
        #expect(saved.thumbnail?.alt == OME.AltText(rawValue: "Main stage"))
        #expect(saved.thumbnail?.role == .known(.poster))
        #expect(saved.thumbnail?.appearance == .known(.dark))
    }

    @Test
    func programItemMediaLinksCanBeAddedEditedRemovedAndReordered() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let createStore = try makeCanonicalPerformanceStore(database: database, fixture: fixture) {
            $0.title = "Media Set"
        }
        await createStore.send(.saveButtonTapped)?.value

        let created = try await database.read { db in
            try #require(ProgramItem.all.fetchAll(db).first)
        }
        let photo = OME.Image(
            source: .known(.url(try #require(URL(string: "https://example.com/photo.jpg")))),
            role: .known(.photo),
            renderingMode: .known(.original)
        )
        let external = OME.Media.External(
            uri: try #require(URL(string: "https://example.com/old-video")),
            title: "Old video"
        )
        let oldRecord = OME.Media.RecordReference(
            uri: try #require(ATProto.URI("at://did:plc:organizer/app.bsky.feed.post/old"))
        )
        var withMedia = created
        withMedia.media = [
            .known(.image(photo)),
            .known(.external(external)),
            .known(.record(oldRecord)),
        ]
        let seededItem = withMedia
        try await database.write { db in
            try ProgramItem.upsert { seededItem }.execute(db)
        }

        let store = try makeCanonicalPerformanceStore(
            database: database, fixture: fixture, performance: seededItem
        ) { _ in }
        let externalID = try #require(store.state.mediaEntries.dropFirst().first?.id)
        let oldRecordID = try #require(store.state.mediaEntries.last?.id)
        store.send(.mediaEditButtonTapped(externalID))
        #expect(store.state.mediaDraft?.entryID == externalID)
        store.send(.mediaDraftURIChanged("https://example.com/new-video")) {
            $0.mediaDraft?.uri = "https://example.com/new-video"
        }
        store.send(.mediaDraftTitleChanged("Live set")) {
            $0.mediaDraft?.title = "Live set"
        }
        store.send(.mediaDraftDescriptionChanged("Recorded on the main stage")) {
            $0.mediaDraft?.description = "Recorded on the main stage"
        }
        store.send(.mediaDraftKindChanged("video")) {
            $0.mediaDraft?.mediaKind = "video"
        }
        store.send(.mediaDraftThumbnailURLChanged("https://example.com/thumb.jpg")) {
            $0.mediaDraft?.thumbnailURL = "https://example.com/thumb.jpg"
            $0.mediaDraft?.removeThumbnail = false
        }
        store.send(.mediaDraftAltChanged("Stage lights")) {
            $0.mediaDraft?.thumbnailAlt = "Stage lights"
        }
        store.send(.mediaDraftSaveButtonTapped)
        #expect(store.state.mediaDraft == nil)
        store.send(.mediaDeleteButtonTapped(oldRecordID))

        store.send(.addRecordMediaButtonTapped)
        #expect(store.state.mediaDraft?.kind == .record)
        store.send(.mediaDraftURIChanged("https://example.com/not-a-record")) {
            $0.mediaDraft?.uri = "https://example.com/not-a-record"
        }
        #expect(store.state.mediaDraft?.validationMessage != nil)
        store.send(.mediaDraftSaveButtonTapped)
        #expect(store.state.mediaDraft != nil)
        let newRecordURI = "at://did:plc:organizer/app.bsky.feed.post/new"
        store.send(.mediaDraftURIChanged(newRecordURI)) {
            $0.mediaDraft?.uri = newRecordURI
        }
        store.send(.mediaDraftSaveButtonTapped)
        let newRecordID = try #require(store.state.mediaEntries.last?.id)
        store.send(.mediaMoveButtonTapped(newRecordID, -1))
        store.send(.mediaMoveButtonTapped(newRecordID, -1))
        #expect(store.state.mediaEntries.first?.id == newRecordID)
        await store.send(.saveButtonTapped)?.value

        let edited = try await database.read { db in
            try #require(try ProgramItem.find(created.id).fetchOne(db))
        }
        var thumbnail = OME.Image(
            source: .known(.url(try #require(URL(string: "https://example.com/thumb.jpg")))),
            role: .known(.photo),
            renderingMode: .known(.original)
        )
        thumbnail.alt = OME.AltText(rawValue: "Stage lights")
        let expectedExternal = OME.Media.External(
            uri: try #require(URL(string: "https://example.com/new-video")),
            title: "Live set",
            description: "Recorded on the main stage",
            thumbnail: thumbnail,
            mediaKind: .known(.video)
        )
        let newRecord = OME.Media.RecordReference(uri: try #require(ATProto.URI(newRecordURI)))
        #expect(edited.id == created.id)
        #expect(edited.createdAt == created.createdAt)
        #expect(edited.media == [
            .known(.record(newRecord)),
            .known(.image(photo)),
            .known(.external(expectedExternal)),
        ])
    }

    @Test
    func createsPerformanceRowsWithMultipleContributors() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let scheduleDate = fixture.schedule.date
        let store = try makeCanonicalPerformanceStore(
            database: database,
            fixture: fixture
        ) {
            $0.title = "Shared Set"
            $0.appendContribution(
                selection: .existingContributor(fixture.contributor.id)
            )
            $0.appendContribution(
                selection: .performanceDisplayName(name: "Mystery Guest"),
                billing: .known(.supporting)
            )
            $0.startTimeSelection = try #require(scheduleDate.at(hour: 22, in: timeZone))
            $0.endTimeSelection = try #require(scheduleDate.at(hour: 23, in: timeZone))
        }

        await store.send(.saveButtonTapped)?.value

        let rows = try await database.read { db in
            (
                items: try ProgramItem.all.fetchAll(db),
                contributors: try Contributor.all.fetchAll(db)
            )
        }
        let performance = try #require(rows.items.first)
        let credits = try #require(performance.credits)
        #expect(rows.items.count == 1)
        #expect(rows.contributors.count == 1)
        #expect(credits.count == 2)
        #expect(credits[0].name == fixture.contributor.name)
        #expect(credits[0].contributor == fixture.contributor.id)
        #expect(credits[0].billing == .known(.primary))
        #expect(credits[0].role == nil)
        #expect(credits[1].name == "Mystery Guest")
        #expect(credits[1].contributor == nil)
        #expect(credits[1].billing == .known(.supporting))
        #expect(credits[1].role == nil)
        try performance.validateReferences()
    }

    @Test
    func createsPerformanceRowWithNewManualContributor() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let scheduleDate = fixture.schedule.date
        let store = try makeCanonicalPerformanceStore(
            database: database,
            fixture: fixture
        ) {
            $0.title = "Manual Contributor Set"
            $0.appendContribution(selection: .newContributor(name: "Guest Artist"))
            $0.startTimeSelection = try #require(scheduleDate.at(hour: 22, in: timeZone))
            $0.endTimeSelection = try #require(scheduleDate.at(hour: 23, in: timeZone))
        }

        await store.send(.saveButtonTapped)?.value

        let rows = try await database.read { db in
            (
                contributors: try Contributor.all.fetchAll(db),
                items: try ProgramItem.all.fetchAll(db)
            )
        }
        let newContributor = try #require(
            rows.contributors.first { $0.name == "Guest Artist" }
        )
        let performance = try #require(rows.items.first)
        let credit = try #require(performance.credits?.first)
        #expect(rows.contributors.count == 2)
        #expect(newContributor.event == fixture.event.id)
        #expect(newContributor.subject == nil)
        #expect(credit.name == "Guest Artist")
        #expect(credit.contributor == newContributor.id)
        #expect(credit.billing == .known(.primary))
        try newContributor.validateReferences()
        try performance.validateReferences()
    }

    @Test
    func rejectsInvalidPerformanceTimeRange() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let startTime = try #require(fixture.schedule.date.at(hour: 20, in: timeZone))
        let store = try makeCanonicalPerformanceStore(
            database: database,
            fixture: fixture
        ) {
            $0.title = "Broken Time"
            $0.startTimeSelection = startTime
            $0.endTimeSelection = startTime
        }

        store.send(.saveButtonTapped) {
            $0.errorMessage = "End time must be after the start time."
        }

        let performanceCount = try await database.read { db in
            try ProgramItem.all.fetchCount(db)
        }
        #expect(performanceCount == 0)
    }

    @Test
    func createsOvernightPerformanceRow() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
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
        let store = try makeCanonicalPerformanceStore(
            database: database,
            fixture: fixture
        ) {
            $0.title = "Late Night Set"
            $0.startTimeSelection = startTime
            $0.timeRangeSelection.endClockTimeSelection = endClockTime
        }

        await store.send(.saveButtonTapped)?.value

        let performance = try await database.read { db in
            try #require(ProgramItem.all.fetchAll(db).first)
        }
        #expect(performance.startDate == startTime)
        #expect(performance.endDate == expectedEndTime)
        #expect(performance.title == "Late Night Set")
        #expect(performance.schedule == fixture.schedule.id)
        try performance.validateReferences()
    }

    @Test
    func createsPerformanceRowWithAnonymousName() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let scheduleDate = fixture.schedule.date
        let store = try makeCanonicalPerformanceStore(
            database: database,
            fixture: fixture
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
                performances: try ProgramItem.all.fetchAll(db),
                contributors: try Contributor.all.fetchAll(db)
            )
        }
        let performance = try #require(rows.performances.first)
        let credit = try #require(performance.credits?.first)
        #expect(rows.performances.count == 1)
        #expect(rows.contributors.count == 1)
        #expect(performance.title == "Surprise Set")
        #expect(credit.contributor == nil)
        #expect(credit.name == "Surprise Guest")
        #expect(credit.billing == .known(.primary))
        try performance.validateReferences()
    }

    @Test
    func createsPerformanceRowWithIdentityRelationship() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let artistDID = try #require(DID("did:plc:artist123"))
        let scheduleDate = fixture.schedule.date
        let store = try makeCanonicalPerformanceStore(
            database: database,
            fixture: fixture
        ) {
            $0.title = "Identity Set"
            $0.appendContribution(
                selection: .identityOnly(
                    actor: artistDID,
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
                performances: try ProgramItem.all.fetchAll(db),
                contributors: try Contributor.all.fetchAll(db)
            )
        }
        let performance = try #require(rows.performances.first)
        let contributor = try #require(rows.contributors.first { $0.subject == artistDID })
        let credit = try #require(performance.credits?.first)
        #expect(rows.performances.count == 1)
        #expect(performance.credits?.count == 1)
        #expect(rows.contributors.count == 2)
        #expect(contributor.event == fixture.event.id)
        #expect(contributor.name == "Artist")
        #expect(credit.name == "Artist")
        #expect(credit.contributor == contributor.id)
        #expect(credit.role == "dj")
        #expect(credit.billing == .known(.primary))
        try performance.validateReferences()
    }

    @Test
    func createsPerformanceRowWithContributorFromIdentity() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let identity = ActorIdentity(
            did: try #require(DID("did:plc:identityartist")),
            handle: Atmosphere.Account.Handle(rawValue: "identityartist.bsky.social"),
            displayName: "Identity Artist",
            source: .typeahead
        )
        let scheduleDate = fixture.schedule.date
        let store = try makeCanonicalPerformanceStore(
            database: database,
            fixture: fixture
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
                contributors: try Contributor.all.fetchAll(db),
                items: try ProgramItem.all.fetchAll(db)
            )
        }
        let createdContributor = try #require(
            rows.contributors.first { $0.subject == identity.did }
        )
        let performance = try #require(rows.items.first)
        let credit = try #require(performance.credits?.first)
        #expect(rows.contributors.count == 2)
        #expect(createdContributor.name == "Identity Artist")
        #expect(credit.name == "Identity Artist")
        #expect(credit.contributor == createdContributor.id)
        #expect(credit.role == "dj")
        try createdContributor.validateReferences()
        try performance.validateReferences()
    }

    @Test
    func reusesContributorWithMatchingIdentityDid() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let did = try #require(DID("did:plc:knownartist"))
        let knownContributorID = try #require(Contributor.ID(
            "at://did:plc:organizer/events.openmusic.contributor/3mrdbziccpca6"
        ))
        var knownContributor = try Contributor(
            id: knownContributorID,
            event: fixture.event.id,
            name: "Known Artist",
            createdAt: "2026-09-01T12:00:00Z"
        )
        knownContributor.subject = did
        let savedContributor = knownContributor
        try await database.write { db in
            try Contributor.insert { savedContributor }.execute(db)
        }
        let identity = ActorIdentity(
            did: did,
            handle: Atmosphere.Account.Handle(rawValue: "knownartist.bsky.social"),
            displayName: "Known Artist Profile",
            source: .typeahead
        )
        let scheduleDate = fixture.schedule.date
        let store = try makeCanonicalPerformanceStore(
            database: database,
            fixture: fixture
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
                contributors: try Contributor.all.fetchAll(db),
                item: try #require(ProgramItem.all.fetchAll(db).first)
            )
        }
        #expect(rows.contributors.count == 2)
        #expect(rows.item.credits?.first?.contributor == knownContributorID)
        #expect(rows.item.credits?.first?.name == "Known Artist Profile")
        try rows.item.validateReferences()
    }

    @Test
    func editsPerformanceRowWithoutDroppingContributors() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let performanceID = try #require(ProgramItem.ID(
            "at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcae"
        ))
        let performance = try seedCanonicalPerformance(
            database: database, fixture: fixture, id: performanceID,
            schedule: fixture.schedule, stage: fixture.stage,
            title: "Opening Set", description: "Original description.",
            startTime: try #require(fixture.schedule.date.at(hour: 20, in: timeZone)),
            endTime: try #require(fixture.schedule.date.at(hour: 21, in: timeZone)),
            credits: [ProgramItem.Credit(
                name: fixture.contributor.name,
                contributor: fixture.contributor.id
            )]
        )
        let updatedStartTime = try #require(fixture.schedule.date.at(hour: 21, in: timeZone))
        let updatedEndTime = try #require(fixture.schedule.date.at(hour: 22, in: timeZone))
        let store = try makeCanonicalPerformanceStore(
            database: database,
            fixture: fixture,
            performance: performance
        ) {
            #expect($0.title == "Opening Set")
            #expect($0.description == "Original description.")
            #expect($0.selectedStageID == fixture.stage.id)
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
                performances: try ProgramItem.all.fetchAll(db),
                contributors: try Contributor.all.fetchAll(db)
            )
        }
        let saved = try #require(rows.performances.first)
        #expect(rows.performances.count == 1)
        #expect(saved.id == performance.id)
        #expect(saved.title == "Updated Set")
        #expect(saved.description == "Updated description.")
        #expect(saved.startDate == updatedStartTime)
        #expect(saved.endDate == updatedEndTime)
        #expect(rows.contributors.count == 1)
        #expect(saved.credits?.count == 1)
        #expect(saved.credits?.first?.contributor == fixture.contributor.id)
        try saved.validateReferences()
    }

    @Test
    func movesCrossMidnightPerformanceToAnotherScheduleWithoutDroppingFormContent() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let targetContext = try seedAdditionalCanonicalScheduleContext(
            database: database, fixture: fixture
        )
        let performanceID = try #require(ProgramItem.ID(
            "at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcae"
        ))
        let originalStartTime = try #require(
            fixture.schedule.date.at(hour: 23, minute: 30, in: timeZone)
        )
        let originalEndTime = originalStartTime.addingTimeInterval(90 * 60)
        let performance = try seedCanonicalPerformance(
            database: database, fixture: fixture, id: performanceID,
            schedule: fixture.schedule, stage: fixture.stage,
            title: "Overnight Set", description: "Original overnight description.",
            startTime: originalStartTime, endTime: originalEndTime,
            credits: [ProgramItem.Credit(
                name: fixture.contributor.name,
                contributor: fixture.contributor.id
            )]
        )
        let store = try makeCanonicalPerformanceStore(
            database: database,
            fixture: fixture,
            schedules: [targetContext.schedule, fixture.schedule],
            performance: performance
        ) { state in
            #expect(state.title == "Overnight Set")
            #expect(state.description == "Original overnight description.")
            #expect(state.selectedStageID == fixture.stage.id)
            #expect(
                state.contributions.map(\.selection)
                    == [.existingContributor(fixture.contributor.id)]
            )
        }
        let formID = store.state.id
        let expectedStartTime = try #require(
            targetContext.schedule.date.at(hour: 23, minute: 30, in: timeZone)
        )
        let expectedEndTime = expectedStartTime.addingTimeInterval(90 * 60)

        store.modify {
            $0.selectedScheduleID = targetContext.schedule.id
        }

        expectNoDifference(store.state.id, formID)
        expectNoDifference(
            store.state.selectedScheduleID,
            targetContext.schedule.id
        )
        expectNoDifference(store.state.startTimeSelection, expectedStartTime)
        expectNoDifference(store.state.endTimeSelection, expectedEndTime)
        expectNoDifference(store.state.timeRangeSelection.duration, 90 * 60)
        expectNoDifference(store.state.selectedStageID, fixture.stage.id)
        expectNoDifference(store.state.title, "Overnight Set")
        expectNoDifference(store.state.description, "Original overnight description.")
        expectNoDifference(
            store.state.contributions.map(\.selection),
            [.existingContributor(fixture.contributor.id)]
        )

        await store.send(.saveButtonTapped)?.value

        #expect(store.state.isSaving == false)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        let rows = try await database.read { db in
            (
                performance: try #require(
                    try ProgramItem
                        .where { $0.id.eq(performanceID) }
                        .fetchOne(db)
                ),
                contributors: try Contributor.all.fetchAll(db)
            )
        }
        expectNoDifference(
            rows.performance.schedule,
            targetContext.schedule.id
        )
        expectNoDifference(rows.performance.startDate, expectedStartTime)
        expectNoDifference(rows.performance.endDate, expectedEndTime)
        expectNoDifference(rows.performance.eventPlace, fixture.stage.id)
        expectNoDifference(rows.performance.title, "Overnight Set")
        expectNoDifference(
            rows.performance.description,
            "Original overnight description."
        )
        expectNoDifference(rows.contributors.count, 1)
        expectNoDifference(
            rows.performance.credits?.first?.contributor,
            fixture.contributor.id
        )
        try rows.performance.validateReferences()
    }

    @Test
    func editsPerformanceContributorRelationship() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let createdAt = try Date("2026-09-02T18:00:00Z", strategy: .iso8601)
        let performanceID = try await database.write { db in
            try ProgramItemRecordEditing.create(
                eventID: fixture.event.id,
                fields: .init(
                    program: fixture.program.id,
                    title: "Opening Set",
                    schedule: fixture.schedule.id,
                    eventPlace: fixture.stage.id,
                    credits: [ProgramItem.Credit(
                        name: fixture.contributor.name,
                        contributor: fixture.contributor.id
                    )]
                ),
                createdAt: createdAt,
                in: db
            )
        }
        let performance = try await database.read { db in
            try #require(try ProgramItem.find(performanceID).fetchOne(db))
        }
        let artistDID = try #require(DID("did:plc:artist456"))
        let store = try makeCanonicalPerformanceStore(
            database: database,
            fixture: fixture,
            performance: performance
        ) {
            #expect(
                $0.contributions.map(\.selection)
                    == [.existingContributor(fixture.contributor.id)]
            )
            let contributionID = try #require($0.contributions.first?.id)
            $0.updateContributionSelection(
                id: contributionID,
                selection: .identityOnly(actor: artistDID, displayTitle: "Artist")
            )
            $0.setContributionRole(id: contributionID, roleSelection: .dj)
        }

        await store.send(.saveButtonTapped)?.value

        let rows = try await database.read { db in
            (
                performance: try #require(try ProgramItem.find(performanceID).fetchOne(db)),
                contributors: try Contributor.all.fetchAll(db)
            )
        }
        let contributor = try #require(rows.contributors.first { $0.subject == artistDID })
        let credit = try #require(rows.performance.credits?.first)
        #expect(rows.performance.id == performanceID)
        #expect(rows.performance.credits?.count == 1)
        #expect(rows.performance.createdAt == performance.createdAt)
        #expect(rows.contributors.count == 2)
        #expect(credit.name == "Artist")
        #expect(credit.contributor == contributor.id)
        #expect(credit.role == "dj")
        try rows.performance.validateReferences()
    }

    @Test
    func loadsCommonAndCustomRelationshipRoles() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let performanceID = try #require(ProgramItem.ID(
            "at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcae"
        ))
        var performance = try seedCanonicalPerformance(
            database: database, fixture: fixture, id: performanceID,
            schedule: fixture.schedule, stage: fixture.stage,
            title: "Opening Set",
            startTime: try #require(fixture.schedule.date.at(hour: 20, in: timeZone)),
            endTime: try #require(fixture.schedule.date.at(hour: 21, in: timeZone)),
            credits: [ProgramItem.Credit(
                name: fixture.contributor.name,
                contributor: fixture.contributor.id,
                role: "dj"
            )]
        )

        _ = try makeCanonicalPerformanceStore(
            database: database,
            fixture: fixture,
            performance: performance
        ) {
            let contribution = try #require($0.contributions.first)
            #expect(contribution.roleSelection == .dj)
            #expect(contribution.customRelationshipRole == "")
        }

        performance.credits?[0].role = "lightingDesigner"
        let updatedPerformance = performance
        try await database.write { db in
            try ProgramItem.upsert { updatedPerformance }.execute(db)
        }

        _ = try makeCanonicalPerformanceStore(
            database: database,
            fixture: fixture,
            performance: updatedPerformance
        ) {
            let contribution = try #require($0.contributions.first)
            #expect(contribution.roleSelection == .custom)
            #expect(contribution.customRelationshipRole == "lightingDesigner")
        }
    }

    @Test
    func contributorRelationshipPickerSearchesLocalFirstAndLooksUpExactIdentityOnSubmit() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let contributors = try await database.read { db in
            try ContributorProfile
                .all(eventID: fixture.event.id, hydration: .none)
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
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let contributors = try await database.read { db in
            try ContributorProfile
                .all(eventID: fixture.event.id, hydration: .none)
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
        let selectedIdentity = ContributorRelationshipPicker.SelectedActorIdentity(identity)
        let store = TestStore(initialState: initialState) {
            ContributorRelationshipPicker()
        }

        store.send(.existingContributorTapped(fixture.contributor.id)) {
            $0.selection = .existingContributor(fixture.contributor.id)
        }
        store.send(.createContributorButtonTapped) {
            $0.selection = .newContributor(name: "Guest Artist")
        }
        store.send(.performanceDisplayNameButtonTapped) {
            $0.selection = .performanceDisplayName(name: "Guest Artist")
        }
        store.send(.identityLinkOnlyButtonTapped(identity)) {
            $0.selection = .identityOnly(
                actor: identity.did,
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
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let contributors = try await database.read { db in
            try ContributorProfile
                .all(eventID: fixture.event.id, hydration: .none)
                .fetchAll(db)
        }
        var initialState = ProgramItemForm.State(
            eventID: fixture.event.id,
            schedule: fixture.schedule,
            schedules: [fixture.schedule],
            programs: [fixture.program],
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
                ProgramItemForm()
            }
        }

        store.send(
            .contributorRelationshipPicker(
                .existingContributorTapped(fixture.contributor.id)
            )
        ) {
            $0.contributions = [
                ProgramItemForm.State.Contribution(
                    id: 0,
                    selection: .existingContributor(fixture.contributor.id)
                )
            ]
            $0.nextContributionID = 1
            $0.contributorRelationshipPicker.searchQuery = ""
        }

        #expect(store.state.contributions.first?.roleSelection == nil)
    }

    @Test
    func performanceTitleTracksPrimaryContributorNamesUntilEdited() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let contributors = try await database.read { db in
            try ContributorProfile
                .all(eventID: fixture.event.id, hydration: .none)
                .fetchAll(db)
        }
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(
                initialState: ProgramItemForm.State(
                    eventID: fixture.event.id,
                    schedule: fixture.schedule,
                    schedules: [fixture.schedule],
                    programs: [fixture.program],
                    stages: [fixture.stage],
                    timeZone: timeZone,
                    contributors: contributors
                )
            ) {
                ProgramItemForm()
            }
        }

        store.send(
            .contributorRelationshipPicker(
                .existingContributorTapped(fixture.contributor.id)
            )
        ) {
            $0.contributions = [
                ProgramItemForm.State.Contribution(
                    id: 0,
                    selection: .existingContributor(fixture.contributor.id)
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
                ProgramItemForm.State.Contribution(
                    id: 0,
                    selection: .existingContributor(fixture.contributor.id)
                ),
                ProgramItemForm.State.Contribution(
                    id: 1,
                    selection: .performanceDisplayName(name: "Guest Artist"),
                    billing: .known(.supporting)
                ),
            ]
            $0.contributorRelationshipPicker.searchQuery = ""
            $0.nextContributionID = 2
        }

        store.send(.contributionBillingButtonTapped(1, .known(.primary))) {
            $0.contributions[1].billing = .known(.primary)
            $0.generatedTitle = "Artist One b2b Guest Artist"
            $0.title = "Artist One b2b Guest Artist"
        }
        store.send(.titleTextChanged("Custom Set")) {
            $0.title = "Custom Set"
            $0.titleIsGenerated = false
        }
        store.send(.contributionBillingButtonTapped(1, .known(.supporting))) {
            $0.contributions[1].billing = .known(.supporting)
            $0.generatedTitle = "Artist One"
        }
        #expect(store.state.title == "Custom Set")
    }

    @Test
    func eventViewerPerformanceEditIntentPresentsEditor() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let performanceID = try #require(ProgramItem.ID(
            "at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcae"
        ))
        let performance = try seedCanonicalPerformance(
            database: database, fixture: fixture, id: performanceID,
            schedule: fixture.schedule, stage: fixture.stage,
            title: "Opening Set", description: "Original description.",
            startTime: try #require(fixture.schedule.date.at(hour: 20, in: timeZone)),
            endTime: try #require(fixture.schedule.date.at(hour: 21, in: timeZone))
        )
        var state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = fixture.event.id
            $0.defaultEventTimeZone = SharedReader(value: timeZone)
        } operation: {
            EventDetail.State(eventID: fixture.event.id)
        }
        state.selectedFeature = .contributors

        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = fixture.event.id
            $0.defaultEventTimeZone = SharedReader(value: timeZone)
        } operation: {
            state.handleEditingIntent(
                .editPerformance(
                    eventID: fixture.event.id,
                    performanceID: performance.id
                )
            )
        }

        let editPerformance = try #require(state.destination?.performanceForm)
        #expect(state.selectedFeature == .contributors)
        #expect(editPerformance.performanceID == performance.id)
        #expect(editPerformance.title == "Opening Set")
        #expect(editPerformance.description == "Original description.")
        #expect(editPerformance.startTimeSelection == performance.startDate)
        #expect(editPerformance.endTimeSelection == performance.endDate)
        #expect(editPerformance.selectedStageID == fixture.stage.id)
    }

    @Test
    func performanceDetailEditActionEmitsEditorRequest() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let performanceID = try #require(ProgramItem.ID(
            "at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcae"
        ))
        let performance = try seedCanonicalPerformance(
            database: database, fixture: fixture, id: performanceID,
            schedule: fixture.schedule, stage: fixture.stage,
            title: "Opening Set",
            startTime: try #require(fixture.schedule.date.at(hour: 20, in: timeZone)),
            endTime: try #require(fixture.schedule.date.at(hour: 21, in: timeZone))
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventTimeZone = SharedReader(value: timeZone)
        } operation: {
            TestStore(
                initialState: ProgramItemDetail.State(
                    performanceID: performance.id,
                    eventID: fixture.event.id
                )
            ) {
                ProgramItemDetail()
            }
        }

        let editTask = store.send(.editButtonTapped)
        await store.receive(
            key: EventEditingRequested.self,
            value: .equals(
                .editPerformance(
                    eventID: fixture.event.id,
                    performanceID: performance.id
                )
            ),
            timeout: .seconds(1)
        )
        await editTask?.value
    }

    @Test
    func performanceDetailDeleteActionRequestsScheduleConfirmation() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let performanceID = try #require(ProgramItem.ID(
            "at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcae"
        ))
        let performance = try seedCanonicalPerformance(
            database: database, fixture: fixture, id: performanceID,
            schedule: fixture.schedule, stage: fixture.stage,
            title: "Opening Set",
            startTime: try #require(fixture.schedule.date.at(hour: 20, in: timeZone)),
            endTime: try #require(fixture.schedule.date.at(hour: 21, in: timeZone))
        )
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventTimeZone = SharedReader(value: timeZone)
        } operation: {
            TestStore(
                initialState: ProgramItemDetail.State(
                    performanceID: performance.id,
                    eventID: fixture.event.id
                )
            ) {
                ProgramItemDetail()
            }
        }

        let deleteTask = store.send(.deleteButtonTapped)
        await store.receive(
            key: SchedulePerformanceDeleteRequested.self,
            value: .equals(performance.id),
            timeout: .seconds(1)
        )
        await deleteTask?.value
    }

    @Test
    func scheduleViewerDeletesPerformanceAfterConfirmation() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let timeZone = fixture.event.timeZone
        let performanceID = try #require(ProgramItem.ID(
            "at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcae"
        ))
        let performance = try seedCanonicalPerformance(
            database: database, fixture: fixture, id: performanceID,
            schedule: fixture.schedule, stage: fixture.stage,
            title: "Opening Set",
            startTime: try #require(fixture.schedule.date.at(hour: 20, in: timeZone)),
            endTime: try #require(fixture.schedule.date.at(hour: 21, in: timeZone)),
            credits: [ProgramItem.Credit(
                name: fixture.contributor.name,
                contributor: fixture.contributor.id
            )]
        )
        await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventTimeZone = SharedReader(value: timeZone)
            $0.uuid = .incrementing
        } operation: {
            let store = Store(initialState: ScheduleList.State(eventID: fixture.event.id)) {
                ScheduleList()
            }
            let scheduleStore: StoreOf<ScheduleSingleStageAtOnce> = store.spawn(\.singleStageAtOnce)

            await scheduleStore.send(
                .deletePerformanceButtonTapped(performance.id)
            )?.value

            #expect(
                store.destination?.deletePerformanceConfirmation?.performanceID
                    == performance.id
            )

            await store.send(
                .destination(
                    .deletePerformanceConfirmation(
                        .deleteButtonTapped(performance.id)
                    )
                )
            )?.value
        }

        let rows = try await database.read { db in
            (
                performances: try ProgramItem.all.fetchAll(db),
                contributors: try Contributor.all.fetchAll(db)
            )
        }
        #expect(rows.performances.isEmpty)
        #expect(rows.contributors.map(\.id) == [fixture.contributor.id])
    }

    @Test
    func programManagementEditsCanonicalProgramAndOrderedPlaces() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let secondPlace = try EventPlace(
            id: #require(EventPlace.ID(
                "at://did:plc:organizer/events.openmusic.eventPlace/3mrdbziccpcae"
            )),
            event: fixture.event.id,
            name: "Meadow",
            createdAt: "2026-09-01T12:00:00Z"
        )
        try await database.write { try EventPlace.insert { secondPlace }.execute($0) }

        await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 0)
        } operation: {
            let manager = Store(initialState: ProgramList.State(eventID: fixture.event.id)) {
                ProgramList()
            }
            #expect(manager.state.orderedPrograms.map(\.id) == [fixture.program.id])
            await manager.send(.editButtonTapped(fixture.program.id))?.value
            #expect(manager.destination?.editor?.programID == fixture.program.id)

            let editor = TestStore(initialState: ProgramForm.State(
                eventID: fixture.event.id,
                program: fixture.program,
                places: [fixture.stage, secondPlace]
            )) { ProgramForm() }
            await editor.send(.addPlaceButtonTapped(secondPlace.id))?.value
            await editor.send(.movePlaceButtonTapped(secondPlace.id, -1))?.value
            editor.modify {
                $0.title = "Main Music"
                $0.description = "The main event program"
                $0.iconName = "calendar"
            }
            #expect(editor.selectedPlaceIDs == [secondPlace.id, fixture.stage.id])
            await editor.send(.saveButtonTapped)?.value
        }

        let saved = try await database.read { db in
            (
                program: try #require(try Program.find(fixture.program.id).fetchOne(db)),
                event: try #require(try Event.find(fixture.event.id).fetchOne(db))
            )
        }
        #expect(saved.program.title == "Main Music")
        #expect(saved.program.description == "The main event program")
        #expect(saved.program.icon == .calendar)
        #expect(saved.program.eventPlaces == [secondPlace.id, fixture.stage.id])
        #expect(saved.event.programs == [fixture.program.id])

        let secondProgramID = try await database.write { db in
            try ProgramRecordEditing.create(
                eventID: fixture.event.id,
                title: "Workshops",
                eventPlaces: [secondPlace.id],
                createdAt: Date(timeIntervalSince1970: 1_780_000_000),
                in: db
            )
        }
        await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            let manager = Store(initialState: ProgramList.State(eventID: fixture.event.id)) {
                ProgramList()
            }
            #expect(manager.state.orderedPrograms.map(\.id) == [fixture.program.id, secondProgramID])
            await manager.send(.moveButtonTapped(secondProgramID, -1))?.value
            #expect(manager.state.orderedPrograms.map(\.id) == [secondProgramID, fixture.program.id])
        }
        #expect(try await database.read { try Event.find(fixture.event.id).fetchOne($0)?.programs }
            == [secondProgramID, fixture.program.id])
    }

    @Test
    func programManagerDeletesAProgramFromItsRowActions() async throws {
        let database = try canonicalPerformanceDatabase()
        let fixture = try seedCanonicalPerformanceFixture(database: database)
        let workshopsID = try await database.write { db in
            try ProgramRecordEditing.create(
                eventID: fixture.event.id,
                title: "Workshops",
                eventPlaces: [],
                createdAt: Date(timeIntervalSince1970: 1_780_000_000),
                in: db
            )
        }

        await withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            let manager = Store(initialState: ProgramList.State(eventID: fixture.event.id)) {
                ProgramList()
            }

            // Deleting Workshops removes both the record and its entry in the Event's program order.
            #expect(manager.state.orderedPrograms.map(\.id) == [fixture.program.id, workshopsID])
            await manager.send(.deleteButtonTapped(workshopsID))?.value
            #expect(manager.state.orderedPrograms.map(\.id) == [fixture.program.id])
        }

        let rows = try await database.read { db in
            (
                workshops: try Program.find(workshopsID).fetchOne(db),
                event: try Event.find(fixture.event.id).fetchOne(db)
            )
        }
        #expect(rows.workshops == nil)
        #expect(rows.event?.programs == [fixture.program.id])
    }

    private func canonicalPerformanceDatabase() throws -> DatabaseQueue {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }

    private func seedCanonicalPerformanceFixture(
        database: DatabaseQueue
    ) throws -> CanonicalScheduleAuthoringFixture {
        let organizer = "did:plc:organizer"
        let eventID = try #require(Event.ID(
            "at://\(organizer)/events.openmusic.event/3mrdbziccpcah"
        ))
        let programID = try #require(Program.ID(
            "at://\(organizer)/events.openmusic.program/3mrdbziccpcai"
        ))
        let scheduleID = try #require(Schedule.ID(
            "at://\(organizer)/events.openmusic.schedule/3mrdbziccpcaj"
        ))
        let stageID = try #require(EventPlace.ID(
            "at://\(organizer)/events.openmusic.eventPlace/3mrdbziccpcak"
        ))
        let contributorID = try #require(Contributor.ID(
            "at://\(organizer)/events.openmusic.contributor/3mrdbziccpcam"
        ))
        let createdAt = ATProto.DateTime(rawValue: "2026-09-01T12:00:00Z")
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let event = try Event(
            id: eventID,
            name: "Wicked Woods 2026",
            createdAt: createdAt,
            timeZone: timeZone,
            programs: [programID],
            schedules: [scheduleID]
        )
        let program = try Program(
            id: programID,
            event: eventID,
            title: "Music",
            createdAt: createdAt,
            eventPlaces: [stageID]
        )
        let schedule = try Schedule(
            id: scheduleID,
            event: eventID,
            date: #require(LocalDate("2026-08-01")),
            createdAt: createdAt
        )
        var stage = try EventPlace(
            id: stageID,
            event: eventID,
            name: "Main Stage",
            createdAt: createdAt
        )
        stage.kind = .known(.stage(EventPlace.Kind.Stage()))
        let contributor = try Contributor(
            id: contributorID,
            event: eventID,
            name: "Artist One",
            createdAt: createdAt
        )
        try database.write { db in
            try Event.insert { event }.execute(db)
            try Program.insert { program }.execute(db)
            try Schedule.insert { schedule }.execute(db)
            try EventPlace.insert { stage }.execute(db)
            try Contributor.insert { contributor }.execute(db)
        }
        return CanonicalScheduleAuthoringFixture(
            event: event,
            program: program,
            schedule: schedule,
            stage: stage,
            contributor: contributor
        )
    }

    private func seedAdditionalCanonicalScheduleContext(
        database: DatabaseQueue,
        fixture: CanonicalScheduleAuthoringFixture
    ) throws -> (schedule: Schedule, stage: EventPlace) {
        let scheduleID = try #require(Schedule.ID(
            "at://did:plc:organizer/events.openmusic.schedule/3mrdbziccpcan"
        ))
        let stageID = try #require(EventPlace.ID(
            "at://did:plc:organizer/events.openmusic.eventPlace/3mrdbziccpcae"
        ))
        let schedule = try Schedule(
            id: scheduleID,
            event: fixture.event.id,
            date: #require(LocalDate("2026-07-31")),
            createdAt: "2026-09-01T12:00:00Z"
        )
        var stage = try EventPlace(
            id: stageID,
            event: fixture.event.id,
            name: "Meadow",
            createdAt: "2026-09-01T12:00:00Z"
        )
        stage.kind = .known(.stage(EventPlace.Kind.Stage()))
        let selectedStage = stage
        try database.write { db in
            try Schedule.insert { schedule }.execute(db)
            try EventPlace.insert { selectedStage }.execute(db)
            var event = try #require(try Event.find(fixture.event.id).fetchOne(db))
            event.schedules = [scheduleID, fixture.schedule.id]
            let updatedEvent = event
            try Event.upsert { updatedEvent }.execute(db)
            var program = try #require(try Program.find(fixture.program.id).fetchOne(db))
            program.eventPlaces = [stageID, fixture.stage.id]
            let updatedProgram = program
            try Program.upsert { updatedProgram }.execute(db)
        }
        return (schedule, selectedStage)
    }

    @discardableResult
    private func seedCanonicalPerformance(
        database: DatabaseQueue,
        fixture: CanonicalScheduleAuthoringFixture,
        id: ProgramItem.ID,
        schedule: Schedule,
        stage: EventPlace,
        title: String,
        description: String? = nil,
        startTime: Date,
        endTime: Date,
        credits: [ProgramItem.Credit]? = nil
    ) throws -> ProgramItem {
        var item = try ProgramItem(
            id: id,
            event: fixture.event.id,
            program: fixture.program.id,
            title: title,
            createdAt: "2026-09-01T12:00:00Z"
        )
        item.schedule = schedule.id
        item.eventPlace = stage.id
        item.description = description
        item.startsAt = ATProto.DateTime(rawValue: ISO8601DateFormatter().string(from: startTime))
        item.endsAt = ATProto.DateTime(rawValue: ISO8601DateFormatter().string(from: endTime))
        item.credits = credits
        let savedItem = item
        try database.write { db in
            try ProgramItem.insert { savedItem }.execute(db)
        }
        return savedItem
    }

    private func addCanonicalPerformanceEditorState(
        database: DatabaseQueue,
        fixture: CanonicalScheduleAuthoringFixture,
        scheduleID: Schedule.ID?,
        stageID: EventPlace.ID?
    ) throws -> ProgramItemForm.State {
        let eventID = fixture.event.id
        let timeZone = fixture.event.timeZone
        var state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.defaultEventTimeZone = SharedReader(value: timeZone)
            $0.date.now = Date(timeIntervalSince1970: 1_780_000_000)
        } operation: {
            EventDetail.State(eventID: eventID)
        }
        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.defaultEventID = eventID
            $0.defaultEventTimeZone = SharedReader(value: timeZone)
            $0.date.now = Date(timeIntervalSince1970: 1_780_000_000)
        } operation: {
            state.handleEditingIntent(
                .addPerformance(
                    eventID: eventID,
                    scheduleID: scheduleID,
                    programID: fixture.program.id,
                    stageID: stageID
                )
            )
        }
        return try #require(state.destination?.performanceForm)
    }

    private func makeCanonicalPerformanceStore(
        database: DatabaseQueue,
        fixture: CanonicalScheduleAuthoringFixture,
        schedules: [Schedule]? = nil,
        performance: ProgramItem? = nil,
        update: (inout ProgramItemForm.State) throws -> Void
    ) throws -> TestStore<ProgramItemForm> {
        let now = try Date("2026-09-02T18:00:00Z", strategy: .iso8601)
        return try withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.date.now = now
            $0.uuid = .incrementing
        } operation: {
            let contributors = try database.read { db in
                try ContributorProfile
                    .all(eventID: fixture.event.id, hydration: .none)
                    .fetchAll(db)
            }
            var state: ProgramItemForm.State
            if let performance {
                state = ProgramItemForm.State(
                    eventID: fixture.event.id,
                    schedule: fixture.schedule,
                    schedules: schedules ?? [fixture.schedule],
                    programs: [fixture.program],
                    stages: [fixture.stage],
                    timeZone: fixture.event.timeZone,
                    performance: performance,
                    contributors: contributors
                )
            } else {
                state = ProgramItemForm.State(
                    eventID: fixture.event.id,
                    schedule: fixture.schedule,
                    schedules: schedules ?? [fixture.schedule],
                    programs: [fixture.program],
                    stages: [fixture.stage],
                    timeZone: fixture.event.timeZone,
                    selectedStageID: fixture.stage.id,
                    contributors: contributors
                )
            }
            try update(&state)
            return TestStore(initialState: state) { ProgramItemForm() }
        }
    }

}

private struct CanonicalScheduleAuthoringFixture {
    var event: Event
    var program: Program
    var schedule: Schedule
    var stage: EventPlace
    var contributor: Contributor
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
