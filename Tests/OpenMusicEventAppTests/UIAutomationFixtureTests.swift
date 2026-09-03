import BlueskyActorCache
import ComposableCalendarEvents
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import HTTPClient
import HTTPTypes
@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing
import XRPCClient

@Suite(.serialized)
@MainActor
struct UIAutomationFixtureTests {
    struct TestivalAttendeeContent: Sendable {
        let installation: InstalledEventRecord?
        let provenance: EventSourceProvenanceRecord?
        let event: OME.Event?
        let stages: [OME.Stage]
        let contributors: [OME.Contributor]
        let schedules: [OME.Schedule]
        let performanceRows: [PerformanceRow]
        let collaborativeSetCredits: [OME.Performance.Contributors]
        let artistTwoPerformances: [PerformanceRow]
        let channels: [OME.Channel]
        let posts: [CommsPost]
        let siteMap: OME.Event.SiteMap?
    }

    @Test
    func `entry waits for fixture preparation only in automation builds`() {
        let ordinaryEntry = withDependencies {
            $0.openMusicEventUIAutomation = false
        } operation: {
            OpenMusicEventApplicationEntryView()
        }
        expectNoDifference(ordinaryEntry.preparation, .ready)

        let automationEntry = withDependencies {
            $0.openMusicEventUIAutomation = true
        } operation: {
            OpenMusicEventApplicationEntryView()
        }
        expectNoDifference(automationEntry.preparation, .preparing)
    }

    @Test
    func `fixture server recognizes the advertised immutable artifact request`() {
        let request = HTTPRequest(
            method: .get,
            url: OpenMusicEventUIAutomationFixture.refreshArtifactURL
        )

        #expect(OpenMusicEventUIAutomationFixture.isRefreshArtifactRequest(request))
    }

