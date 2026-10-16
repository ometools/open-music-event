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
            try ContributorList.contributorProfilesQuery(
                eventID: selectedEventID
            ).fetchAll(db)
        }

        #expect(contributors.map(\.name) == ["Amy", "Zara"])
    }



}
