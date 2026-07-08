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
@Suite(.tcaExhaustivity(.off))
struct StageDuplicationTests {
    @Test
    func emitsCopyStagesFromOtherEventRequestWhenCurrentEventIsEmpty() async throws {
        let database = try makePreparedDatabase()
        let fixture = try await seedEventSet(database: database)
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
    func emitsCopyStagesFromOtherEventRequestWhenCurrentEventHasOnlySingletonStage() async throws {
        let database = try makePreparedDatabase()
        let fixture = try await seedEventSet(database: database)
        try await database.write { db in
            try EventSingletonStage.insert(eventID: fixture.currentEventID, in: db)
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
        let database = try makePreparedDatabase()
        let fixture = try await seedEventSet(database: database)
        let localFileURL = URL(fileURLWithPath: "/tmp/2025-stage-logo.png")
        try await database.write { db in
            try insertStage(
                db,
                eventID: fixture.sourceEventID,
                stageID: "main-stage",
                name: "Main Stage",
                color: 0x00bbcc,
                category: OMERecord.Stage.Category("music"),
                sortIndex: 1,
                images: [
                    OMERecord.ImageAsset(
                        assetKey: "old-event-key",
                        source: .url(URL(string: "https://example.com/main-stage.png")!),
                        role: .hero,
                        renderKind: .fullImage,
                        materializationPolicy: .prefetchOnOpen
                    ),
                    OMERecord.ImageAsset(
                        assetKey: "local-cache-key",
                        source: .url(localFileURL),
                        role: .logo,
                        renderKind: .transparent,
                        materializationPolicy: .prefetchOnOpen
                    ),
                ],
                systemIconName: "music.note",
                iconShortCode: "main",
                lineup: [contributorLocalID("artist-one")]
            )
            try insertStage(
                db,
                eventID: fixture.sourceEventID,
                stageID: "woods",
                name: "Woods",
                color: 0x336699,
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
            store.state.sourceStages.map(\.id.stageID.rawValue.rawValue),
            ["main-stage", "woods"]
        )
        expectNoDifference(
            Set(store.state.selectedStageIDs.map(\.rawValue.rawValue)),
            Set(["main-stage", "woods"])
        )

        store.send(.stageButtonTapped(stageLocalID("woods"))) {
            $0.selectedStageIDs.remove(stageLocalID("woods"))
        }

        await store.send(.copyButtonTapped)?.value

        #expect(store.state.errorMessage == nil)
        #expect(store.state.isCopying == false)
        #expect(store.isPresented == false)

        let stages = try await database.read { db in
            try StagesViewer.stagesQuery(eventID: fixture.currentEventID).fetchAll(db)
        }
        expectNoDifference(stages.map(\.id.stageID.rawValue.rawValue), ["main-stage"])
        expectNoDifference(stages.map(\.name), ["Main Stage"])

        let mainStage = try #require(stages.first)
        #expect(mainStage.id.organizerID == fixture.currentEventID.organizerID)
        #expect(mainStage.id.eventID == fixture.currentEventID.eventID)
        #expect(mainStage.color == 0x00bbcc)
        #expect(mainStage.category == OMERecord.Stage.Category("music"))
        #expect(mainStage.sortIndex == 1)
        #expect(mainStage.systemIconName == "music.note")
        #expect(mainStage.iconShortCode == "main")
        #expect(mainStage.lineup == nil)

        let image = try #require(mainStage.images?.first)
        #expect(mainStage.images?.count == 1)
        #expect(image.assetKey == nil)
        #expect(image.url?.absoluteString == "https://example.com/main-stage.png")
    }

    @Test
    func copiesSelectedStagesFromOtherEventOverSingletonStage() async throws {
        let database = try makePreparedDatabase()
        let fixture = try await seedEventSet(database: database)
        try await database.write { db in
            try EventSingletonStage.insert(eventID: fixture.currentEventID, in: db)
            try insertStage(
                db,
                eventID: fixture.sourceEventID,
                stageID: "main-stage",
                name: "Main Stage",
                sortIndex: 1
            )
            try insertStage(
                db,
                eventID: fixture.sourceEventID,
                stageID: "woods",
                name: "Woods",
                sortIndex: 2
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

        let stages = try await database.read { db in
            try StagesViewer.stagesQuery(eventID: fixture.currentEventID).fetchAll(db)
        }
        expectNoDifference(stages.map(\.id.stageID.rawValue.rawValue), ["main-stage", "woods"])
        expectNoDifference(stages.map(\.name), ["Main Stage", "Woods"])
    }

    @Test
    func copyStagesListsOnlyOtherEventsWithStages() async throws {
        let database = try makePreparedDatabase()
        let fixture = try await seedEventSet(database: database)
        try await database.write { db in
            try insertStage(
                db,
                eventID: fixture.sourceEventID,
                stageID: "main-stage",
                name: "Main Stage"
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
        let database = try makePreparedDatabase()
        let fixture = try await seedEventSet(database: database)
        try await database.write { db in
            try insertStage(
                db,
                eventID: fixture.currentEventID,
                stageID: "existing",
                name: "Existing"
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
            try StagesViewer.stagesQuery(eventID: fixture.currentEventID).fetchAll(db)
        }
        expectNoDifference(stages.map(\.id.stageID.rawValue.rawValue), ["existing"])
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

    private func makeCopyStagesStore(
        eventID: OMERecord.Event.ID,
        database: any DatabaseWriter
    ) -> TestStore<CopyStagesFromEvent> {
        withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: CopyStagesFromEvent.State(eventID: eventID)) {
                CopyStagesFromEvent()
            }
        }
    }

    private func makeStagesViewerStore(
        eventID: OMERecord.Event.ID,
        database: any DatabaseWriter
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

    private func seedEventSet(
        database: any DatabaseWriter
    ) async throws -> EventSet {
        let currentEventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: eventLocalID("2026-pre-party-kelowna")
        )
        let sourceEventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: eventLocalID("2025")
        )
        let emptySourceEventID = OMERecord.Event.ID(
            organizerID: organizerID,
            eventID: eventLocalID("2024")
        )

        try await database.write { db in
            try insertOrganizer(db, id: organizerID)
            try insertEvent(db, id: currentEventID, name: "Wicked Woods 2026 Pre-Party Kelowna")
            try insertEvent(db, id: sourceEventID, name: "Wicked Woods 2025")
            try insertEvent(db, id: emptySourceEventID, name: "Wicked Woods 2024")
        }

        return EventSet(
            currentEventID: currentEventID,
            emptySourceEventID: emptySourceEventID,
            sourceEventID: sourceEventID
        )
    }
}

private struct EventSet {
    var currentEventID: OMERecord.Event.ID
    var emptySourceEventID: OMERecord.Event.ID
    var sourceEventID: OMERecord.Event.ID
}

private let organizerID = OMERecord.Organizer.ID("did:web:wickedwoods.example")!

private func eventLocalID(_ string: String) -> OMERecord.ID<OMERecord.Event> {
    OMERecord.ID<OMERecord.Event>(.init(string))
}

private func stageLocalID(_ string: String) -> OMERecord.ID<OMERecord.Stage> {
    OMERecord.ID<OMERecord.Stage>(.init(string))
}

private func contributorLocalID(_ string: String) -> OMERecord.ID<OMERecord.Contributor> {
    OMERecord.ID<OMERecord.Contributor>(.init(string))
}

private func insertOrganizer(
    _ db: Database,
    id organizerID: OMERecord.Organizer.ID
) throws {
    try OMERecord.Organizer.insert {
        OMERecord.Organizer.Draft(id: organizerID)
    }
    .execute(db)
}

private func insertEvent(
    _ db: Database,
    id eventID: OMERecord.Event.ID,
    name: String
) throws {
    try OMERecord.Event.insert {
        CreateEvent.makeEventDraft(
            id: eventID,
            name: name,
            timeZone: TimeZone(identifier: "America/Denver")!
        )
    }
    .execute(db)
}

private func insertStage(
    _ db: Database,
    eventID: OMERecord.Event.ID,
    stageID: String,
    name: String,
    color: OMEColor = 0x336699,
    category: OMERecord.Stage.Category? = nil,
    sortIndex: Int? = nil,
    images: [OMERecord.ImageAsset]? = nil,
    systemIconName: String? = nil,
    iconShortCode: String? = nil,
    lineup: [OMERecord.ID<OMERecord.Contributor>]? = nil
) throws {
    try OMERecord.Stage.insert {
        OMERecord.Stage.Draft(
            id: OMERecord.Stage.ID(
                organizerID: eventID.organizerID,
                eventID: eventID.eventID,
                stageID: stageLocalID(stageID)
            ),
            name: name,
            color: color,
            category: category,
            sortIndex: sortIndex,
            images: images,
            systemIconName: systemIconName,
            iconShortCode: iconShortCode,
            lineup: lineup
        )
    }
    .execute(db)
}
