import Foundation
import Testing
import SharingGRDB
import CoreModels
@testable import OpenMusicEvent

@Suite(
    .dependencies {
        $0.date.now = baseDate

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        $0.calendar = calendar

        $0.defaultDatabase = try! OpenMusicEvent.appDatabase()
        try $0.defaultDatabase.write { try $0.seedTestData() }

        $0.imagePrefetchClient = .noop
    },
    .snapshots(record: .failed)
)
struct OpenMusicEventBaseTestSuite {}

extension Database {
    func seedTestData() throws {
        try seed {
            // Organizers

            Organizer.omeTools
            Organizer.wickedWoods
            Organizer.shambhala

            // MusicEvents
            MusicEvent.testival

            MusicEvent(
                id: 2,
                organizerURL: Organizer.omeTools.url,
                name: "Nightfall Collective",
                timeZone: .init(identifier: "America/Vancouver")!,
                startTime: baseDate,
                endTime: baseDate.addingTimeInterval(86400 * 3),
                imageURL: nil,
                iconImageURL: nil,
                siteMapImageURL: nil,
                location: nil,
                contactNumbers: []
            )

            MusicEvent(
                id: 3,
                organizerURL: Organizer.omeTools.url,
                name: "Beats & Botanicals",
                timeZone: .init(identifier: "America/Los_Angeles")!,
                startTime: baseDate,
                endTime: baseDate.addingTimeInterval(86400 * 1),
                imageURL: nil,
                iconImageURL: nil,
                siteMapImageURL: nil,
                location: nil,
                contactNumbers: []
            )

            // Stages (shared across events for test coverage)
            Stage(
                id: 1,
                musicEventID: 1,
                sortIndex: 0,
                name: "The Cauldron",
                color: 0xFF4500,
                lineup: []
            )

            Stage(
                id: 2,
                musicEventID: 1,
                sortIndex: 1,
                name: "Sky Tent",
                color: 0x1E90FF,
                lineup: []
            )

            Stage(
                id: 3,
                musicEventID: 2,
                sortIndex: 0,
                name: "Neon Bazaar",
                color: 0x39FF14,
                lineup: []
            )

            Stage(
                id: 4,
                musicEventID: 2,
                sortIndex: 1,
                name: "Back Alley Stage",
                color: 0xFFD700,
                lineup: []
            )

            Stage(
                id: 5,
                musicEventID: 2,
                sortIndex: 2,
                name: "Liquid Lounge",
                color: 0x8A2BE2,
                lineup: []
            )

            Stage(
                id: 6,
                musicEventID: 3,
                sortIndex: 0,
                name: "Driftwood Deck",
                color: 0xDEB887,
                lineup: []
            )

            Stage(
                id: 7,
                musicEventID: 3,
                sortIndex: 1,
                name: "Afterhours Alley",
                color: 0x00CED1,
                lineup: []
            )

            Stage(
                id: 8,
                musicEventID: 3,
                sortIndex: 2,
                name: "Lava Dome",
                color: 0xDC143C,
                lineup: []
            )

            // Schedule example
            Schedule(
                id: 1,
                musicEventID: 1,
                startTime: baseDate.addingTimeInterval(3600),
                endTime: baseDate.addingTimeInterval(3600 * 5),
                customTitle: "Opening Night"
            )
        }
    }
}

private let baseDate = Date(timeIntervalSince1970: 1234567890)
