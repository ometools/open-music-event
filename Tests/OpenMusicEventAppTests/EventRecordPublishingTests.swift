import ATProto
import ATProtoOAuth
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import OpenMusicEventAuthentication
@testable import OpenMusicEventDatabase
import OpenMusicEventLexicon
import Sharing
import SQLiteData
import Testing
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventSourceEditing

@MainActor
@Suite
struct EventRecordPublishingTests {
    @Test(.tcaExhaustivity(.off))
    func `only eligible readers can enter a workspace and local imports do not require sign in`() async throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        let owner = DID("did:plc:entryowner")!
        let id = Event.ID("at://did:plc:entryowner/events.openmusic.event/3mrdbziccpcah")!
        let account = TestMutex<OAuth.Session?>(nil)
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.getOptionalDefaultSession = { account.withLock { $0 } }
        } operation: {
            TestStore(initialState: EventSettings.State(eventID: id)) { EventSettings() }
        }
        // An anonymous reader has no entry button, and cannot bypass it with the action.
        #expect(!store.state.canEnterWorkspace)
        await store.send(.enterAuthoringButtonTapped)?.value
        #expect(store.state.validatedWorkspaceSession == nil)

        account.withLock { $0 = canonicalWorkspaceTestOAuthSession(actorID: DID("did:plc:other")!) }
        #expect(!store.state.canEnterWorkspace)
        account.withLock { $0 = canonicalWorkspaceTestOAuthSession(actorID: owner) }
        #expect(store.state.canEnterWorkspace)
        account.withLock { $0 = nil }
        #expect(!store.state.canEnterWorkspace)

        // Importing a local source enables editing, even while signed out.
        let identity = CanonicalSourceEventIdentity(
            id: id, source: "https://example.com/testival", directory: "events/testival",
            publisher: owner, createdAt: "2026-07-01T00:00:00Z"
        )
        try await database.write { try CanonicalSourceEventIdentity.insert { identity }.execute($0) }
        try await store.state.$importedIdentity.load()
        #expect(store.state.canEnterWorkspace)
        await store.dismount()
    }

    @Test(.tcaExhaustivity(.off))
    func `partial publication clears only verified events and retry reviews only the remaining changes`() async throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        let owner = DID("did:plc:organizer")!
        let id = Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")!
        let minimalID = Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcai")!
        let event = try Event(id: id, name: "Testival", createdAt: "2026-07-01T00:00:00Z", timeZone: .gmt)
        let minimal = try Event(id: minimalID, name: "Minimal Event", createdAt: "2026-07-01T00:00:00Z", timeZone: .gmt)
        try await database.write { db in
            try Event.insert { [event, minimal] }.execute(db)
            for (event, directory) in [(event, "events/testival"), (minimal, "events/minimal")] {
                let identity = CanonicalSourceEventIdentity(
                    id: event.id, source: "https://example.com/testival", directory: directory,
                    publisher: owner, createdAt: event.createdAt
                )
                try CanonicalSourceEventIdentity.insert { identity }.execute(db)
            }
        }
        let failMinimal = TestMutex(true)
        let writes = TestMutex<[Event.ID: EventRecordPublication.Record]>([:])
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.getOptionalDefaultSession = { nil }
            $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { _ in }
            $0[EventRecordPublisher.self] = EventRecordPublisher(
                upload: { _, _ in Issue.record("These events have no images"); throw CancellationError() },
                put: { record, _ in
                    if record.id == minimalID && failMinimal.withLock({ $0 }) { throw CancellationError() }
                    writes.withLock { $0[record.id] = record }
                    return .init(uri: record.id, cid: ATProto.CID(rawValue: "bafyreiverified"))
                },
                read: { id, cid in
                    .init(uri: id, cid: cid, value: try #require(writes.withLock { $0[id]?.payload }))
                }
            )
        } operation: {
            TestStore(initialState: EventRecordPublishing.State(
                eventID: id, selectedSessionID: Shared(value: Atmosphere.Account.ID(owner))
            )) { EventRecordPublishing() }
        }

        // Imported, unchanged Events still need a first publication.
        expectNoDifference(store.state.pendingEvents.map(\.id), [id, minimalID])
        await store.send(.reviewButtonTapped)?.value
        expectNoDifference(store.state.reviewChanges.map(\.kind), [.added, .added])
        await store.send(.publishButtonTapped)?.value
        expectNoDifference(store.state.result?.receipts.map(\.id), [id])
        expectNoDifference(store.state.pendingEvents.map(\.id), [minimalID])
        let saved = try await database.read { try EventRecordPublicationReceipt.find(id).fetchOne($0) }
        expectNoDifference(saved?.event?.value, try event.encodeLexicon())

        // Retry does not include the already verified Event.
        failMinimal.withLock { $0 = false }
        await store.send(.reviewButtonTapped)?.value
        expectNoDifference(store.state.review?.records.map(\.id), [minimalID])
        await store.send(.publishButtonTapped)?.value
        expectNoDifference(store.state.pendingEvents, [])
        expectNoDifference(writes.withLock { $0.count }, 2)

        // A later edit is reviewed against the last verified content.
        var edited = event
        edited.description = "A later local edit"
        let localEdit = edited
        try await database.write { try Event.upsert { localEdit }.execute($0) }
        try await store.state.$events.load()
        try await store.state.$changes.load()
        await store.send(.reviewButtonTapped)?.value
        expectNoDifference(store.state.reviewChanges.map(\.kind), [.edited])
        expectNoDifference(store.state.reviewChanges.first?.fields.first?.after?.lines, ["A later local edit"])
        await store.dismount()
    }

    @Test func `authorization cancellation preserves the reviewed event without publishing`() async throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        let id = Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")!
        let event = try Event(id: id, name: "Local edits", createdAt: "2026-07-01T00:00:00Z", timeZone: .gmt)
        try await database.write { try Event.insert { event }.execute($0) }
        let publisher = EventRecordPublisher(
            upload: { _, _ in Issue.record("Cancelled authorization must not upload"); throw CancellationError() },
            put: { _, _ in Issue.record("Cancelled authorization must not write"); throw CancellationError() },
            read: { _, _ in Issue.record("Cancelled authorization must not read back"); throw CancellationError() }
        )
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.getOptionalDefaultSession = { nil }
            $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { _ in throw CancellationError() }
            $0[EventRecordPublisher.self] = publisher
        } operation: {
            let state = EventRecordPublishing.State(
                eventID: id,
                selectedSessionID: Shared(value: Atmosphere.Account.ID(DID("did:plc:organizer")!))
            )
            return Store(initialState: state) { EventRecordPublishing() }
        }
        await store.send(.reviewButtonTapped)?.value
        let review = try #require(store.review)
        await store.send(.publishButtonTapped)?.value
        #expect(store.errorMessage == "Publication was cancelled. Your local edits are unchanged.")
        #expect(!store.isPublishing)
        expectNoDifference(store.review, review)
        let saved = try await database.read { try Event.find(id).fetchOne($0) }
        expectNoDifference(saved, event)
    }

    @Test func `only explicitly imported local workspaces can edit without an account`() throws {
        let database = try DatabaseQueue()
        let baseline = SourceBaselineDatabase(path: "baseline", database: database)
        let actor = DID("did:plc:organizer")!
        let id = Event.ID("at://\(actor)/events.openmusic.event/3mrdbziccpcah")!
        let local = EventWorkspaceSession(eventID: id, actorID: actor, baseline: baseline, isLocalSource: true)
        let remote = EventWorkspaceSession(eventID: id, actorID: actor, baseline: baseline)
        #expect(local.authorizes(eventID: id, selectedActorID: nil))
        #expect(!remote.authorizes(eventID: id, selectedActorID: nil))
        #expect(!remote.authorizes(eventID: id, selectedActorID: DID("did:plc:other")!))
        #expect(remote.authorizes(eventID: id, selectedActorID: actor))
    }

    @Test func `changing publisher during authorization prevents writes and preserves edits`() async throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        let id = Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")!
        let event = try Event(id: id, name: "Local edits", createdAt: "2026-07-01T00:00:00Z", timeZone: .gmt)
        try await database.write { try Event.insert { event }.execute($0) }
        let selection = Shared<Atmosphere.Account.ID?>(value: Atmosphere.Account.ID(DID("did:plc:organizer")!))
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.getOptionalDefaultSession = { nil }
            $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { _ in
                selection.withLock { $0 = Atmosphere.Account.ID(DID("did:plc:other")!) }
            }
            $0[EventRecordPublisher.self] = EventRecordPublisher(
                upload: { _, _ in Issue.record("Account change must not upload"); throw CancellationError() },
                put: { _, _ in Issue.record("Account change must not write"); throw CancellationError() },
                read: { _, _ in Issue.record("Account change must not read back"); throw CancellationError() }
            )
        } operation: {
            let state = EventRecordPublishing.State(eventID: id, selectedSessionID: selection)
            return Store(initialState: state) { EventRecordPublishing() }
        }
        await store.send(.reviewButtonTapped)?.value
        #expect(store.review != nil)
        await store.send(.publishButtonTapped)?.value
        #expect(store.errorMessage == EventRecordPublication.PublicationError.wrongAccount.localizedDescription)
        #expect(!store.isPublishing)
        #expect(store.result == nil)
        let saved = try await database.read { try Event.find(id).fetchOne($0) }
        expectNoDifference(saved, event)
    }

    @Test func `edits saved during authorization require a new review before any network write`() async throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        let id = Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")!
        let original = try Event(id: id, name: "Reviewed title", createdAt: "2026-07-01T00:00:00Z", timeZone: .gmt)
        var edited = original
        edited.description = "Saved while consent was open"
        let savedEdit = edited
        try await database.write { try Event.insert { original }.execute($0) }
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.getOptionalDefaultSession = { nil }
            $0.oauthAuthorizationBroker = OAuth.AuthorizationBroker { _ in
                try await database.write { try Event.upsert { savedEdit }.execute($0) }
            }
            $0[EventRecordPublisher.self] = EventRecordPublisher(
                upload: { _, _ in Issue.record("Stale review must not upload"); throw CancellationError() },
                put: { _, _ in Issue.record("Stale review must not write"); throw CancellationError() },
                read: { _, _ in Issue.record("Stale review must not read back"); throw CancellationError() }
            )
        } operation: {
            let state = EventRecordPublishing.State(
                eventID: id,
                selectedSessionID: Shared(value: Atmosphere.Account.ID(DID("did:plc:organizer")!))
            )
            return Store(initialState: state) { EventRecordPublishing() }
        }
        await store.send(.reviewButtonTapped)?.value
        #expect(store.review?.records.first?.event.description == nil)
        await store.send(.publishButtonTapped)?.value
        #expect(store.errorMessage == EventRecordPublication.PublicationError.reviewChanged.localizedDescription)
        #expect(!store.isPublishing)
        #expect(store.result == nil)
        let saved = try await database.read { try Event.find(id).fetchOne($0) }
        expectNoDifference(saved, savedEdit)
    }
}
