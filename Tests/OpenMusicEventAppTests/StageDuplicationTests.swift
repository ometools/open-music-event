import ATProto
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import OpenMusicEventDatabase
import SQLiteData
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventLexicon

@MainActor
@Suite(.tcaExhaustivity(.off))
struct StageDuplicationTests {
    @Test
    func emitsCopyStagesFromOtherEventRequestWhenCurrentEventIsEmpty() async throws {
        let database = try makeDatabase()
        let fixture = try seedEventSet(database: database)
        let store = makeStagesViewerStore(
            eventID: fixture.currentEventID,
            database: database
        )

        let copyTask = store.send(.fromOtherEventButtonTapped)
        await store.receive(
            key: EventEditingRequested.self,
            value: .equals(.copyStagesFromEvent(fixture.currentEventID)),
            timeout: .seconds(1)
        )
        await copyTask?.value
    }

    @Test
    func emitsCopyStagesFromOtherEventRequestWhenCurrentEventHasOnlyAnUnstagedPlace() async throws {
        let database = try makeDatabase()
        let fixture = try seedEventSet(database: database)
        try await database.write { db in
            try insertNonStagePlace(
                db,
                id: fixture.destinationNonStageID,
                eventID: fixture.currentEventID,
                name: "North Gate"
            )
        }
        let store = makeStagesViewerStore(
            eventID: fixture.currentEventID,
            database: database
        )

        let copyTask = store.send(.fromOtherEventButtonTapped)
        await store.receive(
            key: EventEditingRequested.self,
            value: .equals(.copyStagesFromEvent(fixture.currentEventID)),
            timeout: .seconds(1)
        )
        await copyTask?.value
    }

