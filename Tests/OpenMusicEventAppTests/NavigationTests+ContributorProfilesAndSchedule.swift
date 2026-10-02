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
    func contributorProfileKeepsExplicitContributorFieldsAheadOfCachedBlueskyProfileData() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = canonicalRouteEventID
        let actor = try #require(DID("did:plc:alice123"))
        let contributorID = canonicalRouteRecordID(
            "events.openmusic.contributor", "3mrdbziccpcaj"
        )
        let createdAt = ATProto.DateTime(rawValue: "2026-08-01T12:00:00Z")
        let explicitImageURL = try #require(URL(string: "https://example.com/explicit.jpg"))
        let event = try Event(
            id: selectedEventID,
            name: "Event One",
            createdAt: createdAt,
            timeZone: .gmt
        )
        var contributor = try Contributor(
            id: contributorID,
            event: selectedEventID,
            name: "Explicit Alice",
            createdAt: createdAt,
            subject: actor
        )
        contributor.description = "OME bio"
        contributor.media = [.known(.image(OME.Image(
            source: .known(.url(explicitImageURL)),
            role: .known(.photo)
        )))]
        let savedContributor = contributor
        let profile = BlueskyActorProfile(
            did: actor.description,
            handle: "alice.bsky.social",
            displayName: "Bluesky Alice",
            description: "Bluesky bio",
            avatar: URL(string: "https://cdn.example/alice-avatar.jpg")
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
        let contributorProfile = row.profile

        #expect(contributorProfile.contributorActor == actor)
        #expect(!contributorProfile.usesActorProfileAsPrimary)
        #expect(contributorProfile.name == "Explicit Alice")
        #expect(contributorProfile.handle == "alice.bsky.social")
        #expect(contributorProfile.subtitle == "@alice.bsky.social")
        #expect(contributorProfile.bio == "OME bio")
        #expect(contributorProfile.artworkDisplayImage?.url == explicitImageURL)
        #expect(contributorProfile.artworkDisplayImage?.recordID != nil)
        #expect(row.matchesSearch("Explicit Alice"))
        #expect(row.matchesSearch("alice.bsky.social"))
        #expect(!row.matchesSearch("Bluesky Alice"))
    }

    @Test
    func contributorsViewerRefreshesTheCanonicalContributorsSubjectProfile() async throws {
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
        let contributor = try Contributor(
            id: contributorID,
            event: selectedEventID,
            name: "Alice at Wicked Woods",
            createdAt: createdAt,
            subject: actor
        )
        let profile = BlueskyActorProfile(
            did: actor.description,
            handle: "alice.bsky.social",
            displayName: "Alice Example",
            description: "ATProto builder",
            avatar: URL(string: "https://cdn.example/alice-avatar.jpg")
        )
        let requestRecorder = BlueskyProfileRequestRecorder()

        try await database.write { db in
            try Event.insert { event }.execute(db)
            try Contributor.insert { contributor }.execute(db)
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
            $0.blueskyActorProfileCache = BlueskyActorProfileCacheClient(
                cachedProfile: { _ in nil },
                refreshProfile: { requestedActor in
                    await requestRecorder.record(requestedActor)
                    return profile
                },
                refreshProfileIfNeeded: { requestedActor, _, _ in
                    await requestRecorder.record(requestedActor)
                    try await database.write { db in
                        try BlueskyActorProfile.insert { profile }
                            .execute(db)
                        try BlueskyActorProfileCacheEntry.insert {
                            BlueskyActorProfileCacheEntry(
                                actor: requestedActor,
                                did: profile.did,
                                lastFetchedAt: Date(timeIntervalSince1970: 1_000),
                                lastFetchAttemptAt: Date(timeIntervalSince1970: 1_000)
                            )
                        }
                        .execute(db)
                    }
                    return profile
                }
            )
        } operation: {
            Store(initialState: ContributorList.State(eventID: selectedEventID)) {
                ContributorList()
            }
        }

        try await waitForContributorListBlueskyProfile(in: store, contributorID: contributorID)

        #expect(await requestRecorder.actors == [actor.description])
        let row = try #require(store.contributorRows.first { $0.contributorID == contributorID })
        #expect(row.profile.name == "Alice at Wicked Woods")
        #expect(row.profile.subtitle == "@alice.bsky.social")
        #expect(row.profile.artworkDisplayImage?.url?.absoluteString == "https://cdn.example/alice-avatar.jpg")
    }

    @Test
    func eventPlaceListFetchesCanonicalStagePlacesInOrder() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = canonicalRouteEventID
        let otherEventID = canonicalRouteRecordID(
            "events.openmusic.event", "3mrdbziccpcba"
        )
        let lateID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcbb"
        )
        let mainID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcbc"
        )
        let otherID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcbd"
        )
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertCanonicalEvent(db, id: otherEventID, name: "Event Two")
            try Self.insertCanonicalStage(
                db, id: lateID, eventID: selectedEventID, name: "Late", sortIndex: 2
            )
            try Self.insertCanonicalStage(
                db, id: mainID, eventID: selectedEventID, name: "Main", sortIndex: 1
            )
            try Self.insertCanonicalStage(
                db, id: otherID, eventID: otherEventID, name: "Other"
            )
        }

        let stages = withDependencies {
            $0.defaultDatabase = database
        } operation: {
            EventPlaceList.State(eventID: selectedEventID).stages
        }
        expectNoDifference(stages.map { $0.id }, [mainID, lateID])
        expectNoDifference(stages.map { $0.name }, ["Main", "Late"])
    }

    @Test
    func stageDetailFetchesOnlyItsCanonicalEventPlace() async throws {
        let database = try makePreparedDatabase()
        let selectedEventID = canonicalRouteEventID
        let otherEventID = canonicalRouteRecordID(
            "events.openmusic.event", "3mrdbziccpcba"
        )
        let selectedPlaceID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcbb"
        )
        let otherPlaceID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcbc"
        )
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: selectedEventID, name: "Event One")
            try Self.insertCanonicalEvent(db, id: otherEventID, name: "Event Two")
            try Self.insertCanonicalStage(
                db, id: selectedPlaceID, eventID: selectedEventID, name: "Main"
            )
            try Self.insertCanonicalStage(
                db, id: otherPlaceID, eventID: otherEventID, name: "Other Main"
            )
        }

        let stage = try await database.read { db in
            try EventPlaceDetail.stageQuery(
                stageID: selectedPlaceID,
                eventID: selectedEventID
            ).fetchOne(db)
        }
        expectNoDifference(stage?.name, "Main")
        let wrongEvent = try await database.read { db in
            try EventPlaceDetail.stageQuery(
                stageID: selectedPlaceID,
                eventID: otherEventID
            ).fetchOne(db)
        }
        #expect(wrongEvent == nil)
    }

    @Test
    func stageDetailFiltersCanonicalProgramItemsToSelectedFestivalDay() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let meadowID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcbb"
        )
        let forestID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcbc"
        )
        let fridayID = canonicalRouteRecordID(
            "events.openmusic.schedule", "3mrdbziccpcbd"
        )
        let saturdayID = canonicalRouteRecordID(
            "events.openmusic.schedule", "3mrdbziccpcbe"
        )
        let programID = canonicalRouteRecordID(
            "events.openmusic.program", "3mrdbziccpcbf"
        )
        let friday = try #require(LocalDate("2026-08-07"))
        let saturday = try #require(LocalDate("2026-08-08"))
        let timeZone = TimeZone.gmt
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(db, id: meadowID, eventID: eventID, name: "Meadow")
            try Self.insertCanonicalStage(db, id: forestID, eventID: eventID, name: "Forest")
            try Self.insertCanonicalSchedule(
                db, id: fridayID, eventID: eventID, date: friday
            )
            try Self.insertCanonicalSchedule(
                db, id: saturdayID, eventID: eventID, date: saturday
            )
            try Self.insertCanonicalProgram(
                db, id: programID, eventID: eventID,
                eventPlaces: [meadowID, forestID]
            )
            try Self.insertCanonicalProgramItem(
                db,
                id: canonicalRouteRecordID(
                    "events.openmusic.programItem", "3mrdbziccpcbg"
                ),
                eventID: eventID,
                programID: programID,
                scheduleID: fridayID,
                placeID: meadowID,
                title: "Meadow Friday",
                startsAt: try #require(friday.at(hour: 18, in: timeZone)),
                endsAt: try #require(friday.at(hour: 19, in: timeZone))
            )
            try Self.insertCanonicalProgramItem(
                db,
                id: canonicalRouteRecordID(
                    "events.openmusic.programItem", "3mrdbziccpcbh"
                ),
                eventID: eventID,
                programID: programID,
                scheduleID: fridayID,
                placeID: forestID,
                title: "Forest Friday",
                startsAt: try #require(friday.at(hour: 18, in: timeZone)),
                endsAt: try #require(friday.at(hour: 19, in: timeZone))
            )
            try Self.insertCanonicalProgramItem(
                db,
                id: canonicalRouteRecordID(
                    "events.openmusic.programItem", "3mrdbziccpcbi"
                ),
                eventID: eventID,
                programID: programID,
                scheduleID: saturdayID,
                placeID: meadowID,
                title: "Meadow Saturday",
                startsAt: try #require(saturday.at(hour: 18, in: timeZone)),
                endsAt: try #require(saturday.at(hour: 19, in: timeZone))
            )
        }

        var state = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            EventPlaceDetail.State(stageID: meadowID, eventID: eventID)
        }
        state.eventViewerState.selectedScheduleID = fridayID
        expectNoDifference(state.resolvedSelectedScheduleID, fridayID)
        expectNoDifference(
            state.selectedSchedulePerformances.map { $0.title },
            ["Meadow Friday"]
        )

        state.eventViewerState.selectedScheduleID = saturdayID
        expectNoDifference(
            state.selectedSchedulePerformances.map { $0.title },
            ["Meadow Saturday"]
        )
        state.eventViewerState.selectedScheduleID = canonicalRouteRecordID(
            "events.openmusic.schedule", "3mrdbziccpcbj"
        )
        expectNoDifference(state.resolvedSelectedScheduleID, fridayID)
    }

    @Test
    func stageDetailOpensCanonicalProgramItem() async throws {
        let database = try makePreparedDatabase()
        let eventID = canonicalRouteEventID
        let meadowID = canonicalRouteRecordID(
            "events.openmusic.eventPlace", "3mrdbziccpcbb"
        )
        let fridayID = canonicalRouteRecordID(
            "events.openmusic.schedule", "3mrdbziccpcbd"
        )
        let programID = canonicalRouteRecordID(
            "events.openmusic.program", "3mrdbziccpcbf"
        )
        let itemID = canonicalRouteRecordID(
            "events.openmusic.programItem", "3mrdbziccpcbg"
        )
        let friday = try #require(LocalDate("2026-08-07"))
        let timeZone = TimeZone.gmt
        try await database.write { db in
            try Self.insertCanonicalEvent(db, id: eventID, name: "Event One")
            try Self.insertCanonicalStage(db, id: meadowID, eventID: eventID, name: "Meadow")
            try Self.insertCanonicalSchedule(
                db, id: fridayID, eventID: eventID, date: friday
            )
            try Self.insertCanonicalProgram(
                db, id: programID, eventID: eventID, eventPlaces: [meadowID]
            )
            try Self.insertCanonicalProgramItem(
                db, id: itemID, eventID: eventID, programID: programID,
                scheduleID: fridayID, placeID: meadowID, title: "Meadow Friday",
                startsAt: try #require(friday.at(hour: 18, in: timeZone)),
                endsAt: try #require(friday.at(hour: 19, in: timeZone))
            )
        }

        let store = withDependencies {
            $0.context = .test
            $0.defaultDatabase = database
        } operation: {
            Store(initialState: EventPlaceDetail.State(stageID: meadowID, eventID: eventID)) {
                EventPlaceDetail()
            }
        }
        await store.send(.performanceButtonTapped(itemID))?.value
        expectNoDifference(
            store.destination?.performanceDetail?.performanceID,
            itemID
        )
        expectNoDifference(
            store.destination?.performanceDetail?.eventID,
            eventID
        )
    }

}
