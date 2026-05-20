import ComposableArchitecture2
import Dependencies
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SQLiteData
import Testing

@testable import OpenMusicEvent
@testable import OpenMusicEventAppEventViewer

@MainActor
struct EditEventSourcePatchInvalidationTests {
    @Test
    func marksSourcePatchNeedsGenerationWhenCurrentEventInvalidates() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let invalidation = SourcePatchInvalidation(
            eventID: eventID,
            operation: .update,
            tableName: OME.Participant.tableName
        )
        let stream = AsyncStream.makeStream(of: SourcePatchInvalidation.self)
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.sourcePatchInvalidations = SourcePatchInvalidations(
                installTriggers: { _ in },
                stream: { stream.stream }
            )
        } operation: {
            TestStore(initialState: EditEvent.State(eventID: eventID)) {
                EditEvent()
            }
        }

        stream.continuation.yield(invalidation)
        await store.receive(
            \.sourcePatchInvalidationReceived,
            .equals(invalidation),
            timeout: .seconds(1)
        ) {
            $0.sourcePatchStatus = .needsGeneration(invalidation)
        }

        stream.continuation.finish()
        await store.dismount()
    }

    @Test
    func ignoresSourcePatchInvalidationsForOtherEvents() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let otherEventInvalidation = SourcePatchInvalidation(
            eventID: testEventID("event-2"),
            operation: .update,
            tableName: OME.Participant.tableName
        )
        let stream = AsyncStream.makeStream(of: SourcePatchInvalidation.self)
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.sourcePatchInvalidations = SourcePatchInvalidations(
                installTriggers: { _ in },
                stream: { stream.stream }
            )
        } operation: {
            TestStore(initialState: EditEvent.State(eventID: eventID)) {
                EditEvent()
            }
        }

        stream.continuation.yield(otherEventInvalidation)
        await Task.yield()

        #expect(store.state.sourcePatchStatus == .notGenerated)

        stream.continuation.finish()
        await store.dismount()
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

private func testEventID(_ string: String) -> OME.Event.ID {
    OME.Event.ID(
        organizerID: OME.Organizer.ID("did:web:example.com")!,
        eventID: OME.ID<OME.Event>(.init(string))
    )
}
