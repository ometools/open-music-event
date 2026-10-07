import Bluesky
import ComposableCalendarEvents
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import IssueReporting
@testable import OpenMusicEventApp
@testable import OpenMusicEventAppEventViewer
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing
import ATProto

@Suite(.serialized)
@MainActor
struct UIAutomationFixtureTests {
    @Test
    func `entry waits for fixture preparation only in automation builds`() {
        let ordinaryEntry = withDependencies {
            $0.openMusicEventUIAutomation = .normal
        } operation: {
            OpenMusicEventApplicationEntryView()
        }
        expectNoDifference(ordinaryEntry.preparation, .ready)

        let automationEntry = withDependencies {
            $0.openMusicEventUIAutomation = .attendee
        } operation: {
            OpenMusicEventApplicationEntryView()
        }
        expectNoDifference(automationEntry.preparation, .preparing)
    }

    #if !os(Android)
    @Test
    func `canonical Testival records support browse install and relaunch without a network fetch`() async throws {
        let database = try preparedDatabase()

        try await withDependencies {
            $0.context = .test
            $0.date = .constant(OpenMusicEventUIAutomationFixture.now)
            OME.prepareDependencies(&$0, database: database, uiAutomation: .attendee)
        } operation: {
            try await OpenMusicEventUIAutomationFixture.prepareCanonicalRecords(into: database)

            @Dependency(\.calendarEvents) var calendarEvents
            let page = try await calendarEvents.browse(
                CalendarEvent.PageRequest(collection: ATProto.NSID(Event.lexiconID.rawValue))
            )
            #expect(page.events.map(\.name) == ["Testival 2026"])
            #expect(page.events.map(\.uri) == [OpenMusicEventUIAutomationFixture.canonicalEventID])
            #expect(page.cursor == nil)
            let browseDetail = EventBrowseDetail.State(event: try #require(page.events.first))
            #expect(browseDetail.dateText == "August 1 – 2, 2026")

            let graph = try await database.read { db in
                let fetched = try EventRecordGraph.fetch(
                    eventID: OpenMusicEventUIAutomationFixture.canonicalEventID,
                    from: db
                )
                return try #require(fetched)
            }
            try graph.validate()
            #expect(graph.programs.map(\.title) == ["Schedule", "Workshops"])
            #expect(graph.schedules.map(\.title) == ["Saturday", "Sunday"])
            #expect(Set(graph.places.map(\.name)) == ["Meadow", "Canopy", "Workshop Grove"])
            #expect(graph.contributors.count == 4)
            #expect(graph.items.count == 7)
            #expect(graph.categories.map(\.name) == ["General", "Safety"])
            #expect(graph.event.locations?.map(\.name) == ["1 Fixture Road, Denver, CO 80202"])
            #expect(graph.event.links?.map(\.title) == [
                "Testival Website", "Event Information", "Report an Incident",
            ])
            let mapStyles = try #require(graph.event.siteMap?.styles)
            #expect(mapStyles.map(\.id) == ["public", "safety"])
            let mapBlobs = mapStyles.compactMap { style -> ATProto.Blob? in
                guard case let .known(.blob(blob)) = style.image.source else { return nil }
                return blob
            }
            #expect(mapBlobs.count == 2)
            for blob in mapBlobs {
                let localURL = try #require(try stagedLocalImageBlobURL(for: blob))
                let bytes = try Data(contentsOf: localURL)
                #expect(bytes.starts(with: [0x89, 0x50, 0x4e, 0x47]))
            }
            let meadow = try #require(graph.places.first { $0.id == OpenMusicEventUIAutomationFixture.canonicalMeadowID })
            let canopy = try #require(graph.places.first { $0.id == OpenMusicEventUIAutomationFixture.canonicalCanopyID })
            let workshopGrove = try #require(graph.places.first { $0.id == OpenMusicEventUIAutomationFixture.canonicalWorkshopGroveID })
            guard case let .some(.known(.stage(meadowStage))) = meadow.kind,
                  case let .some(.known(.stage(canopyStage))) = canopy.kind,
                  case let .some(.known(.stage(workshopStage))) = workshopGrove.kind
            else {
                Issue.record("Testival's three places must render as stages")
                return
            }
            #expect(meadowStage.lineup == [
                OpenMusicEventUIAutomationFixture.canonicalArtistOneID,
                OpenMusicEventUIAutomationFixture.canonicalArtistTwoID,
            ])
            #expect(canopyStage.lineup == [
                OpenMusicEventUIAutomationFixture.canonicalArtistTwoID,
                OpenMusicEventUIAutomationFixture.canonicalArtistThreeID,
            ])
            let artistTwoStageContext = ContributorStageContext(
                contributorID: OpenMusicEventUIAutomationFixture.canonicalArtistTwoID,
                scheduledStages: [canopy, meadow],
                stages: []
            )
            #expect(artistTwoStageContext.primaryStage?.id == meadow.id)
            #expect(workshopStage.category == "workshop")
            #expect(workshopStage.lineup == [OpenMusicEventUIAutomationFixture.canonicalFacilitatorFourID])
            let artistTwo = try #require(graph.contributors.first { $0.id == OpenMusicEventUIAutomationFixture.canonicalArtistTwoID })
            #expect(artistTwo.links?.map(\.platform) == [.known(.spotify), .known(.website)])
            let saturdayItems = graph.items.filter { $0.schedule == OpenMusicEventUIAutomationFixture.canonicalSaturdayID }
            #expect(Set(saturdayItems.map(\.title)) == [
                "Movement Workshop", "Opening Set", "Sunset Session", "Collaborative Set", "Late Night Set",
            ])
            let sundayItems = graph.items.filter { $0.schedule == OpenMusicEventUIAutomationFixture.canonicalSundayID }
            #expect(Set(sundayItems.map(\.title)) == ["Morning Set", "Closing Set"])
            let collaborativeSet = try #require(graph.items.first { $0.id == OpenMusicEventUIAutomationFixture.canonicalCollaborativeSetID })
            #expect(collaborativeSet.credits?.map(\.contributor) == [
                OpenMusicEventUIAutomationFixture.canonicalArtistOneID,
                OpenMusicEventUIAutomationFixture.canonicalArtistTwoID,
            ])
            #expect(collaborativeSet.credits?.map(\.billing) == [.known(.primary), .known(.supporting)])
            let lateNightSet = try #require(graph.items.first { $0.id == OpenMusicEventUIAutomationFixture.canonicalLateNightSetID })
            let lateNightStart = try #require(lateNightSet.startDate)
            let lateNightEnd = try #require(lateNightSet.endDate)
            #expect(lateNightEnd.timeIntervalSince(lateNightStart) == 90 * 60)
            let general = try #require(graph.categories.first { $0.id == OpenMusicEventUIAutomationFixture.canonicalGeneralCategoryID })
            let safety = try #require(graph.categories.first { $0.id == OpenMusicEventUIAutomationFixture.canonicalSafetyCategoryID })
            #expect(general.pinnedPosts == [OpenMusicEventUIAutomationFixture.canonicalWelcomePostID])
            #expect(general.notificationsRequired == false)
            #expect(safety.notificationsRequired == true)
            let siteMap = try #require(graph.event.siteMap)
            #expect(siteMap.title == "Testival Grounds")
            #expect(siteMap.defaultStyleID == "public")
            #expect(siteMap.styles.map(\.title) == ["Public", "Safety"])
            let performanceRows = try await database.read { db in
                try PerformanceRow.all(eventID: graph.event.id).fetchAll(db)
            }
            let divisions = ScheduleList.scheduleDivisions(event: graph.event, programs: graph.programs)
            #expect(divisions.compactMap(\.programID) == graph.event.programs ?? [])
            let musicDivision = try #require(divisions.first)
            let workshopDivision = try #require(divisions.last)
            let musicStages = ScheduleList.visibleStages(stages: graph.places, division: musicDivision)
            #expect(!ScheduleList.State(eventID: graph.event.id).showStageNameLabels)
            let workshopStages = ScheduleList.visibleStages(
                stages: graph.places,
                division: workshopDivision
            )
            #expect(musicStages.map(\.name) == ["Meadow", "Canopy"])
            #expect(workshopStages.map(\.name) == ["Workshop Grove"])
            let saturdayID = OpenMusicEventUIAutomationFixture.canonicalSaturdayID
            #expect(ScheduleList.visiblePerformances(
                performanceRows: performanceRows,
                scheduleID: saturdayID,
                division: musicDivision
            ).map(\.title) == ["Opening Set", "Sunset Session", "Collaborative Set", "Late Night Set"])
            #expect(ScheduleList.visiblePerformances(
                performanceRows: performanceRows,
                scheduleID: saturdayID,
                division: workshopDivision
            ).map(\.title) == ["Movement Workshop"])
            #expect(ScheduleList.currentTimeDestination(
                currentDate: OpenMusicEventUIAutomationFixture.now,
                selectedScheduleID: saturdayID,
                schedules: graph.schedules,
                performanceRows: performanceRows,
                division: musicDivision,
                buffer: 30 * 60
            )?.performanceID == OpenMusicEventUIAutomationFixture.canonicalOpeningSetID)

            // A cached graph installs through the production installer without downloading it.
            @Dependency(\.eventRecords) var client
            let installedID = try await client.install(graph.event.id)
            #expect(installedID == graph.event.id)
            let saved = try await database.read { db in
                (
                    installation: try InstalledEvent.find(installedID).fetchOne(db),
                    posts: try Social.Post.all.fetchAll(db)
                )
            }
            #expect(saved.installation == InstalledEvent(id: installedID))
            #expect(saved.posts.map(\.title) == ["Welcome to Testival"])

            let reopened = OpenMusicEventAppRoot.State(selectedEventIDAtLaunch: installedID)
            #expect(reopened.destination?.eventViewer?.eventID == installedID)

            try await database.write { db in
                var edited = try #require(try Event.find(installedID).fetchOne(db))
                edited.name = "My local Testival name"
                let saved = edited
                try Event.upsert { saved }.execute(db)
            }
            try await OpenMusicEventUIAutomationFixture.prepareCanonicalRecords(into: database)
            let localName = try await database.read { db in
                try Event.find(installedID).fetchOne(db)?.name
            }
            #expect(localName == "My local Testival name")
        }
    }

    @Test
    func `canonical event edits leave attendee choices and read state intact`() async throws {
        let database = try preparedDatabase()

        try await withDependencies {
            $0.context = .test
            OME.prepareDependencies(&$0, database: database, uiAutomation: .attendee)
        } operation: {
            try await OpenMusicEventUIAutomationFixture.prepareCanonicalRecords(into: database)
            let eventID = OpenMusicEventUIAutomationFixture.canonicalEventID
            @Dependency(\.eventRecords) var client
            _ = try await client.install(eventID)

            let personalSchedule = UserSchedule(
                id: try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000026")),
                eventID: eventID,
                title: "My Saturday"
            )
            let membership = UserSchedule.Performance(
                scheduleID: personalSchedule.id,
                performanceID: OpenMusicEventUIAutomationFixture.canonicalCollaborativeSetID
            )
            let viewerState = EventDetailState(
                id: eventID,
                selectedScheduleID: OpenMusicEventUIAutomationFixture.canonicalSaturdayID,
                selectedUserScheduleID: personalSchedule.id,
                didInitializeUserSchedules: true
            )
            let preference = ChannelPreferences(
                id: OpenMusicEventUIAutomationFixture.canonicalGeneralCategoryID,
                notificationState: .unsubscribed
            )
            let read = CommsPostRead(id: OpenMusicEventUIAutomationFixture.canonicalWelcomePostID)
            try await database.write { db in
                try UserSchedule.insert { personalSchedule }.execute(db)
                try UserSchedule.Performance.insert { membership }.execute(db)
                try EventDetailState.insert { viewerState }.execute(db)
                try ChannelPreferences.insert { preference }.execute(db)
                try CommsPostRead.insert { read }.execute(db)
            }

            try await database.write { db in
                var revised = try #require(
                    try ProgramItem.find(OpenMusicEventUIAutomationFixture.canonicalCollaborativeSetID)
                        .fetchOne(db)
                )
                revised.title = "Collaborative Set — Updated"
                let published = revised
                try ProgramItem.upsert { published }.execute(db)
            }

            let saved = try await database.read { db in
                (
                    item: try ProgramItem.find(OpenMusicEventUIAutomationFixture.canonicalCollaborativeSetID)
                        .fetchOne(db),
                    schedule: try UserSchedule.find(personalSchedule.id).fetchOne(db),
                    memberships: try UserSchedule.Performance.fetchAll(db),
                    viewerState: try EventDetailStateRequest(eventID: eventID).fetch(db),
                    preference: try ChannelPreferences.find(preference.id).fetchOne(db),
                    read: try CommsPostRead.find(read.id).fetchOne(db)
                )
            }
            #expect(saved.item?.title == "Collaborative Set — Updated")
            #expect(saved.schedule == personalSchedule)
            #expect(saved.memberships == [membership])
            #expect(saved.viewerState == viewerState)
            #expect(saved.preference == preference)
            #expect(saved.read == read)
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
