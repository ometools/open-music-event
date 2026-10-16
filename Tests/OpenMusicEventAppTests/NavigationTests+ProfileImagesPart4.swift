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
    func contributorProfileUsesCanonicalSubjectForCachedBlueskyDetails() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = canonicalRouteEventID
        let actor = try #require(DID("did:plc:alice123"))
        let contributorID = canonicalRouteRecordID(
            "events.openmusic.contributor", "3mrdbziccpcaj"
        )
        let createdAt = ATProto.DateTime(rawValue: "2026-08-01T12:00:00Z")
        let event = try Event(
            id: selectedEventID,
            name: "Event One",
            createdAt: createdAt,
            timeZone: .gmt
        )
        var contributor = try Contributor(
            id: contributorID,
            event: selectedEventID,
            name: "Alice at Wicked Woods",
            createdAt: createdAt,
            subject: actor
        )
        contributor.description = "Festival bio"
        let savedContributor = contributor
        let profile = BlueskyActorProfile(
            did: actor.description,
            handle: "alice.bsky.social",
            displayName: "Alice Example",
            description: "ATProto builder",
            avatar: URL(string: "https://cdn.example/alice-avatar.jpg"),
            banner: URL(string: "https://cdn.example/alice-banner.jpg")
        )

        try await database.write { db in
            try Event.insert { event }.execute(db)
            try Contributor.insert { savedContributor }.execute(db)
            try BlueskyActorProfile.insert { profile }.execute(db)
        }

        let row = try await database.read { db in
            try #require(
                ContributorList.contributorRowsQuery(
                    eventID: selectedEventID,
                    hydration: .bskyActorProfile
                )
                    .fetchAll(db)
                    .first { $0.contributorID == contributorID }
            )
        }
        let contributorProfile = row

        #expect(contributorProfile.subject == actor)
        #expect(contributorProfile.name == "Alice at Wicked Woods")
        #expect(contributorProfile.handle == "alice.bsky.social")
        #expect(contributorProfile.subtitle == "@alice.bsky.social")
        #expect(contributorProfile.artworkDisplayImage?.url?.absoluteString == "https://cdn.example/alice-avatar.jpg")
        #expect(contributorProfile.artworkDisplayImage?.recordID == nil)
        let matchesAliceatWickedWoods = try await database.read { db in
            try ContributorListRequest(eventID: selectedEventID, search: "Alice at Wicked Woods").fetch(db)
        }
        #expect(matchesAliceatWickedWoods.contains { $0.id == contributorID })
        let matchesalicebskysocial = try await database.read { db in
            try ContributorListRequest(eventID: selectedEventID, search: "alice.bsky.social").fetch(db)
        }
        #expect(matchesalicebskysocial.contains { $0.id == contributorID })
        let matchesAliceExample = try await database.read { db in
            try ContributorListRequest(eventID: selectedEventID, search: "Alice Example").fetch(db)
        }
        #expect(matchesAliceExample.isEmpty)
    }

}
