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
