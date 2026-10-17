import ATProto
import CustomDump
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import OpenMusicEventAppViewServer

@Suite struct CalendarPublisherMigrationTests {
    @Test func `default source exclusions are configurable without changing records`() async throws {
        let configuration = try AppViewConfiguration.fromEnvironment(environment: [
            "OME_CALENDAR_EXCLUDED_PUBLISHERS": "[]"
        ])
        expectNoDifference(configuration.communityCalendarExcludedPublishers, [])
        let store = try OpenMusicEventAppViewStore(database: DatabaseQueue(),
            communityCalendarExcludedPublishers: configuration.communityCalendarExcludedPublishers)
        let excludedPublishers = try await store.calendarPublishers(.init()).defaults.publishers
        expectNoDifference(excludedPublishers, [])
        #expect(throws: AppViewConfigurationError.invalidCommunityCalendarPublishers) {
            try AppViewConfiguration.fromEnvironment(environment: ["OME_CALENDAR_EXCLUDED_PUBLISHERS": "[\"not-a-did\"]"])
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OME_PUBLISHER_SNAPSHOT"] != nil))
    func `existing indexed records survive publisher backfill and filtered tiles remain compact`() async throws {
        let sourcePath = try #require(ProcessInfo.processInfo.environment["OME_PUBLISHER_SNAPSHOT"])
        var configuration = Configuration()
        configuration.readonly = true
        let source = try DatabaseQueue(path: sourcePath, configuration: configuration)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ome-publisher-validation-\(UUID())")
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        let database = try DatabaseQueue(path: directory.appendingPathComponent("appview.sqlite").path)
        try source.backup(to: database)
        let originalCount = try await database.read { try CalendarEventBrowseProjection.all.fetchCount($0) }
        let originalEvent = try await database.read { try CalendarEventBrowseProjection.order(by: \.uri).limit(1).fetchOne($0) }
        let start = ContinuousClock.now
        let store = try OpenMusicEventAppViewStore(database: database)
        let elapsed = start.duration(to: .now)
        let retainedCount = try await database.read { try CalendarEventBrowseProjection.all.fetchCount($0) }
        expectNoDifference(retainedCount, originalCount)
        let retainedEvent = try await database.read { try CalendarEventBrowseProjection.order(by: \.uri).limit(1).fetchOne($0) }
        expectNoDifference(retainedEvent, originalEvent)
        let integrity = try await database.read { try String.fetchOne($0,sql: "PRAGMA quick_check") }
        expectNoDifference(integrity, "ok")
        let generation = try #require(try await database.read { try CalendarMapBuild.find(0).select(\.active).fetchOne($0) })
        let defaults = try await store.calendarPublishers(.init()).defaults
        let allIDs = try await database.read { try CalendarPublisher.select(\.id).fetchAll($0) }
        for lens in [defaults, try CalendarPublisherLens(mode: "only",publishers: defaults.publishers),
                     try CalendarPublisherLens(mode: "only",publishers: Array(allIDs.prefix(allIDs.count / 2)))] {
            let request = try CalendarMapTileRequest(z: 0,x: 0,y: 0,catalogs: [.init(CalendarPublisher.communityCatalog)!],
                dates: "current",publisherMode: lens.mode.rawValue,publishers: lens.publishers)
            var timings: [Double] = []
            var bytes = 0
            for _ in 0..<10 {
                let tile = try await store.mapTile(request,generation: generation)
                timings.append(tile.databaseMilliseconds)
                bytes = tile.gzip.count
                #expect(tile.featureCount <= 64)
            }
            timings.sort()
            print("Publisher tile \(lens.mode.rawValue) \(lens.publishers.count): median=\(timings[5])ms max=\(timings.last!)ms gzip=\(bytes)")
        }
        print("Publisher migration: \(originalCount) unchanged browse records; \(elapsed); retained isolated database: \(directory.path)")
    }
}
