import ATProto
import CustomDump
import FileTree
import Foundation
import OpenMusicEventLexicon
import OpenMusicEventSource
import Testing

struct OpenMusicEventSourceTests {
    @Test
    func validatesLocalRepositoryAndBuildsInsertion() async throws {
        let organizerID = try #require(OME.Organizer.ID("did:plc:organizer"))
        let result = try await OpenMusicEventSourceValidator(
            OpenMusicEventSourceValidationRequest(
                source: fixtureURL("Organizer").path(),
                organizerID: organizerID
            )
        )
        .validate()

        expectNoDifference(
            result.summary.events.map(\.eventID),
            [
                "minimal-event",
                "testival-2026",
            ]
        )
        expectNoDifference(
            result.insertedEventIDs.map(\.eventID.rawValue.rawValue),
            [
                "minimal-event",
                "testival-2026",
            ]
        )
        expectNoDifference(
            result.insertion.eventSourceProvenances.map(\.eventIDOrigin),
            [
                .inferred,
                .inferred,
            ]
        )
        expectNoDifference(
            Set(result.insertion.eventSourceProvenances.map(\.source.reference)),
            [try fixtureURL("Organizer").standardizedFileURL.path()]
        )
        #expect(result.organizerID == organizerID)
    }

    @Test
    func rejectsLocalRepositoryWithoutOrganizerID() async throws {
        do {
            _ = try await OpenMusicEventSourceValidator(
                OpenMusicEventSourceValidationRequest(
                    source: fixtureURL("Organizer").path()
                )
            )
            .validate()
            Issue.record("Expected local source validation to require an organizer ID.")
        } catch OpenMusicEventSourceValidationError.missingOrganizerIDForLocalSource {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func readsOrganizerRepository() throws {
        let repositoryResult = try OpenMusicEventSourceRepositoryFileTree()
            .read(from: fixtureURL("Organizer"))
        let repository = try repositoryResult.output.requiredValue

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

        #expect(testival.event.id == nil)
        #expect(testival.event.name == "Testival 2026")
        #expect(testival.event.startDate?.description == "2026-08-01")
        #expect(testival.event.endDate?.description == "2026-08-03")
        #expect(testival.event.timeZone.identifier == "America/Denver")

        let stage = try #require(testival.stages?.first)
        #expect(stage.fileName == "meadow")
        #expect(stage.data.id == nil)
        #expect(stage.data.name == "Meadow")
        #expect(stage.data.color.rawValue == 0x00aaee)

        let participant = try #require(testival.participants?.first)
        #expect(participant.fileName == "artist-one")
        #expect(participant.data.id == nil)
        #expect(participant.data.name == "Artist One")
        #expect(participant.data.bio == "Artist One writes sturdy test fixtures.\n")
        #expect(participant.data.links?.first?.platform == .soundcloud)

        let poster = try #require(testival.posters?.first)
        #expect(poster.fileName == "lineup")
        #expect(poster.data.id == nil)

        let channel = try #require(testival.channels?.first)
        #expect(channel.fileName == "general")
        #expect(channel.data.id == nil)
        #expect(channel.data.defaultNotificationState == .subscribed)

        let schedule = try #require(testival.schedules?.first)
        #expect(schedule.fileName == "saturday")
        #expect(schedule.data.id == nil)
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
        expectNoDifference(
            performances[0].recordings,
            [
                ExternalPlatform.Asset(
                    url: URL(string: "https://example.com/opening-set.mp3")!
                ),
                ExternalPlatform.Asset(
                    record: .init(
                        uri: ATProto.URI("at://did:plc:streamer/place.stream.livestream/3k5nobkf2w72g")!,
                        cid: "bafyreibvlzqnyqbyq2xlxzyelbnzczd3i2cppmx7xghg42yyjz7dss6xju"
                    )
                ),
            ]
        )
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
