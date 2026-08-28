import BlueskyActorCache
import ComposableCalendarEvents
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

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
