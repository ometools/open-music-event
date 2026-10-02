import CustomDump
import Foundation
import OpenMusicEventLexicon
import Testing

@Suite("OME Lexicon record JSON")
struct MusicEventCodableTests {
    @Test
    func `public OME table records are Codable`() {
        requiresCodable(OME.Organizer.self)
        requiresCodable(OME.Event.self)
        requiresCodable(OME.Calendar.self)
        requiresCodable(OME.Stage.self)
        requiresCodable(OME.Schedule.self)
        requiresCodable(OME.Performance.self)
        requiresCodable(OME.Contributor.self)
        requiresCodable(OME.Channel.self)
        requiresCodable(OME.Poster.self)
        requiresCodable(OME.Relationship.self)
    }

    @Test
    func `the canonical event record crosses the existing JSON boundary`() throws {
        let organizerID = try #require(OME.Organizer.ID("did:plc:wickedwoods"))
        let eventID = OME.Event.ID(
            organizerID: organizerID,
            eventID: OME.ID<OME.Event>(.init("wicked-woods-2026"))
        )
        let startDate = try #require(LocalDate("2026-08-14"))
        let endDate = try #require(LocalDate("2026-08-16"))
        let timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let draft = OME.Event.Draft(
            id: eventID,
            name: "Wicked Woods",
            description: "The event returned by the AppView.",
            startDate: startDate,
            endDate: endDate,
            status: .known(.scheduled),
            mode: .known(.inPerson),
            locations: [OME.Event.Location(address: "Fairplay, Colorado")],
            uris: nil,
            timeZone: timeZone,
            imageURL: nil,
            iconImageURL: nil,
            siteMapImageURL: nil,
            contactNumbers: nil,
            reportingLinks: nil,
            owner: nil
        )

        let record = try JSONDecoder().decode(
            OME.Event.self,
            from: JSONEncoder().encode(draft)
        )
        let roundTrippedRecord = try JSONDecoder().decode(
            OME.Event.self,
            from: JSONEncoder().encode(record)
        )

        expectNoDifference(roundTrippedRecord, record)
    }
}

private func requiresCodable<Value: Codable>(_: Value.Type) {}