    @Test
    func copiesSelectedStagesFromOtherEvent() async throws {
        let database = try makeDatabase()
        let fixture = try seedEventSet(database: database)
        let posterURL = try #require(URL(string: "https://example.com/main-stage.png"))
        let logoURL = try #require(URL(string: "https://example.com/main-stage-logo.png"))
        let lineupID = try #require(Contributor.ID(
            "at://did:plc:organizer/events.openmusic.contributor/3mrdbziccpcam"
        ))
        let media: [Open<OME.Media>] = [
            .known(.image(OME.Image(source: .known(.url(posterURL)), role: .known(.poster)))),
            .known(.image(OME.Image(source: .known(.url(logoURL)), role: .known(.logo)))),
        ]
        try await database.write { db in
            try insertStage(
                db,
                id: fixture.sourceMainStageID,
                eventID: fixture.sourceEventID,
                name: "Main Stage",
                color: try #require(OME.Color(rawValue: 0x00bbcc)),
                category: "music",
                sortIndex: 1,
                icon: .gridOfSquares,
                shortLabel: "Main",
                lineup: [lineupID],
                media: media
            )
            try insertStage(
                db,
                id: fixture.sourceWoodsStageID,
                eventID: fixture.sourceEventID,
                name: "Woods",
                sortIndex: 2
            )
        }
        let store = makeCopyStagesStore(
            eventID: fixture.currentEventID,
            database: database
        )

        await store.send(.task)?.value

        expectNoDifference(store.state.sourceEvents.map(\.id), [fixture.sourceEventID])
        expectNoDifference(
            store.state.sourceStages.map(\.id),
            [fixture.sourceMainStageID, fixture.sourceWoodsStageID]
        )
        expectNoDifference(
            store.state.selectedStageIDs,
            Set([fixture.sourceMainStageID, fixture.sourceWoodsStageID])
        )

        store.send(.stageButtonTapped(fixture.sourceWoodsStageID)) {
            $0.selectedStageIDs.remove(fixture.sourceWoodsStageID)
        }
        await store.send(.copyButtonTapped)?.value

        #expect(store.state.errorMessage == nil)
        #expect(store.state.isCopying == false)
        #expect(store.isPresented == false)

        let stages = try await database.read { db in
            try CopyStagesFromEvent.sourceStages(eventID: fixture.currentEventID, in: db)
        }
        expectNoDifference(stages.map(\.name), ["Main Stage"])
        let copied = try #require(stages.first)
        #expect(copied.id != fixture.sourceMainStageID)
        #expect(copied.event == fixture.currentEventID)
        #expect(copied.stageUse?.color == OME.Color(rawValue: 0x00bbcc))
        #expect(copied.stageUse?.category == "music")
        #expect(copied.stageUse?.sortIndex == 1)
        #expect(copied.stageUse?.icon == .gridOfSquares)
        #expect(copied.stageUse?.shortLabel == "Main")
        #expect(copied.stageUse?.lineup == nil)
        expectNoDifference(copied.media, media)
        try copied.validateReferences()
    }

    @Test
    func copiesSelectedStagesFromOtherEventAlongsideAnUnstagedPlace() async throws {
        let database = try makeDatabase()
        let fixture = try seedEventSet(database: database)
        try await database.write { db in
            try insertNonStagePlace(
                db,
                id: fixture.destinationNonStageID,
                eventID: fixture.currentEventID,
                name: "North Gate"
            )
            try insertStage(
                db, id: fixture.sourceMainStageID,
                eventID: fixture.sourceEventID, name: "Main Stage", sortIndex: 1
            )
            try insertStage(
                db, id: fixture.sourceWoodsStageID,
                eventID: fixture.sourceEventID, name: "Woods", sortIndex: 2
            )
        }
        let store = makeCopyStagesStore(
            eventID: fixture.currentEventID,
            database: database
        )

        await store.send(.task)?.value
        await store.send(.copyButtonTapped)?.value

        #expect(store.state.errorMessage == nil)
        #expect(store.state.isCopying == false)
        #expect(store.isPresented == false)

        let rows = try await database.read { db in
            (
                places: try StagesViewer.stagesQuery(eventID: fixture.currentEventID).fetchAll(db),
                stages: try CopyStagesFromEvent.sourceStages(
                    eventID: fixture.currentEventID, in: db
                )
            )
        }
        expectNoDifference(rows.stages.map(\.name), ["Main Stage", "Woods"])
        #expect(rows.places.count == 3)
        #expect(rows.places.contains { $0.id == fixture.destinationNonStageID })
    }

    @Test
    func copyStagesListsOnlyOtherEventsWithStages() async throws {
        let database = try makeDatabase()
        let fixture = try seedEventSet(database: database)
        try await database.write { db in
            try insertStage(
                db, id: fixture.sourceMainStageID,
                eventID: fixture.sourceEventID, name: "Main Stage"
            )
        }
        let sourceEvents = try await database.read { db in
            try CopyStagesFromEvent.sourceEventOptions(
                for: fixture.currentEventID,
                in: db
            )
        }

        expectNoDifference(sourceEvents.map(\.id), [fixture.sourceEventID])
        expectNoDifference(sourceEvents.map(\.name), ["Wicked Woods 2025"])
        expectNoDifference(sourceEvents.map(\.stageCount), [1])
    }

    @Test
    func copyStagesDoesNotRunWhenCurrentEventAlreadyHasStages() async throws {
        let database = try makeDatabase()
        let fixture = try seedEventSet(database: database)
        try await database.write { db in
            try insertStage(
                db, id: fixture.destinationExistingStageID,
                eventID: fixture.currentEventID, name: "Existing"
            )
        }
        let store = makeStagesViewerStore(
            eventID: fixture.currentEventID,
            database: database
        )

        store.send(.fromOtherEventButtonTapped) {
            $0.errorMessage = "This event already has stages."
        }

        let stages = try await database.read { db in
            try CopyStagesFromEvent.sourceStages(eventID: fixture.currentEventID, in: db)
        }
        expectNoDifference(stages.map(\.id), [fixture.destinationExistingStageID])
    }

    private func makeDatabase() throws -> DatabaseQueue {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }

    private func makeCopyStagesStore(
        eventID: Event.ID,
        database: DatabaseQueue
    ) -> TestStore<CopyStagesFromEvent> {
        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 1_779_800_000)
        } operation: {
            TestStore(initialState: CopyStagesFromEvent.State(eventID: eventID)) {
                CopyStagesFromEvent()
            }
        }
    }

    private func makeStagesViewerStore(
        eventID: Event.ID,
        database: DatabaseQueue
    ) -> TestStore<StagesViewer> {
        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: StagesViewer.State(eventID: eventID)) {
                StagesViewer()
            }
        }
    }

    private func seedEventSet(database: DatabaseQueue) throws -> EventSet {
        let currentEventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
        ))
        let sourceEventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcai"
        ))
        let emptySourceEventID = try #require(Event.ID(
            "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcaj"
        ))
        let sourceMainStageID = try #require(EventPlace.ID(
            "at://did:plc:organizer/events.openmusic.eventPlace/3mrdbziccpcak"
        ))
        let sourceWoodsStageID = try #require(EventPlace.ID(
            "at://did:plc:organizer/events.openmusic.eventPlace/3mrdbziccpcam"
        ))
        let destinationNonStageID = try #require(EventPlace.ID(
            "at://did:plc:organizer/events.openmusic.eventPlace/3mrdbziccpcan"
        ))
        let destinationExistingStageID = try #require(EventPlace.ID(
            "at://did:plc:organizer/events.openmusic.eventPlace/3mrdbziccpcap"
        ))
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let current = try Event(
            id: currentEventID,
            name: "Wicked Woods 2026 Pre-Party Kelowna",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: timeZone
        )
        let source = try Event(
            id: sourceEventID,
            name: "Wicked Woods 2025",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: timeZone
        )
        let emptySource = try Event(
            id: emptySourceEventID,
            name: "Wicked Woods 2024",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: timeZone
        )
        try database.write { db in
            try Event.insert { current }.execute(db)
            try Event.insert { source }.execute(db)
            try Event.insert { emptySource }.execute(db)
        }
        return EventSet(
            currentEventID: currentEventID,
            sourceEventID: sourceEventID,
            sourceMainStageID: sourceMainStageID,
            sourceWoodsStageID: sourceWoodsStageID,
            destinationNonStageID: destinationNonStageID,
            destinationExistingStageID: destinationExistingStageID
        )
    }

    nonisolated private func insertStage(
        _ db: Database,
        id: EventPlace.ID,
        eventID: Event.ID,
        name: String,
        color: OME.Color? = nil,
        category: String? = nil,
        sortIndex: Int? = nil,
        icon: OME.SemanticIcon? = nil,
        shortLabel: String? = nil,
        lineup: [Contributor.ID]? = nil,
        media: [Open<OME.Media>]? = nil
    ) throws {
        var place = try EventPlace(
            id: id, event: eventID, name: name,
            createdAt: "2026-09-01T12:00:00Z"
        )
        var use = EventPlace.Kind.Stage()
        use.color = color
        use.category = category
        use.sortIndex = sortIndex
        use.icon = icon
        use.shortLabel = shortLabel
        use.lineup = lineup
        place.kind = .known(.stage(use))
        place.media = media
        let savedPlace = place
        try EventPlace.insert { savedPlace }.execute(db)
    }

    nonisolated private func insertNonStagePlace(
        _ db: Database,
        id: EventPlace.ID,
        eventID: Event.ID,
        name: String
    ) throws {
        let place = try EventPlace(
            id: id, event: eventID, name: name,
            createdAt: "2026-09-01T12:00:00Z"
        )
        try EventPlace.insert { place }.execute(db)
    }
}

private struct EventSet {
    let currentEventID: Event.ID
    let sourceEventID: Event.ID
    let sourceMainStageID: EventPlace.ID
    let sourceWoodsStageID: EventPlace.ID
    let destinationNonStageID: EventPlace.ID
    let destinationExistingStageID: EventPlace.ID
}
