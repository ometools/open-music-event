import ATProto
import CustomDump
import Foundation
import OpenMusicEventLexicon
import Testing

@Suite("OME calendar event XRPC contract")
struct CalendarEventLexiconTests {
    @Test
    func `getEvents returns the shared calendar event page`() throws {
        let definitions = try lexicon(named: "defs")
        let getEvents = try lexicon(named: "getEvents")

        #expect(definitions["id"] as? String == "app.openmusicevent.calendar.defs")
        #expect(getEvents["id"] as? String == OME.CalendarEvent.GetEvents.nsid.description)

        let definitionsBody = try #require(definitions["defs"] as? [String: Any])
        let calendarEvent = try #require(definitionsBody["calendarEvent"] as? [String: Any])
        let calendarEventProperties = try #require(calendarEvent["properties"] as? [String: Any])
        let hydratedEvent = try #require(calendarEventProperties["event"] as? [String: Any])
        #expect(hydratedEvent["type"] as? String == "unknown")

        let page = try #require(definitionsBody["page"] as? [String: Any])
        let pageProperties = try #require(page["properties"] as? [String: Any])
        let events = try #require(pageProperties["events"] as? [String: Any])
        let eventItems = try #require(events["items"] as? [String: Any])
        #expect(eventItems["ref"] as? String == "#calendarEvent")

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
    func `calendar event pages preserve optional OME hydration`() throws {
        let organizerID = try #require(OME.Organizer.ID("did:plc:wickedwoods"))
        let eventID = OME.Event.ID(
            organizerID: organizerID,
            eventID: OME.ID<OME.Event>(.init("wicked-woods-2026"))
        )
        let event = try makeEvent(id: eventID)
        let source = OME.CalendarEvent.Source(collection: OME.Event.nsid)
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
        categoryConfigs: nil,
        reportingLinks: nil,
        owner: nil
    )
    return try JSONDecoder().decode(OME.Event.self, from: JSONEncoder().encode(draft))
}
