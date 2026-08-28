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
    func `fresh app imports Testival and enters its opening set without network access`() async throws {
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

            let attendeeStory = try await database.read { db in
                let installation = try InstalledEventRecord.find(eventID).fetchOne(db)
                let provenance = try EventSourceProvenanceRecord.find(eventID).fetchOne(db)
                let schedules = try OME.Schedule
                    .where { $0.id.organizerID.eq(eventID.organizerID) }
                    .where { $0.id.eventID.eq(eventID.eventID) }
                    .fetchAll(db)
                let performances = try OME.Performance
                    .where { $0.id.organizerID.eq(eventID.organizerID) }
                    .where { $0.id.eventID.eq(eventID.eventID) }
                    .fetchAll(db)
                return (installation, provenance, schedules, performances)
            }

            #expect(attendeeStory.0 != nil)
            let provenance = try #require(attendeeStory.1)
            expectNoDifference(provenance.sourceKind, .tangled)
            expectNoDifference(
                provenance.sourceReference,
                OpenMusicEventUIAutomationFixture.sourceReference
            )
            expectNoDifference(attendeeStory.2.map(\.customTitle), ["Saturday"])
            expectNoDifference(attendeeStory.3.map(\.title), ["Opening Set"])
            expectNoDifference(
                attendeeStory.3.map { $0.id.performanceID.rawValue.rawValue },
                ["opening-set"]
            )

            // Exercise the same division, stage, schedule, and performance
            // filtering used by the attendee schedule screen.
            let scheduleProjection = try await database.read { db in
                (
                    try PerformanceRow.all(eventID: eventID).fetchAll(db),
                    try ScheduleViewer.schedulesQuery(eventID: eventID).fetchAll(db),
                    try ScheduleViewer.stagesQuery(eventID: eventID).fetchAll(db)
                )
            }
            let selectedScheduleID = ScheduleViewer.resolvedSelectedScheduleID(
                nil,
                schedules: scheduleProjection.1
            )
            let visibleStages = ScheduleViewer.visibleStages(
                stages: scheduleProjection.2,
                division: .schedule
            )
            expectNoDifference(visibleStages.map(\.name), ["Meadow"])
            expectNoDifference(
                ScheduleViewer.visiblePerformances(
                    performanceRows: scheduleProjection.0,
                    scheduleID: selectedScheduleID,
                    stages: visibleStages
                )
                .map(\.title),
                ["Opening Set"]
            )

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
