import CustomDump
import Foundation
import OpenMusicEventSource
import Testing

struct OpenMusicEventSourceTests {
    @Test
    func readsOrganizerRepository() throws {
        let repository = try OpenMusicEventSourceRepositoryFileTree()
            .read(from: fixtureURL("Organizer"))

        expectNoDifference(
            repository.events.map(\.directoryName),
            [
                "minimal-event",
                "testival-2026",
            ]
        )

        let testival = try #require(
            repository.events.first { $0.directoryName == "testival-2026" }?.components
        )

        #expect(testival.event.id?.rawValue.rawValue == "testival-2026")
        #expect(testival.event.name == "Testival 2026")
        #expect(testival.event.startDate?.description == "2026-08-01")
        #expect(testival.event.endDate?.description == "2026-08-03")
        #expect(testival.event.timeZone.identifier == "America/Denver")

        let stage = try #require(testival.stages?.first)
        #expect(stage.fileName == "meadow")
        #expect(stage.data.id?.rawValue.rawValue == "meadow")
        #expect(stage.data.name == "Meadow")
        #expect(stage.data.color.rawValue == 0x00aaee)

        let participant = try #require(testival.participants?.first)
        #expect(participant.fileName == "artist-one")
        #expect(participant.data.id?.rawValue.rawValue == "artist-one")
        #expect(participant.data.name == "Artist One")
        #expect(participant.data.bio == "Artist One writes sturdy test fixtures.\n")
        #expect(participant.data.links?.first?.platform == .soundcloud)

        let poster = try #require(testival.posters?.first)
        #expect(poster.fileName == "lineup")
        #expect(poster.data.id?.rawValue.rawValue == "lineup")
        #expect(poster.data.eventID == testival.event.id)

        let channel = try #require(testival.channels?.first)
        #expect(channel.fileName == "general")
        #expect(channel.data.id?.rawValue.rawValue == "general")
        #expect(channel.data.defaultNotificationState == .subscribed)

        let schedule = try #require(testival.schedules?.first)
        #expect(schedule.fileName == "saturday")
        #expect(schedule.data.id?.rawValue.rawValue == "saturday")
        #expect(schedule.data.date.description == "2026-08-01")

        let performances = try #require(schedule.data.performances["meadow"])
        expectNoDifference(
            performances.map(\.id?.rawValue.rawValue),
            [
                "opening-set",
                nil,
                "closing-set",
            ]
        )
        #expect(performances[0].participantIDs?.first?.rawValue.rawValue == "artist-one")
        #expect(performances[1].participantNames == ["Guest Artist"])

        let minimal = try #require(
            repository.events.first { $0.directoryName == "minimal-event" }?.components
        )
        #expect(minimal.stages == nil)
        #expect(minimal.participants == nil)
        #expect(minimal.posters == nil)
        #expect(minimal.schedules == nil)
        #expect(minimal.channels == nil)
    }

    private func fixtureURL(_ name: String) throws -> URL {
        try #require(
            Bundle.module.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "Fixtures"
            )
        )
    }
}
