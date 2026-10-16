import CustomDump
import Foundation
import ATProtoTypes
import ATProtoSQLite
import OpenMusicEventLexicon
import Testing

@Suite
struct LinkTests {
    @Test
    func contactAndReportingCarryTheirOwnClassification() throws {
        let link = OME.Link(
            url: try #require(URL(string: "tel:+12505550123")), title: "On-site safety",
            description: "Call for help", role: .known(.contact(.init(use: .known(.emergency))))
        )
        let json: Lexicon.JSONValue = .object([
            "url": "tel:+12505550123", "title": "On-site safety", "description": "Call for help",
            "role": .object(["$type": "events.openmusic.defs#contactLink", "use": "emergency"]),
        ])
        expectNoDifference(try link.encodeLexicon(), json)
        expectNoDifference(try OME.Link.decodeLexicon(json), link)
        var reporting = link
        reporting.url = try #require(URL(string: "https://example.com/report"))
        reporting.role = .known(.reporting(.init(use: .known(.nonEmergency))))
        expectNoDifference(try reporting.encodeLexicon().object?["role"], .object([
            "$type": "events.openmusic.defs#reportingLink", "use": "nonEmergency",
        ]))
        expectNoDifference(try OME.Link.decodeLexicon(reporting.encodeLexicon()), reporting)
        reporting.role = .known(.reporting(.init()))
        expectNoDifference(try reporting.encodeLexicon().object?["role"], .object([
            "$type": "events.openmusic.defs#reportingLink",
        ]))
    }

    @Test
    func futureRolesPlatformsAndContactUsesSurviveAnEdit() throws {
        for role: Lexicon.JSONValue in [
            .object(["$type": "events.example.defs#futureRole", "details": .object(["enabled": true])]),
            .object(["$type": "events.openmusic.defs#contactLink", "use": "futureUse"]),
            .object(["$type": "events.openmusic.defs#reportingLink", "use": "futureUse"]),
        ] {
            var json: [String: Lexicon.JSONValue] = [
                "url": "https://example.com/help", "role": role, "platform": "futurePlatform",
            ]
            var link = try OME.Link.decodeLexicon(.object(json))
            link.title = "Updated title"
            json["title"] = "Updated title"
            expectNoDifference(try link.encodeLexicon(), .object(json))
        }
        #expect(throws: (any Error).self) {
            try OME.Link.decodeLexicon(.object([
                "url": "https://example.com", "role": .object([
                    "$type": "events.openmusic.defs#contactLink", "use": 42,
                ]),
            ]))
        }
    }

    @Test
    func existingContributorLinksKeepTheirStoredContent() throws {
        for json: Lexicon.JSONValue in [
            .object(["url": "https://soundcloud.com/artist", "platform": "soundcloud"]),
            .object(["url": "https://soundcloud.com/artist"]),
        ] {
            let link = try OME.Link.decodeLexicon(json)
            expectNoDifference(try link.encodeLexicon(), json)
            expectNoDifference(link.detectedPlatform, .soundcloud)
            #expect(link.role == nil)
        }
        let contributor = try Contributor(
            id: #require(ATProto.URI("at://did:plc:organizer/events.openmusic.contributor/3mrdbziccpcah")),
            event: #require(ATProto.URI("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcai")),
            name: "Artist", createdAt: "2026-09-01T12:00:00Z", links: [.init(url: try #require(URL(string: "https://example.com")), title: "Bookings", role: .known(.contact(.init(use: .known(.nonEmergency)))))]
        )
        expectNoDifference(try Contributor.decodeLexicon(contributor.encodeLexicon(), metadata: .init(uri: contributor.id)), contributor)
    }

    @Test(arguments: ["https://example.com", "tel:+12505550123", "sms:+12505550123", "mailto:safety@example.com"])
    func linkDestinationsSupportWebAndContactSchemes(_ destination: String) throws {
        let link = OME.Link(url: try #require(URL(string: destination)))
        expectNoDifference(try OME.Link.decodeLexicon(link.encodeLexicon()), link)
    }

    @Test
    func websiteAndTicketRolesDoNotCarryContactClassification() throws {
        for (role, type): (OME.Link.Role, String) in [(.website(.init()), "websiteLink"), (.tickets(.init()), "ticketsLink")] {
            let link = OME.Link(url: try #require(URL(string: "https://example.com")), role: .known(role))
            expectNoDifference(try link.encodeLexicon().object?["role"], .object([
                "$type": .string("events.openmusic.defs#" + type),
            ]))
            expectNoDifference(try OME.Link.decodeLexicon(link.encodeLexicon()), link)
        }
    }

    @Test
    func schemaUsesAnOpenRoleUnionAndOpenScalarVocabularies() throws {
        let documents = try LexiconExporter.documents(for: [OME.Link.self])
        let document = try #require(documents.first)
        let defs = try #require(Lexicon.JSONValue(encoding: document).object?["defs"]?.object)
        let link = try #require(defs["link"]?.object)
        expectNoDifference(link["required"], .array(["url"]))
        expectNoDifference(link["nullable"], .array(["title", "description", "role", "platform"]))
        let fields = try #require(link["properties"]?.object)
        expectNoDifference(fields["url"], .object([
            "type": "string", "format": "uri", "description": "The URI opened by this link.",
        ]))
        expectNoDifference(fields["title"], .object([
            "type": "string", "minLength": 1, "maxLength": 5_000, "maxGraphemes": 500,
            "description": "A short human-readable label for the link.",
        ]))
        expectNoDifference(fields["description"], .object([
            "type": "string", "maxLength": 30_000, "maxGraphemes": 3_000,
            "description": "Additional human-readable context about the link.",
        ]))
        expectNoDifference(fields["role"], .object([
            "type": "union", "refs": .array(["#websiteLink", "#ticketsLink", "#contactLink", "#reportingLink"]),
            "description": "The link's purpose in the event experience.",
        ]))
        #expect(fields["platform"]?.object?["enum"] == nil)
        #expect(fields["platform"]?.object?["knownValues"] != nil)
        expectNoDifference(defs["contactLink"]?.object?["properties"]?.object?["use"], .object([
            "type": "string", "knownValues": .array(["emergency", "nonEmergency"]),
            "description": "Whether this contact channel is intended for emergencies or non-emergency matters.",
        ]))
    }
}