    #if !os(Android)
    @Test
    func `fresh attendee imports Testival and can explore its festival program without network access`() async throws {
        let database = try preparedDatabase()

        try await withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            OME.prepareDependencies(
                &$0,
                database: database,
                uiAutomation: true
            )
        } operation: {
            @Dependency(\.date.now) var now
            expectNoDifference(now, OpenMusicEventUIAutomationFixture.now)

            let validation = try await OpenMusicEventUIAutomationFixture.importSource(
                into: database
            )
            let eventID = try #require(validation.insertedEventIDs.only)
            expectNoDifference(
                eventID.eventID.rawValue.rawValue,
                "testival-source-testival-2026"
            )

            // The automation catalog has no network fallback: it projects only
            // source rows already imported into this fresh database.
            @Dependency(\.calendarEvents) var calendarEvents
            let browse = try await calendarEvents.browse(
                CalendarEvent.PageRequest(collection: OME.Event.nsid)
            )
            expectNoDifference(browse.events.map(\.name), ["Testival 2026"])
            expectNoDifference(browse.cursor, nil)

            let browseState = Browse.State(
                events: browse.events,
                referenceDate: now
            )
            expectNoDifference(browseState.happeningNowEvents.map(\.name), ["Testival 2026"])
            expectNoDifference(browseState.upcomingEvents.map(\.name), [])
            expectNoDifference(browseState.pastEvents.map(\.name), [])

            let catalogEvent = try #require(browse.events.only)
            let installedEventID = try await OMEEventInstallationClient.liveValue
                .ensureInstalled(catalogEvent.uri)
            expectNoDifference(installedEventID, eventID)

            let attendeeContent = try await database.read { db in
                let installation = try InstalledEventRecord.find(eventID).fetchOne(db)
                let provenance = try EventSourceProvenanceRecord.find(eventID).fetchOne(db)
                let event = try OME.Event.find(eventID).fetchOne(db)
                let stages = try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
                let contributors = try OME.Contributor
                    .where { $0.id.organizerID.eq(eventID.organizerID) }
                    .where { $0.id.eventID.eq(eventID.eventID) }
                    .order { $0.name.collate(.nocase) }
                    .fetchAll(db)
                let schedules = try ScheduleViewer.schedulesQuery(eventID: eventID).fetchAll(db)
                let performanceRows = try PerformanceRow.all(eventID: eventID).fetchAll(db)
                let collaborativeSetCredits = try OME.Performance.Contributors
                    .where { $0.performanceID.organizerID.eq(eventID.organizerID) }
                    .where { $0.performanceID.eventID.eq(eventID.eventID) }
                    .where {
                        $0.performanceID.performanceID.eq(
                            OME.ID<OME.Performance>(.init("collaborative-set"))
                        )
                    }
                    .order { $0.sortIndex }
                    .fetchAll(db)
                let artistTwoPerformances = try PerformanceRow.forContributor(
                    contributorID: OME.ID<OME.Contributor>(.init("artist-two")),
                    eventID: eventID
                )
                .fetchAll(db)
                let channels = try OME.Channel
                    .where { $0.id.organizerID.eq(eventID.organizerID) }
                    .where { $0.id.eventID.eq(eventID.eventID) }
                    .order { $0.sortIndex.asc(nulls: .last) }
                    .fetchAll(db)
                let posts = try CommsPost
                    .where { $0.id.organizerID.eq(eventID.organizerID) }
                    .where { $0.id.eventID.eq(eventID.eventID) }
                    .order { $0.sortIndex }
                    .fetchAll(db)
                let siteMap = try OME.Event.SiteMap
                    .find(OME.Event.SiteMap.ID(eventID: eventID))
                    .fetchOne(db)
                return TestivalAttendeeContent(
                    installation: installation,
                    provenance: provenance,
                    event: event,
                    stages: stages,
                    contributors: contributors,
                    schedules: schedules,
                    performanceRows: performanceRows,
                    collaborativeSetCredits: collaborativeSetCredits,
                    artistTwoPerformances: artistTwoPerformances,
                    channels: channels,
                    posts: posts,
                    siteMap: siteMap
                )
            }

            // Enter Event persists the installation and retains the stable
            // Tangled-style provenance used to restore the attendee workspace.
            #expect(attendeeContent.installation != nil)
            let provenance = try #require(attendeeContent.provenance)
            expectNoDifference(provenance.sourceKind, .tangled)
            expectNoDifference(
                provenance.sourceReference,
                OpenMusicEventUIAutomationFixture.sourceReference
            )

            // The event carries the location, navigation, support, and reporting
            // information used by Wicked Woods without remote image content.
            let event = try #require(attendeeContent.event)
            expectNoDifference(event.name, "Testival 2026")
            expectNoDifference(
                event.locations?.map(\.address),
                ["1 Fixture Road, Denver, CO 80202"]
            )
            expectNoDifference(event.locations?.first?.coordinates?.latitude, 39.7392)
            expectNoDifference(event.locations?.first?.coordinates?.longitude, -104.9903)
            expectNoDifference(event.uris?.map(\.name), ["Testival Website"])
            expectNoDifference(event.contactNumbers?.map(\.title), ["Event Information"])
            expectNoDifference(event.reportingLinks?.map(\.name), ["Report an Incident"])

            // The fixture has two music stages and a separate workshop division,
            // with curated lineups drawn from four contributor profiles.
            expectNoDifference(
                attendeeContent.stages.map(\.name),
                ["Meadow", "Canopy", "Workshop Grove"]
            )
            expectNoDifference(
                attendeeContent.stages.map { $0.category?.rawValue },
                [nil, nil, "workshop"]
            )
            expectNoDifference(
                attendeeContent.stages.map {
                    ($0.lineup ?? []).map { $0.rawValue.rawValue }
                },
                [
                    ["artist-one", "artist-two"],
                    ["artist-two", "artist-three"],
                    ["facilitator-four"],
                ]
            )
            expectNoDifference(
                attendeeContent.contributors.map(\.name),
                ["Artist One", "Artist Three", "Artist Two", "Facilitator Four"]
            )
            let artistTwo = try #require(
                attendeeContent.contributors.first { $0.name == "Artist Two" }
            )
            expectNoDifference(
                artistTwo.links?.map(\.platform),
                [.spotify, .website]
            )

