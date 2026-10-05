import ATProto
import ATProtoTypes
import ComposableArchitecture2
import ComposableCalendarEvents
import CustomDump
import ConcurrencyExtras
import Dependencies
import DependenciesTestSupport
import DebugSnapshots
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSourceEditing
import Observation
import SQLiteData
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import Testing

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer

@MainActor
struct CanonicalEventEditingTests {
    typealias Event = OpenMusicEventLexicon.Event

    @Test(arguments: [false, true])
    func signedOutReaderRefreshesPublishedContentWithoutOverwritingImportedEdits(imported: Bool) async throws {
        let database = try database()
        let original = try event()
        var updated = original
        updated.cid = localImageBlob(Data("new record".utf8), mimeType: .png).ref
        updated.description = "Image B and updated description"
        updated.media = [.known(.image(.init(
            source: .known(.blob(localImageBlob(Data("image B".utf8), mimeType: .png))),
            alt: "Image B", role: .known(.hero)
        )))]
        let latest = updated
        try latest.validateReferences()
        try await database.write { db in
            try Event.insert { original }.execute(db)
            if imported {
                try #sql("""
                    INSERT INTO canonicalSourceEventIdentities
                    (id, source, directory, publisher, createdAt)
                    VALUES (\(original.id), '/fixture', 'testival', 'did:plc:organizer', \(original.createdAt))
                    """).execute(db)
            }
        }
        let refreshed = LockIsolated(false)
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.getSelectedOAuthSessionID = { nil }
            var client = EventRecordClient { _ in throw ValidationError("A cached reader needs no graph download") }
            client.latestEvent = { id in
                expectNoDifference(id, original.id)
                refreshed.setValue(true)
                return latest
            }
            $0.eventRecords = client
        } operation: {
            TestStore(initialState: EventBrowseDetail.State(event: CalendarEvent(
                uri: original.id, cid: latest.cid, name: original.name, startsAt: nil,
                organizer: .init(id: DID("did:plc:organizer")!),
                source: .init(collection: .init(Event.lexiconID.rawValue))
            ))) { EventBrowseDetail() }
        }
        await store.send(.task)?.value
        if !imported { store.expect { $0.record = latest } }
        #expect(refreshed.value == !imported)
        expectNoDifference(store.eventDescription, imported ? original.description : latest.description)
        let saved = try await database.read { try Event.find(original.id).fetchOne($0) }
        expectNoDifference(saved, imported ? original : latest)
        await store.dismount()
    }

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
            $0.uuid = .incrementing
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
            $0.eventInfoForm?.draft.rsvpExpected = false
        } changes: {
            $0.eventInfoForm?.draft.name = "  Wicked Woods 2026  "
            $0.eventInfoForm?.draft.description = "  Updated locally  "
            $0.eventInfoForm?.draft.rsvpExpected = false
        }
        var expected = event
        expected.name = "Wicked Woods 2026"
        expected.description = "Updated locally"
        expected.rsvpExpected = false
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

    @Test
    func locationEditorUpdatesCanonicalLocationsWithoutOverwritingOtherEventFields() async throws {
        let database = try database()
        var record = try event()
        var address = Event.Address(country: "US")
        address.street = "Old Road"
        var location = Event.Location(name: "Main Gate")
        location.description = "Old arrival instructions"
        location.locators = [.known(.address(address))]
        location.links = [OME.Link(url: try #require(URL(string: "https://example.org/old-map")))]
        record.locations = [location]
        let originalRecord = record
        try await database.write { try Event.insert { originalRecord }.execute($0) }
        let recordID = record.id

        @Bindable var store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EditLocation.State(eventID: record.id)) { EditLocation() }
        }
        #expect(store.hasLoadedDraft)
        #expect(store.locations.count == 1)
        $store.locations[0].name.wrappedValue = "  North Gate  "
        $store.locations[0].description.wrappedValue = "  Follow the signs.  "
        $store.locations[0].locators[0].street.wrappedValue = "Forest Road"
        let locationID = store.locations[0].id
        await store.send(.addLocatorButtonTapped(locationID, .geo))?.value
        $store.locations[0].locators[1].latitude.wrappedValue = "39.0"
        $store.locations[0].locators[1].longitude.wrappedValue = "-105.0"
        let oldLinkID = store.locations[0].links[0].id
        await store.send(.removeLinkButtonTapped(locationID, oldLinkID))?.value
        await store.send(.addLinkButtonTapped(locationID))?.value
        $store.locations[0].links[0].title.wrappedValue = "Map"
        $store.locations[0].links[0].url.wrappedValue = "https://example.org/new-map"
        $store.locations[0].links[0].roleChoice.wrappedValue = "contact"
        $store.locations[0].links[0].useChoice.wrappedValue = "emergency"
        $store.locations[0].links[0].platformRawValue.wrappedValue = ExternalPlatform.website.rawValue

        try await database.write { db in
            var latest = try #require(try Event.find(recordID).fetchOne(db))
            latest.name = "Renamed while editing"
            try Event.upsert { latest }.execute(db)
        }
        await store.send(.saveButtonTapped)?.value

        let saved = try await database.read { try #require(try Event.find(recordID).fetchOne($0)) }
        #expect(saved.name == "Renamed while editing")
        #expect(saved.locations?.count == 1)
        #expect(saved.locations?[0].name == "North Gate")
        #expect(saved.locations?[0].description == "Follow the signs.")
        #expect(saved.locations?[0].links?.first?.url.absoluteString == "https://example.org/new-map")
        #expect(saved.locations?[0].links?.first?.role == .known(.contact(.init(use: .known(.emergency)))))
        #expect(saved.locations?[0].links?.first?.platform == .known(.website))
        let savedLocators = try #require(saved.locations?.first?.locators)
        if let first = savedLocators.first,
           case let .known(.address(savedAddress)) = first {
            #expect(savedAddress.country == "US")
            #expect(savedAddress.street == "Forest Road")
        } else {
            Issue.record("Address locator was lost")
        }
        if let last = savedLocators.last,
           case let .known(.geo(savedGeo)) = last {
            #expect(savedGeo.latitude == "39.0")
            #expect(savedGeo.longitude == "-105.0")
        } else {
            Issue.record("Coordinate locator was lost")
        }
    }

    @Test
    func locationEditorRejectsIncompleteRowsBeforeWriting() async throws {
        let database = try database()
        let record = try event()
        try await database.write { try Event.insert { record }.execute($0) }

        @Bindable var store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EditLocation.State(eventID: record.id)) { EditLocation() }
        }
        await store.send(.addLocationButtonTapped)?.value
        #expect(!store.canSubmit)
        $store.locations[0].name.wrappedValue = "Camp"
        let locationID = store.locations[0].id
        await store.send(.addLocatorButtonTapped(locationID, .geo))?.value
        $store.locations[0].locators[0].latitude.wrappedValue = "91"
        $store.locations[0].locators[0].longitude.wrappedValue = "-105"
        #expect(!store.canSubmit)
        await store.send(.saveButtonTapped)?.value
        let unchanged = try await database.read { try #require(try Event.find(record.id).fetchOne($0)) }
        #expect(unchanged.locations == nil)

        $store.locations[0].locators[0].latitude.wrappedValue = "39"
        #expect(store.canSubmit)
    }

    @Test
    func locationRowActionsPreserveOrderAndUnknownLocator() async throws {
        let database = try database()
        var record = try event()
        let unknownLocator: Open<Event.Locator> = .unknown(.object([
            "$type": "events.example.defs#arrivalPoint",
            "gate": "north",
        ]))
        var address = Event.Address(country: "US")
        address.street = "Forest Road"
        var campground = Event.Location(name: "Campground")
        campground.locators = [
            .known(.address(address)),
            unknownLocator,
        ]
        campground.links = [
            OME.Link(url: try #require(URL(string: "https://example.com/arrival")), title: "Arrival"),
            OME.Link(url: try #require(URL(string: "https://example.com/camping")), title: "Camping"),
        ]
        record.locations = [campground, Event.Location(name: "Main Gate"), Event.Location(name: "Old Gate")]
        let originalRecord = record
        let recordID = record.id
        try await database.write { try Event.insert { originalRecord }.execute($0) }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EditLocation.State(eventID: recordID)) { EditLocation() }
        }
        let campgroundID = store.locations[0].id
        let mainGateID = store.locations[1].id
        let oldGateID = store.locations[2].id
        let unknownLocatorID = store.locations[0].locators[1].id
        let campingLinkID = store.locations[0].links[1].id

        await store.send(.editLocationButtonTapped(campgroundID))?.value
        #expect(store.editingLocationID == campgroundID)
        await store.send(.editLocatorButtonTapped(campgroundID, unknownLocatorID))?.value
        #expect(store.editingLocatorID == unknownLocatorID)
        await store.send(.moveLocatorButtonTapped(campgroundID, unknownLocatorID, -1))?.value
        await store.send(.moveLinkButtonTapped(campgroundID, campingLinkID, -1))?.value
        await store.send(.moveLocationButtonTapped(mainGateID, -1))?.value
        await store.send(.removeLocationButtonTapped(oldGateID))?.value
        await store.send(.saveButtonTapped)?.value

        let saved = try await database.read { try #require(try Event.find(recordID).fetchOne($0)) }
        #expect(saved.locations?.map(\.name) == ["Main Gate", "Campground"])
        #expect(saved.locations?[1].locators?.first == unknownLocator)
        #expect(saved.locations?[1].links?.map(\.title) == ["Camping", "Arrival"])
    }

    @Test
    func creatingScheduleStoresCanonicalRecordAndUpdatesEventOrder() async throws {
        let database = try database()
        let record = try event()
        try await database.write { try Event.insert { record }.execute($0) }
        let now = try Date("2026-09-02T18:00:00Z", strategy: .iso8601)
        let day = try #require(LocalDate("2026-09-05"))
        @Bindable var store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.date.now = now
        } operation: {
            Store(initialState: ScheduleForm.State(
                eventID: record.id, initialDate: day, timeZone: record.timeZone
            )) { ScheduleForm() }
        }
        $store.customTitle.wrappedValue = "  Saturday Music  "
        await store.send(.saveButtonTapped)?.value

        let savedEvent = try await database.read { try #require(try Event.find(record.id).fetchOne($0)) }
        let schedules = try await database.read { try Schedule.all.fetchAll($0) }
        let savedSchedule = try #require(schedules.first)
        #expect(schedules.count == 1)
        #expect(savedSchedule.event == record.id)
        #expect(savedSchedule.date == day)
        #expect(savedSchedule.title == "Saturday Music")
        #expect(savedEvent.schedules == [savedSchedule.id])
        #expect(savedEvent.name == record.name)
        try savedSchedule.validateReferences()
    }

    @Test
    func editingAndDeletingScheduleKeepsTheEventGraphConsistent() async throws {
        let database = try database()
        let record = try event()
        let originalDay = try #require(LocalDate("2026-09-05"))
        let revisedDay = try #require(LocalDate("2026-09-06"))
        let createdAt = ATProto.DateTime(rawValue: "2026-09-01T12:00:00Z")
        let scheduleID = try CanonicalRecordID.next(
            collection: Schedule.lexiconID,
            in: record.id.authority,
            at: try Date("2026-09-01T12:00:00Z", strategy: .iso8601),
            clockID: 1
        )
        let schedule = try Schedule(
            id: scheduleID,
            event: record.id,
            date: originalDay,
            createdAt: createdAt,
            title: "Saturday"
        )
        var eventWithSchedule = record
        eventWithSchedule.schedules = [scheduleID]
        let originalEventWithSchedule = eventWithSchedule
        try await database.write { db in
            try Event.insert { originalEventWithSchedule }.execute(db)
            try Schedule.insert { schedule }.execute(db)
        }

        @Bindable var store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.date = .constant(Date(timeIntervalSince1970: 0))
        } operation: {
            Store(initialState: ScheduleForm.State(
                schedule: schedule,
                timeZone: record.timeZone
            )) { ScheduleForm() }
        }
        #expect(store.customTitle == "Saturday")
        $store.customTitle.wrappedValue = "  Sunday Music  "
        $store.dateSelection.wrappedValue = revisedDay.atStartOfDay(in: record.timeZone)
        await store.send(.saveButtonTapped)?.value

        let saved = try await database.read { try #require(try Schedule.find(scheduleID).fetchOne($0)) }
        let savedEvent = try await database.read { try #require(try Event.find(record.id).fetchOne($0)) }
        #expect(saved.id == scheduleID)
        #expect(saved.createdAt == createdAt)
        #expect(saved.date == revisedDay)
        #expect(saved.title == "Sunday Music")
        #expect(savedEvent.schedules == [scheduleID])
        let scheduleCount = try await database.read { try Schedule.all.fetchAll($0).count }
        #expect(scheduleCount == 1)

        let deleteStore = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: ScheduleForm.State(
                schedule: saved,
                timeZone: record.timeZone
            )) { ScheduleForm() }
        }
        await deleteStore.send(.deleteButtonTapped)?.value
        let eventAfterDelete = try await database.read { try #require(try Event.find(record.id).fetchOne($0)) }
        let deletedSchedule = try await database.read { try Schedule.find(scheduleID).fetchOne($0) }
        #expect(deletedSchedule == nil)
        #expect(eventAfterDelete.schedules == nil)
    }

    @Test
    func deletingAnAssignedSchedulePreservesTheDayAndItsProgramItem() async throws {
        let database = try database()
        var record = try event()
        let scheduleID = try #require(Schedule.ID(
            "at://did:plc:organizer/events.openmusic.schedule/3mrdbziccpcaj"
        ))
        let schedule = try Schedule(
            id: scheduleID,
            event: record.id,
            date: try #require(LocalDate("2026-09-05")),
            createdAt: "2026-09-01T12:00:00Z"
        )
        record.schedules = [scheduleID]
        let originalEventWithSchedule = record
        let item = try ProgramItem(
            id: #require(ATProto.URI(
                "at://did:plc:organizer/events.openmusic.programItem/3mrdbziccpcak"
            )),
            event: record.id,
            program: #require(ATProto.URI(
                "at://did:plc:organizer/events.openmusic.program/3mrdbziccpcal"
            )),
            title: "Main stage set",
            createdAt: "2026-09-01T12:00:00Z",
            schedule: scheduleID
        )
        try await database.write { db in
            try Event.insert { originalEventWithSchedule }.execute(db)
            try Schedule.insert { schedule }.execute(db)
            try ProgramItem.insert { item }.execute(db)
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: ScheduleForm.State(
                schedule: schedule,
                timeZone: record.timeZone
            )) { ScheduleForm() }
        }
        await store.send(.deleteButtonTapped)?.value

        #expect(store.errorMessage == "Move or delete scheduled items before deleting this schedule.")
        let savedSchedule = try await database.read { try Schedule.find(scheduleID).fetchOne($0) }
        let savedItem = try await database.read { try ProgramItem.find(item.id).fetchOne($0) }
        let savedEvent = try await database.read {
            try #require(try Event.find(originalEventWithSchedule.id).fetchOne($0))
        }
        #expect(savedSchedule == schedule)
        #expect(savedItem == item)
        #expect(savedEvent.schedules == [scheduleID])
    }

    @Test(arguments: [false, true])
    func canonicalMediaReplacesCatalogArtworkIncludingWhenCleared(cleared: Bool) throws {
        let database = try database()
        var record = try event()
        let posterURL = try #require(URL(string: "https://wickedwoods.example/current-poster.png"))
        let heroURL = try #require(URL(string: "https://wickedwoods.example/current-hero.png"))
        let iconURL = try #require(URL(string: "https://wickedwoods.example/current-icon.png"))
        if cleared {
            record.media = []
        } else {
            record.media = [
                .known(.image(.init(source: .known(.url(iconURL)), role: .known(.icon(.init()))))),
                .known(.image(.init(source: .known(.url(heroURL)), role: .known(.hero)))),
                .known(.image(.init(source: .known(.url(posterURL)), role: .known(.poster)))),
            ]
        }
        try database.write { try Event.insert { record }.execute($0) }

        var catalog = listing(record)
        catalog.media = [
            .init(
                url: try #require(URL(string: "https://wickedwoods.example/stale-poster.png")),
                role: "poster"
            )
        ]
        let detail = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            EventBrowseDetail.State(event: catalog)
        }

        expectNoDifference(
            detail.artworkSources.map(\.image.url),
            cleared ? [] : [posterURL, heroURL, iconURL]
        )
        expectNoDifference(
            detail.artworkSources.map(\.kind),
            cleared ? [] : [.primaryImage, .primaryImage, .logo]
        )
        #expect(detail.artworkTitleSources.containsLogo == !cleared)
    }

    @Test(arguments: ["offline", "wrong-record", "incomplete-graph"])
    func failedDownloadsLeaveNoPartialRecordsAndCanBeRetried(scenario: String) async throws {
        let database = try database()
        let original = try event()
        let attempts = LockIsolated(0)
        let store = withDependencies {
            $0.defaultDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0.uuid = .incrementing
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
            $0.uuid = .incrementing
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
            $0.uuid = .incrementing
        } operation: {
            EventForm.State(event: event)
        }
        state.draft.description = "  "
        state.draft.status = nil
        state.draft.mode = nil
        state.draft.rsvpExpected = nil
        state.draft.end = nil
        state.draft.timeZone = try #require(TimeZone(identifier: "Pacific/Auckland"))
        let saved = state.preparedRecord
        #expect(saved.description == nil)
        #expect(saved.status == nil)
        #expect(saved.mode == nil)
        #expect(saved.rsvpExpected == nil)
        #expect(saved.end == nil)
        expectNoDifference(saved.start, event.start)
        #expect(state.validationMessage == nil)
    }

    @Test
    func invalidNameAndReversedExactTimesCannotBeSaved() throws {
        var state = try withDependencies {
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0.uuid = .incrementing
        } operation: {
            EventForm.State(event: try event())
        }
        state.draft.name = "  "
        #expect(!state.canSubmit)
        state.draft.name = "Wicked Woods"
        state.draft.end = .known(.time(.init(value: "2026-09-01T00:00:00Z")))
        #expect(!state.canSubmit)
        state.draft.end = .known(.day(.init(value: try #require(LocalDate("2026-09-04")))))
        #expect(state.canSubmit)
    }

    @Test
    func eventLinksEditAndReorderWithoutLosingUnknownPurpose() async throws {
        var event = try event()
        let unknownRole: Open<OME.Link.Role> = .unknown(.object([
            "$type": "events.example.defs#pressLink",
            "audience": "press",
        ]))
        event.links = [
            OME.Link(
                url: try #require(URL(string: "https://example.com/press")),
                title: "Press",
                description: "Original notes",
                role: unknownRole
            ),
            OME.Link(
                url: try #require(URL(string: "https://example.com/tickets")),
                title: "Tickets",
                role: .known(.tickets(.init()))
            ),
            OME.Link(url: try #require(URL(string: "https://example.com/retired")), title: "Retired"),
        ]
        let store = withDependencies {
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0.uuid = .incrementing
        } operation: {
            TestStore(initialState: EventForm.State(event: event)) { EventForm() }
        }
        let pressID = store.state.links[0].id
        let ticketID = store.state.links[1].id
        let retiredID = store.state.links[2].id

        await store.send(.editLinkButtonTapped(pressID))?.value
        store.modify {
            $0.links[0].title = "Press Kit"
            $0.links[0].description = ""
        }
        await store.send(.moveLinkButtonTapped(ticketID, -1))?.value
        await store.send(.removeLinkButtonTapped(retiredID))?.value

        #expect(store.state.canSubmit)
        let saved = try #require(store.state.preparedRecord.links)
        #expect(saved.map(\.title) == ["Tickets", "Press Kit"])
        #expect(saved[1].description == nil)
        #expect(saved[1].role == unknownRole)
        #expect(saved[0].role == .known(.tickets(.init())))
        #expect(store.state.preparedRecord.media == event.media)
    }

    @Test
    func incompleteEventLinkCannotBeSaved() async throws {
        let store = try withDependencies {
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0.uuid = .incrementing
        } operation: {
            TestStore(initialState: EventForm.State(event: try event())) { EventForm() }
        }
        await store.send(.addLinkButtonTapped)?.value
        #expect(!store.state.canSubmit)
        store.modify { $0.links[0].url = "https://example.com" }
        #expect(store.state.canSubmit)
    }

    @Test
    func eventMediaRowsCanBeAddedReorderedEditedAndDeleted() async throws {
        let database = try database()
        let original = try event()
        try await database.write { db in
            try Event.upsert { original }.execute(db)
        }
        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0.uuid = .incrementing
        } operation: {
            TestStore(initialState: EventForm.State(event: original)) { EventForm() }
        }

        await store.send(.addExternalMediaButtonTapped)?.value
        store.modify {
            $0.mediaDraft?.uri = "https://example.com/event-stream"
            $0.mediaDraft?.title = "Event Stream"
        }
        await store.send(.mediaDraftSaveButtonTapped)?.value
        await store.send(.addRecordMediaButtonTapped)?.value
        store.modify {
            $0.mediaDraft?.uri = "at://did:plc:organizer/app.bsky.feed.post/3mrdbziccpcy"
        }
        await store.send(.mediaDraftSaveButtonTapped)?.value
        let recordRowID = try #require(store.state.mediaEntries.last?.id)
        await store.send(.mediaMoveButtonTapped(recordRowID, -1))?.value
        await store.send(.mediaMoveButtonTapped(recordRowID, -1))?.value
        await store.send(.saveButtonTapped)?.value
        try await waitForEventFormDismissal(store)

        let saved = try await database.read { db in
            try #require(try Event.find(original.id).fetchOne(db))
        }
        guard let savedMedia = saved.media, savedMedia.count == 3,
              case .known(.record) = savedMedia[0],
              case .unknown = savedMedia[1] else {
            Issue.record("Expected record media before the preserved unknown media")
            return
        }

        let reopened = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0.uuid = .incrementing
        } operation: {
            TestStore(initialState: EventForm.State(event: saved)) { EventForm() }
        }
        guard reopened.state.mediaEntries.count == 3 else {
            Issue.record("Expected three media rows on reopen")
            return
        }
        await reopened.send(.mediaDeleteButtonTapped(reopened.state.mediaEntries[0].id))?.value
        await reopened.send(.mediaEditButtonTapped(reopened.state.mediaEntries[1].id))?.value
        reopened.modify { $0.mediaDraft?.title = "Updated Event Stream" }
        await reopened.send(.mediaDraftSaveButtonTapped)?.value
        await reopened.send(.saveButtonTapped)?.value
        try await waitForEventFormDismissal(reopened)

        let updated = try await database.read { db in
            try #require(try Event.find(original.id).fetchOne(db))
        }
        #expect(updated.media?.count == 2)
        guard case .some(.unknown) = updated.media?.first,
              case let .some(.known(.external(external))) = updated.media?.last else {
            Issue.record("Expected preserved unknown and edited external media")
            return
        }
        #expect(external.title == "Updated Event Stream")
    }

    @Test
    func siteMapEditorUpdatesCanonicalStylesAndDefaultWithoutReplacingOtherEventFields() async throws {
        let database = try database()
        var record = try event()
        record.siteMap = Event.SiteMap(
            title: "Grounds",
            styles: [
                .init(id: "public", title: "Public", image: OME.Image(
                    source: .known(.url(try #require(URL(string: "https://example.com/public.png")))),
                    role: .known(.siteMap)
                )),
                .init(id: "safety", title: "Safety", image: OME.Image(
                    source: .known(.url(try #require(URL(string: "https://example.com/safety.png")))),
                    role: .known(.siteMap)
                )),
            ],
            defaultStyleID: "public"
        )
        let originalRecord = record
        let eventID = originalRecord.id
        try await database.write { try Event.insert { originalRecord }.execute($0) }

        // The map's Edit action opens a draft of the installed canonical record.
        let viewer = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: SiteMapViewer.State(eventID: record.id)) { SiteMapViewer() }
        }
        await viewer.send(.editButtonTapped)?.value
        #expect(viewer.destination?.editSiteMap?.title == "Grounds")

        @Bindable var editor = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.uuid = .constant(UUID(2))
        } operation: {
            Store(initialState: EditSiteMap.State(event: record)) { EditSiteMap() }
        }

        // Rename and reorder the existing styles without changing their stable IDs.
        $editor.title.wrappedValue = "  Wicked Woods Grounds  "
        await editor.send(.moveStyleButtonTapped("safety", -1))?.value
        await editor.send(.editStyleButtonTapped("safety"))?.value
        $editor.styles[0].title.wrappedValue = "  Emergency  "
        $editor.styles[0].sourceURLString.wrappedValue = "https://example.com/emergency.png"
        $editor.defaultStyleID.wrappedValue = "safety"

        // A new row must have an image before the editor will save it.
        await editor.send(.addStyleButtonTapped)?.value
        #expect(!editor.canSubmit)
        $editor.styles[2].title.wrappedValue = "Parking"
        $editor.styles[2].sourceURLString.wrappedValue = "http://example.com/parking.png"
        #expect(!editor.canSubmit)
        $editor.styles[2].sourceURLString.wrappedValue = "https://example.com/parking.png"
        #expect(editor.canSubmit)

        // An unrelated rename made while editing survives the map save.
        try await database.write { db in
            var latest = try #require(try Event.find(eventID).fetchOne(db))
            latest.name = "Wicked Woods Renamed"
            try Event.upsert { latest }.execute(db)
        }
        await editor.send(.saveButtonTapped)?.value

        let saved = try await database.read { try #require(try Event.find(eventID).fetchOne($0)) }
        #expect(saved.name == "Wicked Woods Renamed")
        #expect(saved.description == record.description)
        #expect(saved.siteMap?.title == "Wicked Woods Grounds")
        #expect(saved.siteMap?.styles.map(\.id) == ["safety", "public", UUID(2).uuidString.lowercased()])
        #expect(saved.siteMap?.styles.map(\.title) == ["Emergency", "Public", "Parking"])
        #expect(saved.siteMap?.defaultStyleID == "safety")
        #expect(saved.siteMap?.defaultStyle?.image.displayImageAsset(recordID: record.id)?.url
                == URL(string: "https://example.com/emergency.png"))
    }

    @Test
    func siteMapEditorRemovesMapFromCanonicalEvent() async throws {
        let database = try database()
        var record = try event()
        record.siteMap = Event.SiteMap(
            title: "Grounds",
            styles: [.init(id: "public", title: "Public", image: OME.Image(
                source: .known(.url(try #require(URL(string: "https://example.com/map.png")))),
                role: .known(.siteMap)
            ))]
        )
        let originalRecord = record
        let eventID = originalRecord.id
        try await database.write { try Event.insert { originalRecord }.execute($0) }
        let editor = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EditSiteMap.State(event: record)) { EditSiteMap() }
        }

        await editor.send(.removeMapButtonTapped)?.value
        #expect(editor.canSubmit)
        await editor.send(.saveButtonTapped)?.value

        let saved = try await database.read { try #require(try Event.find(eventID).fetchOne($0)) }
        #expect(saved.siteMap == nil)
        #expect(saved.name == record.name)
        #expect(saved.media == record.media)
    }

    private func waitForEventFormDismissal(_ store: TestStore<EventForm>) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while store.isPresented && clock.now < deadline {
            try await clock.sleep(for: .milliseconds(5))
        }
        #expect(!store.isPresented)
        #expect(!store.state.isSaving)
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
