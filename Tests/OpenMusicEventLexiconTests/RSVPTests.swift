import ATProto
import Foundation
import OpenMusicEventLexicon
import Testing

struct RSVPTests {
    @Test
    func `an OME RSVP has the same subject and status shape as a community calendar RSVP`() throws {
        let eventURI = try #require(
            ATProto.URI("at://did:plc:festival/app.openmusicevent.event/summer-2026")
        )
        let record = OME.RSVP(
            subject: OME.Event.Reference(uri: eventURI, cid: "bafyreievent"),
            status: .going
        )

        // Publishing is deliberately deferred, but the value we persist today is already
        // the public record value OME will publish later.
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(record))
                as? [String: Any]
        )
        #expect(object["$type"] as? String == "app.openmusicevent.rsvp")
        #expect(object["status"] as? String == "app.openmusicevent.rsvp#going")

        let subject = try #require(object["subject"] as? [String: String])
        #expect(subject["uri"] == eventURI.description)
        #expect(subject["cid"] == "bafyreievent")
    }
}
