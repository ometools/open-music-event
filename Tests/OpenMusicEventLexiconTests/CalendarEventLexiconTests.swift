import ATProto
import CustomDump
import Foundation
import OpenMusicEventLexicon
import Testing

@Suite("OME calendar event XRPC contract")
struct CalendarEventLexiconTests {
    @Test
    func `calendar queries return the shared calendar event contracts`() throws {
        let definitions = try lexicon(named: "defs")
        let getEvent = try lexicon(named: "getEvent")
        let getEvents = try lexicon(named: "getEvents")

        #expect(definitions["id"] as? String == "app.openmusicevent.calendar.defs")
        #expect(getEvent["id"] as? String == OME.CalendarEvent.GetEvent.nsid.description)
        #expect(getEvents["id"] as? String == OME.CalendarEvent.GetEvents.nsid.description)

        let definitionsBody = try #require(definitions["defs"] as? [String: Any])
        let calendarEvent = try #require(definitionsBody["calendarEvent"] as? [String: Any])
        let calendarEventProperties = try #require(calendarEvent["properties"] as? [String: Any])
        let hydratedEvent = try #require(calendarEventProperties["event"] as? [String: Any])
        #expect(hydratedEvent["type"] as? String == "unknown")
        let source = try #require(definitionsBody["source"] as? [String: Any])
        let sourceProperties = try #require(source["properties"] as? [String: Any])
        let sourceRecord = try #require(sourceProperties["sourceRecord"] as? [String: Any])
        #expect(sourceRecord["ref"] as? String == "#sourceRecord")
        let resolvedArtifact = try #require(
            sourceProperties["resolvedArtifact"] as? [String: Any]
        )
        #expect(resolvedArtifact["ref"] as? String == "#sourceArtifact")
        let sourceArtifact = try #require(definitionsBody["sourceArtifact"] as? [String: Any])
        #expect(
            sourceArtifact["required"] as? [String]
                == ["url", "revision", "checksumSHA256", "byteCount"]
        )

        let page = try #require(definitionsBody["page"] as? [String: Any])
        let pageProperties = try #require(page["properties"] as? [String: Any])
        let events = try #require(pageProperties["events"] as? [String: Any])
        let eventItems = try #require(events["items"] as? [String: Any])
        #expect(eventItems["ref"] as? String == "#calendarEvent")

        let getEventDefinitions = try #require(getEvent["defs"] as? [String: Any])
        let getEventMain = try #require(getEventDefinitions["main"] as? [String: Any])
        #expect(getEventMain["type"] as? String == "query")
        let getEventParameters = try #require(getEventMain["parameters"] as? [String: Any])
        #expect(getEventParameters["required"] as? [String] == ["uri"])
        let getEventOutput = try #require(getEventMain["output"] as? [String: Any])
        let getEventSchema = try #require(getEventOutput["schema"] as? [String: Any])
        #expect(
            getEventSchema["ref"] as? String
                == "app.openmusicevent.calendar.defs#calendarEvent"
        )

        let getEventsDefinitions = try #require(getEvents["defs"] as? [String: Any])
        let main = try #require(getEventsDefinitions["main"] as? [String: Any])
        #expect(main["type"] as? String == "query")

        let parameters = try #require(main["parameters"] as? [String: Any])
        #expect(parameters["required"] as? [String] == ["catalog"])

        let output = try #require(main["output"] as? [String: Any])
        let schema = try #require(output["schema"] as? [String: Any])
        #expect(schema["ref"] as? String == "app.openmusicevent.calendar.defs#page")
    }

    @Test
    func `getEvent carries its canonical record URI`() throws {
        let uri = try #require(ATProto.URI(
            "at://did:plc:wickedwoods/app.openmusicevent.event/wicked-woods-2026"
        ))

        expectNoDifference(
            OME.CalendarEvent.GetEvent(uri: uri).parameters,
            OME.CalendarEvent.GetEvent.Parameters(uri: uri)
        )
    }

    @Test
    func `calendar event pages preserve optional OME hydration`() throws {
        let organizerID = try #require(OME.Organizer.ID("did:plc:wickedwoods"))
        let eventID = OME.Event.ID(
            organizerID: organizerID,
            eventID: OME.ID<OME.Event>(.init("wicked-woods-2026"))
        )
        let event = try makeEvent(id: eventID)
        let artifactURL = try #require(
            URL(
                string: "https://resources.openmusicevent.app/wickedwoods.ca/ome-workspace/archive/2222222222222222222222222222222222222222.tar.gz"
            )
        )
        let source = OME.CalendarEvent.Source(
            collection: OME.Event.nsid,
            appViewHost: "openmusicevent.app",
            sourceRecord: OME.SourceRecord(
                kind: .tangled,
                reference: "https://tangled.org/wickedwoods.ca/ome-workspace",
                ref: "main"
            ),
            resolvedArtifact: OME.CalendarEvent.Source.Artifact(
                url: artifactURL,
                revision: "2222222222222222222222222222222222222222",
                checksumSHA256: "DrPja/sk3Nm7HRvs4VMSFrWVOaj94X7oAiSvBlPJKqM=",
                byteCount: 7
            ),
            resolvedRepository: OME.CalendarEvent.Source.Repository(
                reference: "https://resources.openmusicevent.app/wickedwoods.ca/ome-workspace",
                ref: "2222222222222222222222222222222222222222"
            )
        )
        let organizer = OME.CalendarEvent.Organizer(
            id: organizerID,
            handle: "wickedwoods.bsky.social",
            displayName: "Wicked Woods"
        )

        let page = OME.CalendarEvent.Page(
            events: [
                OME.CalendarEvent(
                    uri: OME.Event.reference(id: eventID).uri,
                    name: "Wicked Woods",
                    startsAt: Date(timeIntervalSince1970: 1_776_384_000),
                    endsAt: Date(timeIntervalSince1970: 1_776_556_800),
                    status: .scheduled,
                    mode: .inPerson,
                    locations: [.init(name: "Fairplay, Colorado")],
                    organizer: organizer,
                    source: source,
                    timeZoneIdentifier: "America/Denver",
                    event: event
                ),
                OME.CalendarEvent(
                    uri: ATProto.URI(
                        authority: .did(organizerID),
                        collection: ATProto.NSID("community.lexicon.calendar.event"),
                        rkey: .init("community-gathering")
                    ),
                    name: "Community Gathering",
                    status: .unknown("community.lexicon.calendar.event#tentative"),
                    mode: .unknown("community.lexicon.calendar.event#broadcast"),
                    organizer: organizer,
                    source: .init(collection: ATProto.NSID("community.lexicon.calendar.event"))
                ),
            ],
            cursor: "next-page"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encodedPage = try encoder.encode(page)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedPage = try decoder.decode(OME.CalendarEvent.Page.self, from: encodedPage)
        expectNoDifference(decodedPage, page)

        let json = try #require(JSONSerialization.jsonObject(with: encodedPage) as? [String: Any])
        let encodedEvents = try #require(json["events"] as? [[String: Any]])
        #expect(encodedEvents[0]["event"] != nil)
        #expect(encodedEvents[1]["event"] == nil)
        let encodedSource = try #require(encodedEvents[0]["source"] as? [String: Any])
        let encodedSourceRecord = try #require(encodedSource["sourceRecord"] as? [String: Any])
        #expect(encodedSourceRecord["$type"] as? String == OME.SourceRecord.nsid.rawValue)
        #expect(encodedSourceRecord["reference"] as? String == "https://tangled.org/wickedwoods.ca/ome-workspace")
        let encodedArtifact = try #require(encodedSource["resolvedArtifact"] as? [String: Any])
        #expect(encodedArtifact["url"] as? String == artifactURL.absoluteString)
        #expect(
            encodedArtifact["revision"] as? String
                == "2222222222222222222222222222222222222222"
        )
        #expect(
            encodedArtifact["checksumSHA256"] as? String
                == "DrPja/sk3Nm7HRvs4VMSFrWVOaj94X7oAiSvBlPJKqM="
        )
        #expect(encodedArtifact["byteCount"] as? Int == 7)
    }

    @Test
    func `getEvents carries its catalog cursor and limit`() {
        let request = OME.CalendarEvent.GetEvents(
            catalog: OME.Event.nsid,
            cursor: "next-page",
            limit: 25
        )

        expectNoDifference(
            request.parameters,
            OME.CalendarEvent.GetEvents.Parameters(
                catalog: OME.Event.nsid,
                cursor: "next-page",
                limit: 25
            )
        )
    }
}

private func lexicon(named name: String) throws -> [String: Any] {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = packageRoot
        .appendingPathComponent("Lexicons")
        .appendingPathComponent("app")
        .appendingPathComponent("openmusicevent")
        .appendingPathComponent("calendar")
        .appendingPathComponent("\(name).json")
    return try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
}

private func makeEvent(id: OME.Event.ID) throws -> OME.Event {
    let startDate = try #require(LocalDate("2026-08-14"))
    let endDate = try #require(LocalDate("2026-08-16"))
    let timeZone = try #require(TimeZone(identifier: "America/Denver"))
    let draft = OME.Event.Draft(
        id: id,
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
    return try JSONDecoder().decode(OME.Event.self, from: JSONEncoder().encode(draft))
}
