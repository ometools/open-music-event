import ATProto
import ATProtoOAuth
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
@testable import OpenMusicEventSourceEditing
import Sharing
import SQLiteData
import Testing
@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

@MainActor
@Suite(.tcaExhaustivity(.off))
struct EventCreationTests {
    @Test func `creation requires an account and cancellation leaves no event`() async throws {
        let database = try database()
        let account = TestMutex<OAuth.Session?>(nil)
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 1_791_201_600)
            $0.getOptionalDefaultSession = { account.withLock { $0 } }
        } operation: { TestStore(initialState: MyEvents.State()) { MyEvents() } }

        #expect(!store.canCreateEvent)
        await store.send(.createButtonTapped)?.value
        #expect(store.eventForm == nil)
        account.withLock { $0 = canonicalWorkspaceTestOAuthSession(actorID: DID("did:plc:creator")!) }
        #expect(store.canCreateEvent)
        await store.send(.createButtonTapped)?.value
        #expect(store.eventForm != nil)
        await store.send(.eventForm(.cancelButtonTapped))?.value
        #expect(store.eventForm == nil)
        let events = try await database.read { try Event.all.fetchAll($0) }
        let installed = try await database.read { try InstalledEvent.all.fetchAll($0) }
        let created = try await database.read { try LocallyCreatedEvent.all.fetchAll($0) }
        expectNoDifference(events, [])
        expectNoDifference(installed, [])
        expectNoDifference(created, [])
        await store.dismount()
    }

    @Test(arguments: [false, true])
    func `a new event survives reopening and uses the existing publisher without source provenance`(withImage: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appending(path: "events.sqlite").path
        let database = try database(path: path)
        let owner = DID("did:plc:creator")!
        let session = canonicalWorkspaceTestOAuthSession(actorID: owner)
        let imageBytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=")!
        let fileStore = LocalImageFileStoreClient(
            existingFileURL: { key, _ in
                let url = directory.appending(path: key)
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            },
            write: { key, data, _ in
                let url = directory.appending(path: key)
                try data.write(to: url)
                return url
            }
        )
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 1_791_201_600)
            $0.getOptionalDefaultSession = { session }
            $0.localImageFileStore = fileStore
        } operation: { TestStore(initialState: MyEvents.State()) { MyEvents() } }

        await store.send(.createButtonTapped)?.value
        let id = try #require(store.eventForm?.eventID)
        let createdAt = try #require(store.eventForm?.draft.createdAt)
        expectNoDifference(id.authority, .did(owner))
        // Invalid content stays in the form and does not create an installed event.
        await store.send(.eventForm(.saveButtonTapped))?.value
        #expect(store.eventForm?.errorMessage != nil)
        let invalidEvents = try await database.read { try Event.all.fetchAll($0) }
        expectNoDifference(invalidEvents, [])
        store.modify {
            $0.eventForm?.draft.name = "Created in the app"
            $0.eventForm?.draft.description = "No source repository needed"
            $0.eventForm?.draft.timeZone = TimeZone(identifier: "America/Denver")!
            if withImage {
                $0.eventForm?.mediaEntries = [.init(importedImage: .init(
                    mimeType: "image/png", data: imageBytes,
                    image: .init(source: .known(.blob(localImageBlob(imageBytes, mimeType: .png))),
                                 alt: "An image for the new event", role: .known(.hero))
                ))]
            }
        }
        await store.send(.eventForm(.saveButtonTapped))?.value
        #expect(store.eventForm == nil)
        try await store.state.$events.load()
        expectNoDifference(store.sortedEvents.map(\.id), [id])
        await store.dismount()

        // A new connection and mounted library read the durable draft.
        let reopened = try DatabaseQueue(path: path)
        let savedEvent = try await reopened.read { try Event.find(id).fetchOne($0) }
        let event = try #require(savedEvent)
        expectNoDifference(event.createdAt, createdAt)
        expectNoDifference(event.description, "No source repository needed")
        let sources = try await reopened.read { try CanonicalSourceEventIdentity.all.fetchAll($0) }
        let created = try await reopened.read { try LocallyCreatedEvent.find(id).fetchOne($0) }
        expectNoDifference(sources, [])
        #expect(created != nil)

        // Even when workspace entry captures this saved draft, first publication is Added.
        let baseline = try CanonicalWorkspaceBaseline.openOrCapture(
            at: directory.appending(path: "baseline.sqlite").path, from: reopened
        )
        let payload = TestMutex<Lexicon.JSONValue?>(nil)
        let publishing = withDependencies {
            $0.defaultDatabase = reopened
            $0.getOptionalDefaultSession = { session }
            $0.localImageFileStore = fileStore
            $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { _ in }
            $0[EventRecordPublisher.self] = EventRecordPublisher(
                upload: { image, _ in
                    #expect(withImage)
                    expectNoDifference(image.bytes, imageBytes)
                    return image.blob
                },
                put: { record, _ in
                    payload.withLock { $0 = record.payload }
                    return .init(uri: record.id, cid: ATProto.CID(rawValue: "bafyreicreated"))
                },
                read: { uri, cid in .init(uri: uri, cid: cid, value: try #require(payload.withLock { $0 })) }
            )
        } operation: {
            TestStore(initialState: EventRecordPublishing.State(
                eventID: id, baseline: baseline, selectedSessionID: Shared(value: Atmosphere.Account.ID(owner))
            )) { EventRecordPublishing() }
        }
        expectNoDifference(publishing.pendingEvents.map(\.id), [id])
        await publishing.send(.reviewButtonTapped)?.value
        expectNoDifference(publishing.reviewChanges.map(\.kind), [.added])
        expectNoDifference(publishing.review?.records.first?.images.map(\.bytes), withImage ? [imageBytes] : [])
        await publishing.send(.publishButtonTapped)?.value
        expectNoDifference(publishing.result?.receipts.map(\.id), [id])
        expectNoDifference(publishing.pendingEvents, [])
        await publishing.dismount()

        // Later edits still use the same URI and creation timestamp.
        var edited = event
        edited.description = "Second version"
        let saved = edited
        try await reopened.write { try Event.upsert { saved }.execute($0) }
        let changes = try await reopened.read { try CanonicalChangesRequest(eventID: id, baseline: baseline).fetch($0) }
        expectNoDifference(changes.map(\.kind), [.edited])
        expectNoDifference(changes.map(\.id), [id])
        let updatedCreatedAt = try await reopened.read { try Event.find(id).fetchOne($0)?.createdAt }
        expectNoDifference(updatedCreatedAt, createdAt)
    }

    @Test func `switching accounts or signing out keeps the unsaved draft with its original owner`() async throws {
        let database = try database()
        let owner = canonicalWorkspaceTestOAuthSession(actorID: DID("did:plc:creator")!)
        let account = TestMutex<OAuth.Session?>(owner)
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 1_791_201_600)
            $0.getOptionalDefaultSession = { account.withLock { $0 } }
        } operation: { TestStore(initialState: MyEvents.State()) { MyEvents() } }
        await store.send(.createButtonTapped)?.value
        let id = try #require(store.eventForm?.eventID)
        store.modify { $0.eventForm?.draft.name = "Keep this draft" }
        for session in [canonicalWorkspaceTestOAuthSession(actorID: DID("did:plc:other")!), nil] {
            account.withLock { $0 = session }
            await store.send(.eventForm(.saveButtonTapped))?.value
            expectNoDifference(store.eventForm?.eventID, id)
            expectNoDifference(store.eventForm?.draft.name, "Keep this draft")
            #expect(store.eventForm?.errorMessage?.contains("account") == true)
            let events = try await database.read { try Event.all.fetchAll($0) }
            expectNoDifference(events, [])
        }
        account.withLock { $0 = owner }
        await store.send(.eventForm(.saveButtonTapped))?.value
        #expect(store.eventForm == nil)
        let ids = try await database.read { try Event.all.fetchAll($0).map(\.id) }
        expectNoDifference(ids, [id])
        await store.dismount()
    }

    func database(path: String = ":memory:") throws -> DatabaseQueue {
        let database = try DatabaseQueue(path: path)
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }
}
