import ATProto
import ATProtoOAuth
import ComposableArchitecture2
import CustomDump
import Dependencies
import Foundation
import OpenMusicEventAuthentication
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import Sharing
import SQLiteData
import Testing
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventSourceEditing

@MainActor
@Suite
struct EventRecordPublishingTests {
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
