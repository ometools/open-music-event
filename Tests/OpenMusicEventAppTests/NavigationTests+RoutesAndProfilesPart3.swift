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
    func organizerDetailGroupsDefaultCalendarEntries() async throws {
        let database = try makePreparedDatabase()
        let calendarID = OrganizerDetail.defaultCalendarID(organizerID: testOrganizerID)
        let currentEventID = canonicalRouteRecordID("events.openmusic.event", "3mrdbziccpcba")
        let previousEventID = canonicalRouteRecordID("events.openmusic.event", "3mrdbziccpcbb")
        let previousLaterEventID = canonicalRouteRecordID("events.openmusic.event", "3mrdbziccpcbc")
        let upcomingEventID = canonicalRouteRecordID("events.openmusic.event", "3mrdbziccpcbd")
        let upcomingLaterEventID = canonicalRouteRecordID("events.openmusic.event", "3mrdbziccpcbe")
        let unreferencedEventID = canonicalRouteRecordID("events.openmusic.event", "3mrdbziccpcbf")
        let currentEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("current-event")
        )
        let previousEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("previous-event")
        )
        let previousLaterEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("previous-later-event")
        )
        let upcomingEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("upcoming-event")
        )
        let upcomingLaterEntryID = OMERecord.CalendarEntry.ID(
            calendarOwnerID: testOrganizerID,
            calendarID: OMERecord.Calendar.defaultID,
            entryID: calendarEntryLocalID("upcoming-later-event")
        )
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let today = try #require(LocalDate("2026-05-11"))
        let currentStartDate = try #require(LocalDate("2026-05-10"))
        let currentEndDate = try #require(LocalDate("2026-05-12"))
        let previousStartDate = try #require(LocalDate("2026-05-01"))
        let previousEndDate = try #require(LocalDate("2026-05-03"))
        let previousLaterStartDate = try #require(LocalDate("2026-05-10"))
        let previousLaterEndDate = try #require(LocalDate("2026-05-10"))
        let upcomingStartDate = try #require(LocalDate("2026-06-01"))
        let upcomingEndDate = try #require(LocalDate("2026-06-03"))
        let upcomingLaterStartDate = try #require(LocalDate("2026-06-04"))
        let upcomingLaterEndDate = try #require(LocalDate("2026-06-06"))
        try await database.write { db in
            try Self.insertOrganizer(db, id: testOrganizerID)
            try Self.insertCanonicalEvent(
                db,
                id: currentEventID,
                name: "Current Event",
                startDate: currentStartDate,
                endDate: currentEndDate,
                timeZone: timeZone
            )
            try Self.insertCanonicalEvent(
                db,
                id: previousEventID,
                name: "Previous Event",
                startDate: previousStartDate,
                endDate: previousEndDate,
                timeZone: timeZone
            )
            try Self.insertCanonicalEvent(
                db,
                id: previousLaterEventID,
                name: "Previous Later Event",
                startDate: previousLaterStartDate,
                endDate: previousLaterEndDate,
                timeZone: timeZone
            )
            try Self.insertCanonicalEvent(
                db,
                id: upcomingEventID,
                name: "Upcoming Event",
                startDate: upcomingStartDate,
                endDate: upcomingEndDate,
                timeZone: timeZone
            )
            try Self.insertCanonicalEvent(
                db,
                id: upcomingLaterEventID,
                name: "Upcoming Later Event",
                startDate: upcomingLaterStartDate,
                endDate: upcomingLaterEndDate,
                timeZone: timeZone
            )
            try Self.insertCanonicalEvent(db, id: unreferencedEventID, name: "Unreferenced Event")
            try Self.insertCalendar(db, id: calendarID, name: "Main Calendar")
            try Self.insertCalendarEntry(
                db,
                id: currentEntryID,
                event: OMERecord.Event.Reference(uri: currentEventID),
                createdAt: Date(timeIntervalSince1970: 100)
            )
            try Self.insertCalendarEntry(
                db,
                id: previousEntryID,
                event: OMERecord.Event.Reference(uri: previousEventID),
                createdAt: Date(timeIntervalSince1970: 200)
            )
            try Self.insertCalendarEntry(
                db,
                id: previousLaterEntryID,
                event: OMERecord.Event.Reference(uri: previousLaterEventID),
                createdAt: Date(timeIntervalSince1970: 250)
            )
            try Self.insertCalendarEntry(
                db,
                id: upcomingEntryID,
                event: OMERecord.Event.Reference(uri: upcomingEventID),
                createdAt: Date(timeIntervalSince1970: 300)
            )
            try Self.insertCalendarEntry(
                db,
                id: upcomingLaterEntryID,
                event: OMERecord.Event.Reference(uri: upcomingLaterEventID),
                createdAt: Date(timeIntervalSince1970: 350)
            )
        }
        let entryRows = try await database.read { db in
            CalendarDetail.EntryRows(
                entries: try OrganizerDetail.defaultCalendarEntriesQuery(
                    organizerID: testOrganizerID
                )
                .fetchAll(db),
                events: try CalendarDetail.localEventsQuery.fetchAll(db)
            )
        }
        let sections = OrganizerDetail.CalendarEntrySections(
            entryRows: entryRows,
            now: today.atStartOfDay(in: timeZone)
        )

        #expect(sections.currentRows.map(\.event?.id) == [currentEventID])
        #expect(sections.upcomingRows.map(\.event?.id) == [upcomingEventID, upcomingLaterEventID])
        #expect(sections.previousRows.map(\.event?.id) == [previousLaterEventID, previousEventID])
        #expect(sections.initialSection == .now)
    }

    @Test
    func contributorsViewerFetchesContributorsForEvent() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = canonicalRouteEventID
        let otherEventID = canonicalRouteRecordID(
            "events.openmusic.event", "3mrdbziccpcae"
        )
        let zaraID = canonicalRouteRecordID(
            "events.openmusic.contributor", "3mrdbziccpcae"
        )
        let amyID = canonicalRouteRecordID(
            "events.openmusic.contributor", "3mrdbziccpcaq"
        )
        let otherID = canonicalRouteRecordID(
            "events.openmusic.contributor", "3mrdbziccpcar"
        )
        let createdAt = ATProto.DateTime(rawValue: "2026-09-01T12:00:00Z")
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertCanonicalEvent(db, id: otherEventID, name: "Event Two")
            for (id, event, name) in [
                (zaraID, selectedEventID, "Zara"),
                (amyID, selectedEventID, "Amy"),
                (otherID, otherEventID, "Other"),
            ] {
                let contributor = try Contributor(
                    id: id,
                    event: event,
                    name: name,
                    createdAt: createdAt,
                    subject: nil
                )
                try Contributor.insert { contributor }.execute(db)
            }
        }

        let contributors = try await database.read { db in
            try ContributorsViewer.contributorProfilesQuery(
                eventID: selectedEventID
            ).fetchAll(db)
        }

        #expect(contributors.map(\.name) == ["Amy", "Zara"])
    }



}
