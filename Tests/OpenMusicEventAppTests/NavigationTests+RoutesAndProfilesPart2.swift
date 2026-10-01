import Bluesky
import ATProto
import Clocks
import ComposableArchitecture2
import ComposableNotifications
import CustomDump
import Dependencies
import DependenciesTestSupport
import DebugSnapshots
import Foundation
import IssueReporting
import Observation
import OpenMusicEventDatabase
import OpenMusicEventAuthentication
import OpenMusicEventImages
import OpenMusicEventLexicon
import OpenMusicEventSource
import OpenMusicEventSourceEditing
import OpenMusicEventWhiteLabel
import Sharing
import SQLiteData
import SourceEditing
#if os(Android)
import SkipSwiftUI
#elseif canImport(SwiftUI)
import SwiftUI
#endif
import Testing
import ATProto

@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
@testable import OpenMusicEventEditors

extension NavigationTests {
    @Test
    func organizerDetailFetchesCalendarsForOrganizer() async throws {
        let database = try makePreparedDatabase()
        let otherOrganizerID = try #require(OMERecord.Organizer.ID("did:web:other.example"))
        let defaultCalendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let sideCalendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: calendarLocalID("side-room")
        )
        let otherCalendarID = OMERecord.Calendar.ID(
            ownerID: otherOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertOrganizer(db, id: otherOrganizerID)
            try Self.insertCalendar(db, id: sideCalendarID, name: "Side Room")
            try Self.insertCalendar(db, id: defaultCalendarID, name: "Main Calendar")
            try Self.insertCalendar(db, id: otherCalendarID, name: "Other Calendar")
        }

        let calendars = try await database.read { db in
            try OrganizerDetail.calendarsQuery(organizerID: testOrganizerID).fetchAll(db)
        }

        #expect(calendars.map(\.id) == [defaultCalendarID, sideCalendarID])
    }

    @Test
    func calendarDetailResolvesEntriesWithLocalEvents() async throws {
        let database = try makePreparedDatabase()
        let calendarID = OMERecord.Calendar.ID(
            ownerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID
        )
        let firstEventID = canonicalRouteRecordID("events.openmusic.event", "3mrdbziccpcba")
        let pinnedEventID = canonicalRouteRecordID("events.openmusic.event", "3mrdbziccpcbb")
        let firstEventDate = try #require(LocalDate("2026-06-01"))
        let pinnedEventDate = try #require(LocalDate("2026-05-01"))
        let firstEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("first-entry")
        )
        let pinnedEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("pinned-entry")
        )
        let unavailableEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("unavailable-entry")
        )
        let unavailableEventRef = OMERecord.Event.Reference(
            uri: canonicalRouteRecordID("events.openmusic.event", "3mrdbziccpcbc")
        )

        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertCanonicalEvent(
                db,
                id: firstEventID,
                name: "First Event",
                startDate: firstEventDate
            )
            try Self.insertCanonicalEvent(
                db,
                id: pinnedEventID,
                name: "Pinned Event",
                startDate: pinnedEventDate
            )
            try Self.insertCalendar(db, id: calendarID, name: "Main Calendar")
            try Self.insertCalendarEntry(
                db,
                id: firstEntryID,
                event: OMERecord.Event.Reference(uri: firstEventID),
                createdAt: Date(timeIntervalSince1970: 100)
            )
            try Self.insertCalendarEntry(
                db,
                id: unavailableEntryID,
                event: unavailableEventRef,
                createdAt: Date(timeIntervalSince1970: 200)
            )
            try Self.insertCalendarEntry(
                db,
                id: pinnedEntryID,
                event: OMERecord.Event.Reference(uri: pinnedEventID),
                createdAt: Date(timeIntervalSince1970: 50),
                note: "Pinned pick",
                pinned: true
            )
        }

        let rows = try await database.read { db in
            CalendarDetail.EntryRows(
                entries: try CalendarDetail.entriesQuery(calendarID: calendarID).fetchAll(db),
                events: try CalendarDetail.localEventsQuery.fetchAll(db)
            )
        }

        #expect(rows.rows.map(\.entry.id) == [pinnedEntryID, firstEntryID, unavailableEntryID])
        #expect(rows.rows.map(\.event?.id) == [pinnedEventID, firstEventID, nil])
        #expect(rows.rows.first?.entry.note == "Pinned pick")
    }


}
