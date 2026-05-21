import ComposableArchitecture2
import Dependencies
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import SourceEditing
import SQLiteData
import Testing

@testable import OpenMusicEvent
@testable import OpenMusicEventAppEventViewer

@MainActor
struct EditEventSourcePatchInvalidationTests {
    @Test
    func generateSourcePatchButtonLoadsPatch() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/event.yml",
                    kind: .modified,
                    oldContents: Data("name: Old\n".utf8),
                    newContents: Data("name: New\n".utf8)
                )
            ]
        )
        let store: TestStore<EditEvent> = withDependencies {
            $0.defaultDatabase = database
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = SourcePatchGenerator { request in
                #expect(request == OpenMusicEventSourcePatchRequest(eventID: eventID))
                return patch
            }
        } operation: {
            TestStore(initialState: EditEvent.State(eventID: eventID)) {
                EditEvent()
            }
        }

        let task = store.send(.generateSourcePatchButtonTapped) {
            $0.sourcePatchStatus = .generating
        }
        await store.receive(
            \.sourcePatchGenerationResponse,
            .equals(.success(patch)),
            timeout: .seconds(1)
        ) {
            $0.sourcePatchStatus = .generated(patch)
        }
        await task?.value

        await store.dismount()
    }

    @Test
    func selectingSourceChangeViewGeneratesPatch() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let patch = SourcePatch()
        let store: TestStore<EditEvent> = withDependencies {
            $0.defaultDatabase = database
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = SourcePatchGenerator { request in
                #expect(request == OpenMusicEventSourcePatchRequest(eventID: eventID))
                return patch
            }
        } operation: {
            TestStore(initialState: EditEvent.State(eventID: eventID)) {
                EditEvent()
            }
        }

        store.modify {
            $0.selectedChangeView = .source
        }
        let task = await store.receive(\.generateSourcePatchButtonTapped, timeout: .seconds(1)) {
            $0.sourcePatchStatus = .generating
        }
        await store.receive(
            \.sourcePatchGenerationResponse,
            .equals(.success(patch)),
            timeout: .seconds(1)
        ) {
            $0.sourcePatchStatus = .generated(patch)
        }
        await task?.value

        await store.dismount()
    }

    @Test
    func sourceInvalidationRegeneratesPatchWhenSourceChangeViewIsSelected() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let invalidation = SourcePatchInvalidation(
            eventID: eventID,
            operation: .update,
            tableName: OME.Participant.tableName
        )
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/event-1/participants/artist.md",
                    kind: .modified,
                    oldContents: Data("Old bio.\n".utf8),
                    newContents: Data("New bio.\n".utf8)
                )
            ]
        )
        let stream = AsyncStream.makeStream(of: SourcePatchInvalidation.self)
        let store: TestStore<EditEvent> = withDependencies {
            $0.defaultDatabase = database
            $0.sourcePatchInvalidations = SourcePatchInvalidations(
                installTriggers: { _ in },
                stream: { stream.stream }
            )
            $0[SourcePatchGeneratorKey<OpenMusicEventSourcePatchRequest>.self] = SourcePatchGenerator { request in
                #expect(request == OpenMusicEventSourcePatchRequest(eventID: eventID))
                return patch
            }
        } operation: {
            TestStore(initialState: EditEvent.State(eventID: eventID)) {
                EditEvent()
            }
        }

        store.modify {
            $0.selectedChangeView = .source
        }
        let task = await store.receive(\.generateSourcePatchButtonTapped, timeout: .seconds(1)) {
            $0.sourcePatchStatus = .generating
        }
        await store.receive(
            \.sourcePatchGenerationResponse,
            .equals(.success(patch)),
            timeout: .seconds(1)
        ) {
            $0.sourcePatchStatus = .generated(patch)
        }
        await task?.value

        stream.continuation.yield(invalidation)
        await store.receive(
            \.sourcePatchInvalidationReceived,
            .equals(invalidation),
            timeout: .seconds(1)
        ) {
            $0.sourcePatchStatus = .generating
        }
        await store.receive(
            \.sourcePatchGenerationResponse,
            .equals(.success(patch)),
            timeout: .seconds(1)
        ) {
            $0.sourcePatchStatus = .generated(patch)
        }

        stream.continuation.finish()
        await store.dismount()
    }

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
