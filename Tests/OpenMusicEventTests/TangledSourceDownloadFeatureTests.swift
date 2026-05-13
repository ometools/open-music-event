import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventSource
import SQLiteData
import Testing

@testable import OpenMusicEvent

@MainActor
struct TangledSourceDownloadFeatureTests {
    @Test
    func myEventsPresentsDownloadFeature() throws {
        let database = try makePreparedDatabase()
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.exhaustivity = .off
        } operation: {
            TestStore(initialState: MyEvents.State()) {
                MyEvents()
            }
        }

        store.send(.didTapImportSource)

        guard case .sourceImport = store.state.destination else {
            Issue.record("Expected My Events to present the Tangled source download feature.")
            return
        }
    }

    @Test
    func myEventsFetchesDownloadedOrganizers() async throws {
        let database = try makePreparedDatabase()
        let eventID = importedEventID()
        try await database.write { db in
            try OMERecord.Organizer.insert {
                OMERecord.Organizer.Draft(id: eventID.organizerID)
            }
            .execute(db)
            try OMERecord.Event.insert {
                CreateEvent.makeEventDraft(
                    id: eventID,
                    name: "Imported Event",
                    startDate: nil,
                    endDate: nil
                )
            }
            .execute(db)
            try OMERecord.EventOrganizer.insert {
                OMERecord.EventOrganizer.Draft(
                    id: .init(
                        organizerID: eventID.organizerID,
                        eventID: eventID.eventID,
                        eventOrganizerID: eventID.organizerID
                    )
                )
            }
            .execute(db)
        }

        let organizers = try await database.read { db in
            try MyEvents.organizersQuery.fetchAll(db)
        }
        let events = try await database.read { db in
            try MyEvents.query.fetchAll(db)
        }

        #expect(organizers.map(\.id) == [eventID.organizerID])
        #expect(events.isEmpty)
    }

    @Test
    func importsTangledSourceUsingRepositoryRef() async throws {
        let recorder = ImportRecorder()
        let eventID = importedEventID()
        let result = try validationResult(eventID: eventID)

        let store = withDependencies {
            $0.context = .test
            $0.exhaustivity = .off
            $0.tangledSourceImport = TangledSourceImportClient { request in
                await recorder.record(request)
                return result
            }
        } operation: {
            var initialState = TangledSourceDownload.State()
            initialState.repository = " https://tangled.org/woody.fm/shambhala-ome "
            initialState.ref = " main "
            return TestStore(initialState: initialState) {
                TangledSourceDownload()
            }
        }

        await store.send(.importButtonTapped) {
            $0.isImporting = true
        }?.value
        #expect(store.state.isImporting == false)
        #expect(store.state.importedSummary == result.summary)
        #expect(store.state.errorMessage == nil)
        #expect(store.isPresented == false)

        #expect(
            await recorder.requests == [
                OpenMusicEventSourceValidationRequest(
                    source: "https://tangled.org/woody.fm/shambhala-ome",
                    ref: "main"
                )
            ]
        )
    }

    @Test
    func myEventsOpensOrganizerDetailAfterSourceImportCompletes() async throws {
        let database = try makePreparedDatabase()
        let organizerID = importedEventID().organizerID
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            var initialState = MyEventsImportHarness.State()
            initialState.myEvents.destination = .sourceImport(Spawn(TangledSourceDownload.State()))
            return TestStore(initialState: initialState) {
                MyEventsImportHarness()
            }
        }

        await store.send(.completeImport(organizerID))?.value
        await Task.yield()
        #expect(store.state.destination == nil)
        #expect(store.state.organizerDetail?.organizerID == organizerID)
    }

    @Test
    func emptyRefDefaultsToHEAD() async throws {
        let recorder = ImportRecorder()

        let store = withDependencies {
            $0.context = .test
            $0.exhaustivity = .off
            $0.tangledSourceImport = TangledSourceImportClient { request in
                await recorder.record(request)
                return try validationResult()
            }
        } operation: {
            var initialState = TangledSourceDownload.State()
            initialState.repository = "woody.fm/shambhala-ome"
            initialState.ref = " "
            return TestStore(initialState: initialState) {
                TangledSourceDownload()
            }
        }

        await store.send(.importButtonTapped)?.value

        #expect(await recorder.requests.map(\.ref) == ["HEAD"])
    }

    @Test
    func reportsEmptyRepository() throws {
        let store = withDependencies {
            $0.context = .test
        } operation: {
            TestStore(initialState: TangledSourceDownload.State()) {
                TangledSourceDownload()
            }
        }

        store.send(.importButtonTapped) {
            $0.errorMessage = "Enter a Tangled repository."
        }
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
}

private actor ImportRecorder {
    var requests: [OpenMusicEventSourceValidationRequest] = []

    func record(_ request: OpenMusicEventSourceValidationRequest) {
        requests.append(request)
    }
}

@Feature
private struct MyEventsImportHarness {
    struct State {
        var destination: MyEvents.Destination.State?
        var organizerDetail: OrganizerDetail.State?
        var myEvents = MyEvents.State()
    }

    enum Action {
        case completeImport(OMERecord.Organizer.ID)
        case myEvents(MyEvents.Action)
    }

    var body: some Feature {
        Scope(state: \.myEvents, action: \.myEvents) {
            MyEvents()
        }
        .onChange(of: \.myEvents.destination, initial: true) { _, newValue, state in
            state.destination = newValue
        }
        .onChange(of: \.myEvents.organizerDetail, initial: true) { _, newValue, state in
            state.organizerDetail = newValue
        }
        Update { _, action in
            switch action {
            case .completeImport(let organizerID):
                store.addTask {
                    try store.post(
                        key: SourceImportCompleted.self,
                        value: organizerID
                    )
                }
            case .myEvents:
                break
            }
        }
    }
}

private func validationResult(
    eventID: OMERecord.Event.ID = importedEventID()
) throws -> OpenMusicEventSourceValidationResult {
    let source = OpenMusicEventSourceRepository(events: [])
    let insertion = try OMERecord.SourceDatabaseInsertion(
        .init(source: source, organizerID: eventID.organizerID)
    )
    return OpenMusicEventSourceValidationResult(
        repositoryURL: FileManager.default.temporaryDirectory,
        organizerID: eventID.organizerID,
        insertion: insertion,
        insertedEventIDs: [eventID],
        summary: SourceValidationSummary(
            events: [.init(eventID: eventID.eventID.rawValue.rawValue, name: "Imported Event")],
            stageCount: 0,
            scheduleCount: 0,
            participantCount: 0,
            channelCount: 0,
            posterCount: 0,
            performanceCount: 0,
            performanceParticipantCount: 0
        )
    )
}

private func importedEventID() -> OMERecord.Event.ID {
    let organizerID = OMERecord.Organizer.ID("did:plc:imported")!
    return OMERecord.Event.ID(
        organizerID: organizerID,
        eventID: OMERecord.ID<OMERecord.Event>(.init("imported-event"))
    )
}