            // Two days exercise schedule selection, simultaneous stages, workshop
            // filtering, supporting credits, and a performance crossing midnight.
            expectNoDifference(
                attendeeContent.schedules.map(\.customTitle),
                ["Saturday", "Sunday"]
            )
            expectNoDifference(
                attendeeContent.performanceRows.map(\.title),
                [
                    "Movement Workshop",
                    "Opening Set",
                    "Sunset Session",
                    "Collaborative Set",
                    "Late Night Set",
                    "Morning Set",
                    "Closing Set",
                ]
            )
            expectNoDifference(
                attendeeContent.performanceRows.map { $0.id.performanceID.rawValue.rawValue },
                [
                    "movement-workshop",
                    "opening-set",
                    "sunset-session",
                    "collaborative-set",
                    "late-night-set",
                    "morning-set",
                    "closing-set",
                ]
            )
            let timingStatuses: [PerformanceTimingStatus?] =
                attendeeContent.performanceRows.map { row in
                    PerformanceTimingStatus(
                        startTime: row.performance.startTime,
                        endTime: row.performance.endTime,
                        now: now
                    )
                }
            let expectedTimingStatuses: [PerformanceTimingStatus?] = [
                .nowPlaying,
                .nowPlaying,
                .startsIn(15 * 60),
                .startsIn((1 * 60 + 45) * 60),
                .startsIn((5 * 60 + 15) * 60),
                .startsIn((15 * 60 + 45) * 60),
                .startsIn((24 * 60 + 45) * 60),
            ]
            expectNoDifference(timingStatuses, expectedTimingStatuses)
            let lateNightSet = try #require(
                attendeeContent.performanceRows.first { $0.title == "Late Night Set" }
            )
            expectNoDifference(
                lateNightSet.performance.endTime.timeIntervalSince(
                    lateNightSet.performance.startTime
                ),
                90 * 60
            )
            expectNoDifference(
                attendeeContent.collaborativeSetCredits.map { $0.contributorID?.rawValue.rawValue },
                ["artist-one", "artist-two"]
            )
            expectNoDifference(
                attendeeContent.collaborativeSetCredits.map(\.billing),
                [.primary, .supporting]
            )
            expectNoDifference(
                attendeeContent.collaborativeSetCredits.map { $0.role?.rawValue },
                ["musician", "visual-artist"]
            )
            expectNoDifference(
                attendeeContent.artistTwoPerformances.map(\.title),
                ["Sunset Session", "Collaborative Set", "Morning Set"]
            )

            // The attendee schedule projection resolves Saturday first and exposes
            // the same schedule/workshop divisions as the production viewer.
            let selectedScheduleID = ScheduleViewer.resolvedSelectedScheduleID(
                nil,
                schedules: attendeeContent.schedules
            )
            expectNoDifference(selectedScheduleID?.rawValue.rawValue, "saturday")
            expectNoDifference(
                ScheduleViewer.scheduleDivisions(stages: attendeeContent.stages).map(\.id),
                ["schedule", "workshop"]
            )
            let musicStages = ScheduleViewer.visibleStages(
                stages: attendeeContent.stages,
                division: .schedule
            )
            let workshopStages = ScheduleViewer.visibleStages(
                stages: attendeeContent.stages,
                division: ScheduleViewer.ScheduleDivision(
                    category: OME.Stage.Category("workshop")
                )
            )
            expectNoDifference(musicStages.map(\.name), ["Meadow", "Canopy"])
            expectNoDifference(workshopStages.map(\.name), ["Workshop Grove"])
            expectNoDifference(
                ScheduleViewer.currentTimeDestination(
                    currentDate: now,
                    selectedScheduleID: selectedScheduleID,
                    schedules: attendeeContent.schedules,
                    performanceRows: attendeeContent.performanceRows,
                    stages: musicStages,
                    buffer: 30 * 60
                )?.performanceID.rawValue.rawValue,
                "opening-set"
            )
            expectNoDifference(
                ScheduleViewer.visiblePerformances(
                    performanceRows: attendeeContent.performanceRows,
                    scheduleID: selectedScheduleID,
                    stages: musicStages
                )
                .map(\.title),
                ["Opening Set", "Sunset Session", "Collaborative Set", "Late Night Set"]
            )
            expectNoDifference(
                ScheduleViewer.visiblePerformances(
                    performanceRows: attendeeContent.performanceRows,
                    scheduleID: selectedScheduleID,
                    stages: workshopStages
                )
                .map(\.title),
                ["Movement Workshop"]
            )

            // Communications and the multi-style map cross the same source import
            // and local-image materialization boundaries as Wicked Woods.
            expectNoDifference(attendeeContent.channels.map(\.name), ["General", "Safety"])
            expectNoDifference(
                attendeeContent.channels.map(\.notificationsRequired),
                [false, true]
            )
            expectNoDifference(attendeeContent.posts.map(\.title), ["Welcome to Testival"])
            expectNoDifference(attendeeContent.posts.map(\.isPinned), [true])
            let siteMap = try #require(attendeeContent.siteMap)
            expectNoDifference(siteMap.title, "Testival Grounds")
            expectNoDifference(siteMap.defaultStyleID?.rawValue.rawValue, "public")
            expectNoDifference(siteMap.styles.map(\.title), ["Public", "Safety"])
            let mapURLs = try siteMap.styles.map { style in
                try #require(style.image.url)
            }
            #expect(mapURLs.allSatisfy { $0.isFileURL })
            #expect(mapURLs.allSatisfy { $0.pathExtension.lowercased() == "png" })
            let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            let mapSignatures = try mapURLs.map {
                try Data(contentsOf: $0).prefix(pngSignature.count)
            }
            #expect(mapSignatures.allSatisfy { Data($0) == pngSignature })

            // Restoring the installed event exercises the same provenance-to-
            // workspace resolution used immediately after Enter Event.
            let restoredRoot = OpenMusicEventAppRoot.State(
                selectedEventIDAtLaunch: installedEventID
            )
            let workspaceID = try #require(
                restoredRoot.destination?.eventViewer?.authoring.context.id
            )
            expectNoDifference(workspaceID, try #require(provenance.workspace?.id))
        }
    }

    @Test
    func `installed attendee receives a published Testival revision without losing personal state`() async throws {
        let database = try preparedDatabase()
        let requests = LockIsolated<[HTTPRequest]>([])

        try await withDependencies {
            $0.context = .test
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            OME.prepareDependencies(
                &$0,
                database: database,
                uiAutomation: true
            )
            $0.requestInterceptors = []
            $0.uuid = .incrementing
            $0.httpClient = .liveValue
            $0[XRPC.Client.self] = .liveValue
            let serverResponses = $0.dataForURL
            $0.dataForURL = { request, body in
                requests.withValue { $0.append(request) }
                return try await serverResponses(request, body)
            }
        } operation: {
            // Revision A crosses the normal validator and becomes the attendee's installed event.
            let validation = try await OpenMusicEventUIAutomationFixture.importSource(
                into: database
            )
            let eventID = try #require(validation.insertedEventIDs.only)
            expectNoDifference(eventID, OpenMusicEventUIAutomationFixture.eventID)
            let eventURI = OME.Event.reference(id: eventID).uri
            let installedEventID = try await OMEEventInstallationClient.liveValue
                .ensureInstalled(eventURI)
            expectNoDifference(installedEventID, eventID)

            // The attendee owns these rows. Published source replacement may update schedules and
            // posts, but it must not reset notification choices, read state, or personal schedules.
            let generalChannelID = OME.Channel.ID(
                organizerID: eventID.organizerID,
                eventID: eventID.eventID,
                channelID: OME.ID<OME.Channel>(rawValue: "general")
            )
            let welcomePostID = CommsPost.ID(
                organizerID: eventID.organizerID,
                eventID: eventID.eventID,
                channelID: generalChannelID.channelID,
                postID: CommsPost.PostID("welcome")
            )
            let personalSchedule = UserSchedule(
                id: try #require(
                    UUID(uuidString: "00000000-0000-0000-0000-000000000026")
                ),
                eventID: eventID,
                title: "My Saturday"
            )
            let collaborativeSetMembership = UserSchedule.Performance(
                scheduleID: personalSchedule.id,
                performanceID: OME.ID<OME.Performance>(rawValue: "collaborative-set")
            )
            let viewerState = EventViewerState(
                id: eventID,
                selectedScheduleID: OME.ID<OME.Schedule>(rawValue: "saturday"),
                selectedUserScheduleID: personalSchedule.id,
                didInitializeUserSchedules: true
            )
            try await database.write { db in
                try ChannelPreferences.insert {
                    ChannelPreferences(
                        id: generalChannelID,
                        notificationState: .unsubscribed
                    )
                }
                .execute(db)
                try CommsPostRead.insert { CommsPostRead(id: welcomePostID) }.execute(db)
                try UserSchedule.insert { personalSchedule }.execute(db)
                try UserSchedule.Performance.insert { collaborativeSetMembership }.execute(db)
                try EventViewerState.insert { viewerState }.execute(db)
            }

            // The same XRPC query used in production receives the complete AppView projection.
            let advertisedEvent = try await CalendarEventsClient.openMusicEvent(eventURI)
            let advertisedSource = advertisedEvent.source
            expectNoDifference(advertisedSource.appViewHost, "openmusicevent.app")
            expectNoDifference(
                advertisedSource.sourceRecord,
                OME.SourceRecord(
                    kind: .tangled,
                    reference: OpenMusicEventUIAutomationFixture.sourceReference,
                    ref: OpenMusicEventUIAutomationFixture.refreshRevision
                )
            )
            expectNoDifference(
                advertisedSource.resolvedArtifact,
                OME.CalendarEvent.Source.Artifact(
                    url: OpenMusicEventUIAutomationFixture.refreshArtifactURL,
                    revision: OpenMusicEventUIAutomationFixture.refreshRevision,
                    checksumSHA256: OpenMusicEventUIAutomationFixture.refreshArtifactSHA256,
                    byteCount: OpenMusicEventUIAutomationFixture.refreshArtifactByteCount
                )
            )
            expectNoDifference(
                advertisedSource.resolvedRepository,
                OME.CalendarEvent.Source.Repository(
                    reference: OpenMusicEventUIAutomationFixture.refreshArtifactRepository,
                    ref: OpenMusicEventUIAutomationFixture.refreshRevision
                )
            )

            // Resume synchronization downloads and verifies the advertised archive, validates the
            // requested event, then atomically replaces only its published source-owned rows.
            try await OMEEventInstallationClient.liveValue.synchronizeInstalledEvent(eventID)

            let refreshed = try await database.read { db in
                (
                    installation: try InstalledEventRecord.find(eventID).fetchOne(db),
                    provenance: try EventSourceProvenanceRecord.find(eventID).fetchOne(db),
                    performances: try PerformanceRow.all(eventID: eventID).fetchAll(db),
                    posts: try CommsPost
                        .where { $0.id.organizerID.eq(eventID.organizerID) }
                        .where { $0.id.eventID.eq(eventID.eventID) }
                        .fetchAll(db),
                    preference: try ChannelPreferences.find(generalChannelID).fetchOne(db),
                    reads: try CommsPostRead.fetchAll(db),
                    personalSchedule: try UserSchedule.find(personalSchedule.id).fetchOne(db),
                    memberships: try UserSchedule.Performance.fetchAll(db),
                    viewerState: try EventViewerStateRequest(eventID: eventID).fetch(db)
                )
            }

            expectNoDifference(
                refreshed.performances.map(\.title),
                [
                    "Movement Workshop",
                    "Opening Set",
                    "Sunset Session",
                    "Collaborative Set — Updated",
                    "Surprise Set",
                    "Late Night Set",
                    "Morning Set",
                    "Closing Set",
                ]
            )
            expectNoDifference(
                Set(refreshed.posts.map(\.title)),
                ["Saturday Schedule Updated", "Welcome to Testival"]
            )
            expectNoDifference(
                refreshed.preference,
                ChannelPreferences(
                    id: generalChannelID,
                    notificationState: .unsubscribed
                )
            )
            expectNoDifference(refreshed.reads.map(\.id), [welcomePostID])
            expectNoDifference(refreshed.personalSchedule, personalSchedule)
            expectNoDifference(refreshed.memberships, [collaborativeSetMembership])
            expectNoDifference(refreshed.viewerState, viewerState)
            expectNoDifference(
                refreshed.provenance?.ref,
                OpenMusicEventUIAutomationFixture.refreshRevision
            )
            // The imported provenance records the immutable revision we fetched, while the
            // attendee's installation stays anchored to the canonical authoring branch.
            expectNoDifference(
                refreshed.installation?.ref,
                OpenMusicEventUIAutomationFixture.sourceRef
            )
        }

        let observedRequests = requests.value
        expectNoDifference(observedRequests.map(\.method), [.get, .get, .get])
        expectNoDifference(
            observedRequests.compactMap(\.url).map(\.path),
            [
                OpenMusicEventUIAutomationFixture.calendarEventPath,
                OpenMusicEventUIAutomationFixture.calendarEventPath,
                OpenMusicEventUIAutomationFixture.refreshArtifactURL.path,
            ]
        )
        expectNoDifference(
            observedRequests.compactMap(\.url).last,
            OpenMusicEventUIAutomationFixture.refreshArtifactURL
        )
    }

    func preparedDatabase() throws -> any DatabaseWriter {
        let database = try SQLiteData.defaultDatabase()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        BlueskyActorCacheMigrations.register(into: &migrator)
        OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        return database
    }
    #endif
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
