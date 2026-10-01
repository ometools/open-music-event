import ATProto
import ATProtoTypes
import ComposableArchitecture2
import ComposableCalendarEvents
import CustomDump
import ConcurrencyExtras
import Dependencies
import DebugSnapshots
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

@MainActor
struct CanonicalEventEditingTests {
    typealias Event = OpenMusicEventLexicon.Event

    @Test
    func editingFromBrowsePreservesProtocolIdentityAndUneditedFields() async throws {
        let database = try database()
        let event = try event()
        try await database.write { db in
            try #sql("""
                CREATE TABLE notes (
                    event TEXT REFERENCES "events.openmusic.event"(id) ON DELETE CASCADE,
                    note TEXT NOT NULL
                )
                """).execute(db)
        }

        let store = withDependencies {
            $0.defaultDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0.getSelectedOAuthSessionID = { nil }
            $0.eventRecords = .init { id in
                expectNoDifference(id, event.id)
                return EventRecordGraph(event: event)
            }
        } operation: {
            TestStore(initialState: EventBrowseDetail.State(event: listing(event))) {
                EventBrowseDetail()
            }
        }

        // Opening the browse result loads the canonical record without a source checkout.
        #expect(store.record == nil)
        await store.send(.task)?.value
        store.expect {
            $0.record = event
        }
        expectNoDifference(store.record, event)
        try await database.write { db in
            try #sql("INSERT INTO notes VALUES (\(event.id), 'Meet at the gate')").execute(db)
        }
        store.send(.editButtonTapped) {
            $0.eventInfoForm = .init(draft: event, isSaving: false, errorMessage: nil)
        }
        #expect(store.eventInfoForm?.eventID == event.id)
        store.modify {
            $0.eventInfoForm?.draft.name = "  Wicked Woods 2026  "
            $0.eventInfoForm?.draft.description = "  Updated locally  "
        } changes: {
            $0.eventInfoForm?.draft.name = "  Wicked Woods 2026  "
            $0.eventInfoForm?.draft.description = "  Updated locally  "
        }
        var expected = event
        expected.name = "Wicked Woods 2026"
        expected.description = "Updated locally"
        await store.send(.eventInfoForm(.saveButtonTapped)) {
            $0.eventInfoForm = nil
            $0.record = expected
        }?.value
        #expect(store.eventInfoForm == nil)

        let saved = try await database.read { try Event.find(event.id).fetchOne($0) }
        // Equality covers exact timestamp spelling, CID, unknown media and all other fields.
        expectNoDifference(saved, expected)
        let note = try await database.read {
            try #sql("SELECT note FROM notes", as: String.self).fetchOne($0)
        }
        expectNoDifference(note, "Meet at the gate")

        // The mounted detail query follows the edit without a hand-maintained snapshot.
        expectNoDifference(store.record, expected)
        expectNoDifference(store.title, "Wicked Woods 2026")
        expectNoDifference(store.eventDescription, "Updated locally")
        // Reopening keeps the local edit even though the publisher still has the original.
        await store.send(.task)?.value
        expectNoDifference(store.record, expected)
        await store.dismount()
    }

    @Test(arguments: [false, true])
    func canonicalLinksAndLocationsReplaceCatalogValuesIncludingWhenCleared(cleared: Bool) throws {
        let database = try database()
        var record = try event()
        if !cleared {
            record.links = [try OME.Link(
                url: #require(URL(string: "https://wickedwoods.example/current-tickets")),
                title: "Current tickets"
            )]
            record.locations = [try Event.Location(name: "Current venue")]
        }
        try database.write { try Event.insert { record }.execute($0) }

        var catalog = listing(record)
        catalog.links = [
            CalendarEvent.Link(
                name: "Old tickets",
                uri: try #require(URL(string: "https://wickedwoods.example/old-tickets"))
            )
        ]
        catalog.locations = [.init(name: "Old venue")]
        let detail = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            EventBrowseDetail.State(event: catalog)
        }

        // A cleared canonical value must not bring stale catalog information back.
        expectNoDifference(detail.locationText, cleared ? nil : "Current venue")
        expectNoDifference(detail.links, cleared ? [] : [
            CalendarEvent.Link(
                name: "Current tickets",
                uri: try #require(URL(string: "https://wickedwoods.example/current-tickets"))
            )
        ])
    }

    @Test(arguments: ["offline", "wrong-record", "incomplete-graph"])
    func failedDownloadsLeaveNoPartialRecordsAndCanBeRetried(scenario: String) async throws {
        let database = try database()
        let original = try event()
        let attempts = LockIsolated(0)
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0.getSelectedOAuthSessionID = { nil }
            $0.eventRecords = .init { id in
                expectNoDifference(id, original.id)
                let attempt = attempts.withValue { $0 += 1; return $0 }
                if attempt == 1 {
                    switch scenario {
                    case "offline":
                        throw URLError(.notConnectedToInternet)
                    case "wrong-record":
                        return EventRecordGraph(event: try Event(
                            id: #require(Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcai")),
                            name: "Another event",
                            createdAt: original.createdAt,
                            timeZone: original.timeZone
                        ))
                    default:
                        var incomplete = original
                        incomplete.programs = [
                            try #require(ATProto.URI("at://did:plc:organizer/events.openmusic.program/3mrdbziccpcai"))
                        ]
                        return EventRecordGraph(event: incomplete)
                    }
                }
                return EventRecordGraph(event: original)
            }
        } operation: {
            TestStore(initialState: EventBrowseDetail.State(event: listing(original))) {
                EventBrowseDetail()
            }
        }

        // An unavailable or invalid download must not create an editable partial event.
        await store.send(.task)?.value
        store.expect {
            $0.errorMessage = "Unable to load all event details."
        }
        #expect(store.record == nil)
        let afterFailure = try await database.read { try Event.all.fetchAll($0) }
        expectNoDifference(afterFailure, [])

        // Opening the detail again retries, clears the error, and makes the record editable.
        await store.send(.task) {
            $0.errorMessage = nil
        }?.value
        store.expect {
            $0.record = original
        }
        store.send(.editButtonTapped) {
            $0.eventInfoForm = .init(draft: original, isSaving: false, errorMessage: nil)
        }
        expectNoDifference(attempts.value, 2)
        await store.dismount()
    }

    @Test
    func aRecordSavedWhileDownloadingIsNotOverwritten() async throws {
        let database = try database()
        let original = try event()
        let local: Event = {
            var event = original
            event.name = "A local edit made while loading"
            return event
        }()
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0.getSelectedOAuthSessionID = { nil }
            $0.eventRecords = .init { _ in
                // Another opening of this event finishes and saves before this response arrives.
                try await database.write { try Event.insert { local }.execute($0) }
                return EventRecordGraph(event: original)
            }
        } operation: {
            TestStore(initialState: EventBrowseDetail.State(event: listing(original))) {
                EventBrowseDetail()
            }
        }
        await store.send(.task)?.value
        store.expect {
            $0.record = local
        }
        let saved = try await database.read { try Event.find(original.id).fetchOne($0) }
        expectNoDifference(saved, local)
        await store.dismount()
    }

    @Test(arguments: [false, true])
    func savingDoesNotOverwriteAnUpdatedOrDeletedRecord(deleted: Bool) async throws {
        let database = try database()
        let original = try event()
        try await database.write { try Event.insert { original }.execute($0) }
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 0)
        } operation: {
            TestStore(initialState: EventBrowseDetail.State(event: listing(original))) {
                EventBrowseDetail()
            }
        }
        store.send(.editButtonTapped) {
            $0.eventInfoForm = .init(draft: original, isSaving: false, errorMessage: nil)
        }
        store.modify {
            $0.eventInfoForm?.draft.name = "My edit"
        } changes: {
            $0.eventInfoForm?.draft.name = "My edit"
        }

        let latest: Event = {
            var event = original
            event.name = "Another editor's change"
            return event
        }()
        try await database.write { db in
            if deleted {
                try Event.find(original.id).delete().execute(db)
            } else {
                try Event.upsert { latest }.execute(db)
            }
        }

        await store.send(.eventInfoForm(.saveButtonTapped)) {
            $0.record = deleted ? nil : latest
            $0.eventInfoForm?.errorMessage = deleted
                ? "This event is no longer available."
                : "This event changed while you were editing. Reopen the form to edit the latest version."
        }?.value
        #expect(store.eventInfoForm?.isSaving == false)
        #expect(store.eventInfoForm?.errorMessage != nil)
        let saved = try await database.read { try Event.find(original.id).fetchOne($0) }
        expectNoDifference(saved, deleted ? nil : latest)
        await store.dismount()
    }

    @Test
    func clearingOptionalValuesAndChangingTimeZoneKeepsBoundaryPrecision() throws {
        let event = try event()
        var state = withDependencies {
            $0.date.now = Date(timeIntervalSince1970: 0)
        } operation: {
            EditEventInfo.State(event: event)
        }
        state.draft.description = "  "
        state.draft.status = nil
        state.draft.mode = nil
        state.draft.end = nil
        state.draft.timeZone = try #require(TimeZone(identifier: "Pacific/Auckland"))
        let saved = state.preparedRecord
        #expect(saved.description == nil)
        #expect(saved.status == nil)
        #expect(saved.mode == nil)
        #expect(saved.end == nil)
        expectNoDifference(saved.start, event.start)
        #expect(state.validationMessage == nil)
    }

    @Test
    func invalidNameAndReversedExactTimesCannotBeSaved() throws {
        var state = try withDependencies {
            $0.date.now = Date(timeIntervalSince1970: 0)
        } operation: {
            EditEventInfo.State(event: try event())
        }
        state.draft.name = "  "
        #expect(!state.canSubmit)
        state.draft.name = "Wicked Woods"
        state.draft.end = .known(.time(.init(value: "2026-09-01T00:00:00Z")))
        #expect(!state.canSubmit)
        state.draft.end = .known(.day(.init(value: try #require(LocalDate("2026-09-04")))))
        #expect(state.canSubmit)
    }

    private func database() throws -> DatabaseQueue {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }

    private func event() throws -> Event {
        try Event(
            id: #require(Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")),
            cid: ATProto.CID("bafyreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku"),
            name: "Wicked Woods",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: #require(TimeZone(identifier: "America/Denver")),
            description: "Original description",
            start: .known(.time(.init(value: "2026-09-04T12:34:56.123456789-06:00"))),
            end: .known(.day(.init(value: #require(LocalDate("2026-09-07"))))),
            status: .unknown(.string("extended-status")),
            media: [.unknown(.object(["$type": "events.example.defs#video", "url": "https://example.com/video"]))],
            rsvpExpected: true
        )
    }

    private func listing(_ event: Event) -> CalendarEvent {
        CalendarEvent(
            uri: event.id,
            name: "Stale listing name",
            startsAt: Date(timeIntervalSince1970: 0),
            organizer: .init(id: DID("did:plc:organizer")!),
            source: .init(collection: .init(Event.lexiconID.rawValue))
        )
    }
}
