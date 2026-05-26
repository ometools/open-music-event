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
    func proposeChangeReviewsChangesWhenPatchIsNotReady() async throws {
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

        let task = store.send(.proposeChangeButtonTapped) {
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
    func proposeChangeButtonPresentsComposerForGeneratedPatch() async throws {
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
        let store = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            var state = EditEvent.State(eventID: eventID)
            state.sourcePatchStatus = .generated(patch)
            return TestStore(initialState: state) {
                EditEvent()
            }
        }

        store.send(.proposeChangeButtonTapped) {
            $0.isSourceProposalComposerPresented = true
            $0.sourceProposalStatus = .composing
        }

        await store.dismount()
    }

    @Test
    func sourceProposalDescriptionCanBeUpdated() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let store = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            TestStore(initialState: EditEvent.State(eventID: eventID)) {
                EditEvent()
            }
        }

        store.send(.sourceProposalDescriptionChanged("Updated the event name.")) {
            $0.sourceProposalDescription = "Updated the event name."
        }

        await store.dismount()
    }

    @Test
    func createProposalPublishesGeneratedPatchWithResolvedSourceLocation() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let repositoryURL = URL(fileURLWithPath: "/tmp/source-repository")
        let location = SourcePatchLocation(
            repositoryURL: repositoryURL,
            relativePath: "events/event-1"
        )
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
        let sourceChangeURL = try #require(URL(string: "https://source.woody.fm/events/event-1/proposals/1"))
        let publication = SourcePatchPublication(sourceChangeURL: sourceChangeURL)

        let store = withDependencies {
            $0.defaultDatabase = database
            $0.openMusicEventSourcePatchLocationResolver = OpenMusicEventSourcePatchLocationResolver { request in
                #expect(request == OpenMusicEventSourcePatchRequest(eventID: eventID))
                return location
            }
            $0.sourcePatchPublisher = SourcePatchPublisher { request in
                #expect(
                    request == SourcePatchPublishRequest(
                        description: "Updated the event name.",
                        location: location,
                        patch: patch
                    )
                )
                return publication
            }
        } operation: {
            var state = EditEvent.State(eventID: eventID)
            state.isSourceProposalComposerPresented = true
            state.sourcePatchStatus = .generated(patch)
            state.sourceProposalDescription = "Updated the event name."
            state.sourceProposalStatus = .composing
            return TestStore(initialState: state) {
                EditEvent()
            }
        }

        let task = store.send(.createProposalButtonTapped) {
            $0.sourceProposalStatus = .proposing
        }
        await store.receive(
            \.sourceProposalResponse,
            .equals(.success(publication)),
            timeout: .seconds(1)
        ) {
            $0.sourceProposalStatus = .created(publication)
        }
        await task?.value

        await store.dismount()
    }

    @Test
    func failedProposalCanBeRetried() async throws {
        let database = try makePreparedDatabase()
        let eventID = testEventID("event-1")
        let location = SourcePatchLocation(
            repositoryURL: URL(fileURLWithPath: "/tmp/source-repository"),
            relativePath: "events/event-1"
        )
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

        let store = withDependencies {
            $0.defaultDatabase = database
            $0.openMusicEventSourcePatchLocationResolver = OpenMusicEventSourcePatchLocationResolver { _ in
                location
            }
            $0.sourcePatchPublisher = SourcePatchPublisher { _ in
                throw SourceProposalTestError.failed
            }
        } operation: {
            var state = EditEvent.State(eventID: eventID)
            state.isSourceProposalComposerPresented = true
            state.sourcePatchStatus = .generated(patch)
            state.sourceProposalStatus = .composing
            return TestStore(initialState: state) {
                EditEvent()
            }
        }
        let failure = EditEvent.SourceProposalFailure(SourceProposalTestError.failed)

        let task = store.send(.createProposalButtonTapped) {
            $0.sourceProposalStatus = .proposing
        }
        await store.receive(
            \.sourceProposalResponse,
            .equals(.failure(failure)),
            timeout: .seconds(1)
        ) {
            $0.sourceProposalStatus = .failed(failure)
        }
        await task?.value

        let retryTask = store.send(.createProposalButtonTapped) {
            $0.sourceProposalStatus = .proposing
        }
        await store.receive(
            \.sourceProposalResponse,
            .equals(.failure(failure)),
            timeout: .seconds(1)
        ) {
            $0.sourceProposalStatus = .failed(failure)
        }
        await retryTask?.value

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

private enum SourceProposalTestError: Equatable, Error {
    case failed
}
