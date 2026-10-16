import Bluesky
import ATProto
import Dependencies
import DependenciesTestSupport
import Foundation
import OpenMusicEventDatabase
import SQLiteData
import Testing

@testable import OpenMusicEventApp

@Suite(
    .dependencies {
        $0.uuid = .incrementing
    },
    .tcaExhaustivity(.off),
    .serialized
)
struct UserStoryTests {}

enum UserStory {
    static let organizerID = OMERecord.Organizer.ID("did:web:example.com")!
    static let eventID = OMERecord.Event.ID(
        organizerID: organizerID,
        eventID: eventLocalID("testival-2026")
    )
    static let meadowStageID = stageLocalID("meadow")
    static let pavilionStageID = stageLocalID("pavilion")

    static func makePreparedStoryDatabase(
        at databaseURL: URL? = nil
    ) throws -> any DatabaseWriter {
        if let databaseURL {
            let database = try DatabasePool(path: databaseURL.path)
            var migrator = DatabaseMigrator()
            OMERecord.DatabaseMigrations.register(into: &migrator)
            BlueskyActorCacheMigrations.register(into: &migrator)
            OpenMusicEventAppDatabaseMigrations.register(into: &migrator)
            try migrator.migrate(database)
            return database
        }

        return try withDependencies {
            $0.context = .test
            try OME.prepareDependencies(&$0)
        } operation: {
            @Dependency(\.defaultDatabase) var database
            return database
        }
    }

    static func seedDefault(in database: any DatabaseWriter) async throws {
        let meadowLogoURL = try #require(URL(string: "https://cdn.example.com/stages/meadow-logo.png"))
        let meadowHeroURL = try #require(URL(string: "https://cdn.example.com/stages/meadow-hero.png"))
        let meadowPosterURL = try #require(URL(string: "https://cdn.example.com/stages/meadow-poster.png"))
        let pavilionHeroURL = try #require(URL(string: "https://cdn.example.com/stages/pavilion-hero.png"))

        try await database.write { db in
            try OMERecord.Organizer.insert {
                OMERecord.Organizer.Draft(id: organizerID)
            }
            .execute(db)

            try OMERecord.Event.insert {
                testEventDraft(
                    id: eventID,
                    name: "Testival 2026",
                    startDate: nil,
                    endDate: nil,
                    timeZone: TimeZone(identifier: "America/Denver")!
                )
            }
            .execute(db)

            try OMERecord.Stage.insert {
                OMERecord.Stage.Draft(
                    id: OMERecord.Stage.ID(
                        organizerID: eventID.organizerID,
                        eventID: eventID.eventID,
                        stageID: meadowStageID
                    ),
                    name: "Meadow",
                    color: 0x44AA77,
                    category: OMERecord.Stage.Category("main"),
                    sortIndex: 1,
                    iconImageURL: meadowLogoURL,
                    systemIconName: "sparkles",
                    iconShortCode: "MD",
                    imageURL: meadowHeroURL,
                    posterImageURL: meadowPosterURL,
                    lineup: nil
                )
            }
            .execute(db)

            try OMERecord.Stage.insert {
                OMERecord.Stage.Draft(
                    id: OMERecord.Stage.ID(
                        organizerID: eventID.organizerID,
                        eventID: eventID.eventID,
                        stageID: pavilionStageID
                    ),
                    name: "Pavilion",
                    color: 0x336699,
                    category: OMERecord.Stage.Category("workshop"),
                    sortIndex: 2,
                    iconImageURL: nil,
                    systemIconName: "music.mic",
                    iconShortCode: "PV",
                    imageURL: pavilionHeroURL,
                    posterImageURL: nil,
                    lineup: nil
                )
            }
            .execute(db)
        }
    }

    private static func eventLocalID(
        _ string: String
    ) -> OMERecord.ID<OMERecord.Event> {
        OMERecord.ID<OMERecord.Event>(
            rawValue: ATProto.Record.Key(rawValue: string)
        )
    }

    private static func stageLocalID(
        _ string: String
    ) -> OMERecord.ID<OMERecord.Stage> {
        OMERecord.ID<OMERecord.Stage>(
            rawValue: ATProto.Record.Key(rawValue: string)
        )
    }
}
