import CustomDump
import Foundation
import ATProtoTypes
import ATProtoSQLite
import SQLiteData
@testable import OpenMusicEventLexicon
import Testing

@Suite
struct EventTests {
    private let uri = ATProto.URI("at://did:plc:wickedwoods/events.openmusic.event/3mrdbziccpcah")!

    typealias Event = OpenMusicEventLexicon.Event

    @Test
    func `an unannounced event payload needs only its name creation timestamp and time zone`() throws {
        let event = try Event(id: uri, name: "Coming soon", createdAt: "2026-09-15T12:34:56.123456789Z", timeZone: .gmt)
        let json = try event.encodeLexicon()
        expectNoDifference(json, .object([
            "$type": "events.openmusic.event", "name": "Coming soon",
            "createdAt": "2026-09-15T12:34:56.123456789Z", "timeZone": "GMT",
        ]))
        expectNoDifference(try Event.decodeLexicon(json, metadata: .init(uri: uri)), event)
    }

    @Test(arguments: [true, false])
    func `the public event model round trips through its SQLite table`(enforceForeignKey: Bool) throws {
        let programURI = try #require(ATProto.URI(
            "at://did:plc:wickedwoods/events.openmusic.program/3mrdbziccpcal"
        ))
        let scheduleURI = try #require(ATProto.URI(
            "at://did:plc:wickedwoods/events.openmusic.schedule/3mrdbziccpcam"
        ))
        var event = try Event(
            id: uri,
            cid: "last-observed-revision",
            name: "Wicked Woods",
            createdAt: "2026-01-01T12:00:00.000Z",
            timeZone: try #require(TimeZone(identifier: "America/Edmonton")),
            description: "Music in the woods",
            start: .known(.day(.init(value: try #require(LocalDate("2026-09-04"))))),
            end: .known(.time(.init(value: "2026-09-07T06:00:00.000Z"))),
            status: .unknown("events.example.defs#tentative"),
            mode: .known(.inPerson),
            locations: [
                .init(
                    name: "Festival grounds",
                    locators: [.known(.address(.init(country: "CA", locality: "Invermere")))],
                    links: [.init(url: try #require(URL(string: "https://example.com/map")), title: "Map")]
                ),
            ],
            links: [.init(url: try #require(URL(string: "https://example.com/tickets")), role: .known(.tickets(.init())))],
            programs: [programURI],
            schedules: [scheduleURI],
            rsvpExpected: true,
            categories: [#require(ATProto.URI("at://did:plc:wickedwoods/social.ome.category/3mrdbziccpcam"))],
            siteMap: .init(title: "Festival map", styles: [
                .init(id: "public", title: "Public", image: .init(
                    source: .known(.url(#require(URL(string: "https://example.com/map.png")))),
                    role: .known(.siteMap)
                )),
            ], defaultStyleID: "public")
        )
        event.media = [
            .known(.image(.init(source: .known(.url(try #require(URL(string: "https://example.com/poster.png"))))))),
            .unknown(.object([
                "$type": "events.example.defs#video",
                "url": "https://example.com/recap.mp4",
            ])),
        ]

        let database = try DatabaseQueue()
        try database.write { db in
            try #sql(
                """
                CREATE TABLE \(quote: Event.tableName) (
                  "id" TEXT PRIMARY KEY NOT NULL,
                  "cid" TEXT,
                  "name" TEXT NOT NULL,
                  "createdAt" TEXT NOT NULL,
                  "timeZone" TEXT NOT NULL,
                  "description" TEXT,
                  "start" TEXT,
                  "end" TEXT,
                  "status" TEXT,
                  "mode" TEXT,
                  "locations" TEXT,
                  "links" TEXT,
                  "media" TEXT,
                  "programs" TEXT,
                  "schedules" TEXT,
                  "rsvpExpected" INTEGER,
                  "categories" TEXT,
                  "siteMap" TEXT
                ) STRICT
                """
            )
            .execute(db)
            try db.execute(sql: """
                CREATE TABLE testChildren (
                  id TEXT PRIMARY KEY NOT NULL,
                  cid TEXT,
                  event TEXT NOT NULL \(enforceForeignKey ? "REFERENCES \"events.openmusic.event\"(id)" : ""),
                  localNote TEXT
                ) STRICT
                """)
            let child = try EventChild(
                id: #require(ATProto.URI("at://did:plc:wickedwoods/events.example.child/3mrdbziccpcai")),
                event: event.id,
                localNote: "Local only"
            )
            if enforceForeignKey {
                #expect(throws: (any Error).self) { try EventChild.insert { child }.execute(db) }
            } else {
                try EventChild.insert { child }.execute(db)
                #expect(try EventChild.all.fetchCount(db) == 1)
                #expect(try EventChild.all.join(Event.all) { $0.event.eq($1.id) }.fetchAll(db).count == 0)
            }
            try Event.insert { event }.execute(db)
            #expect(throws: (any Error).self) { try Event.insert { event }.execute(db) }
            if enforceForeignKey { try EventChild.insert { child }.execute(db) }
            let storedChild = try #require(try EventChild.find(child.id).fetchOne(db))
            expectNoDifference(storedChild, child)
            expectNoDifference(try storedChild.encodeLexicon(), .object([
                "$type": "events.example.child", "event": .string(event.id.description),
            ]))
            #expect(try EventChild.all.join(Event.all) { $0.event.eq($1.id) }.fetchAll(db).count == 1)
        }

        let stored = try database.read { db in
            try #require(try Event.all.fetchOne(db))
        }
        #expect(Event.tableName == "events.openmusic.event")
        expectNoDifference(stored, event)
        expectNoDifference(try stored.encodeLexicon(), try event.encodeLexicon())

        event.name = "Wicked Woods — updated locally"
        #expect(event.cid == "last-observed-revision")
        try database.write { db in
            try Event.find(uri).update { $0.name = event.name }.execute(db)
            let edited = try #require(try Event.find(uri).fetchOne(db))
            expectNoDifference(edited, event)
            try Event.find(uri).update { $0.cid = #bind("new-repository-revision" as ATProto.CID?) }.execute(db)
            #expect(try Event.find(uri).fetchOne(db)?.cid == "new-repository-revision")
            #expect(try EventChild.all.join(Event.all) { $0.event.eq($1.id) }.fetchAll(db).count == 1)
            if enforceForeignKey {
                #expect(throws: (any Error).self) { try Event.find(uri).delete().execute(db) }
                #expect(try EventChild.all.fetchCount(db) == 1)
            } else {
                try db.execute(
                    sql: "UPDATE \"events.openmusic.event\" SET id = ? WHERE id = ?",
                    arguments: ["at://did:plc:wickedwoods/events.example.other/3mrdbziccpcah", uri.description]
                )
                let invalidIdentity = try #require(try Event.all.fetchOne(db))
                #expect(throws: (any Error).self) { try invalidIdentity.encodeLexicon() }
                try db.execute(
                    sql: "UPDATE \"events.openmusic.event\" SET id = ?",
                    arguments: [uri.description]
                )
                try Event.find(uri).delete().execute(db)
                #expect(try EventChild.all.fetchCount(db) == 1)
            }
        }
    }

    @Test(arguments: ["description", "start", "end", "status", "mode", "locations", "links", "media", "programs", "schedules", "rsvpExpected", "categories", "siteMap"])
    func `optional fields accept explicit null`(_ field: String) throws {
        let event = try Event(id: uri, name: "Event", createdAt: "2026-09-15T00:00:00Z", timeZone: .gmt)
        var object = try #require(event.encodeLexicon().object)
        object[field] = .null
        let decoded = try Event.decodeLexicon(.object(object), metadata: .init(uri: uri))
        expectNoDifference(decoded, event)
        expectNoDifference(try decoded.encodeLexicon(), try event.encodeLexicon())
    }

    @Test
    func `the event preserves program tab order and festival day order`() throws {
        let music = try #require(ATProto.URI(
            "at://did:plc:wickedwoods/events.openmusic.program/3mrdbziccpcal"
        ))
        let workshops = try #require(ATProto.URI(
            "at://did:plc:wickedwoods/events.openmusic.program/3mrdbziccpcam"
        ))
        let friday = try #require(ATProto.URI(
            "at://did:plc:wickedwoods/events.openmusic.schedule/3mrdbziccpcan"
        ))
        let saturday = try #require(ATProto.URI(
            "at://did:plc:wickedwoods/events.openmusic.schedule/3mrdbziccpca2"
        ))
        let event = try Event(
            id: uri,
            name: "Wicked Woods",
            createdAt: "2026-09-15T00:00:00Z",
            timeZone: .gmt,
            programs: [music, workshops],
            schedules: [friday, saturday]
        )
        try event.validateReferences()
        expectNoDifference(try event.encodeLexicon().object?["programs"], .array([
            .string(music.description), .string(workshops.description),
        ]))
        expectNoDifference(try event.encodeLexicon().object?["schedules"], .array([
            .string(friday.description), .string(saturday.description),
        ]))
    }

    @Test
    func `event program and schedule references are unique records in its repository`() throws {
        let program = try #require(ATProto.URI(
            "at://did:plc:wickedwoods/events.openmusic.program/3mrdbziccpcal"
        ))
        var event = try Event(
            id: uri,
            name: "Wicked Woods",
            createdAt: "2026-09-15T00:00:00Z",
            timeZone: .gmt,
            programs: [program, program]
        )
        #expect(throws: ValidationError.self) { try event.validateReferences() }

        event.programs = [try #require(ATProto.URI(
            "at://did:plc:another/events.openmusic.program/3mrdbziccpcal"
        ))]
        #expect(throws: ValidationError.self) { try event.validateReferences() }
    }

    @Test(arguments: ["name", "createdAt", "timeZone", "$type"])
    func `required public record fields cannot disappear`(_ field: String) throws {
        var object = try #require(Event(id: uri, name: "Event", createdAt: "2026-09-15T00:00:00Z", timeZone: .gmt).encodeLexicon().object)
        object.removeValue(forKey: field)
        #expect {
            try Event.decodeLexicon(.object(object), metadata: .init(uri: uri))
        } throws: { error in
            guard case DecodingError.dataCorrupted(let context) = error else { return false }
            return context.codingPath.map(\.stringValue) == (field == "$type" ? [] : [field])
        }
    }

    @Test
    func `future union variants and known string values survive an unrelated edit`() throws {
        var object = try #require(Event(id: uri, name: "Event", createdAt: "2026-09-15T00:00:00Z", timeZone: .gmt).encodeLexicon().object)
        object["start"] = .object(["$type": "events.example.defs#season", "year": 2027])
        object["locations"] = .array([.object([
            "name": "Gate B",
            "locators": .array([.object(["$type": "events.example.defs#locator", "gate": "B"])]),
        ])])
        object["media"] = .array([.object([
            "$type": "events.example.defs#video", "url": "https://example.com/video.mp4",
            "metadata": .object(["caption": "Future media"]),
        ])])
        object["status"] = "events.example.defs#tentative"
        object["mode"] = "events.example.defs#broadcast"
        var event = try Event.decodeLexicon(.object(object), metadata: .init(uri: uri))
        event.name = "New name"
        object["name"] = "New name"
        expectNoDifference(try event.encodeLexicon(), .object(object))
    }

    @Test(arguments: [
        ("media", #"[{"$type":"events.openmusic.defs#image","source":{"$type":"events.openmusic.defs#imageURL"}}]"#),
        ("media", #"[{"url":"https://example.com/missing-type"}]"#),
        ("start", #"{"$type":"events.openmusic.defs#day","value":"2026-02-30"}"#),
        ("end", #"{"$type":"events.openmusic.defs#time","value":"yesterday"}"#),
        ("locations", #"[{"name":"Invalid","locators":[{"$type":"community.lexicon.location.address","country":"C"}]}]"#),
        ("locations", #"[{"name":"Invalid","locators":[{"$type":"events.example.defs#future","latitude":0.5}]}]"#),
        ("locations", #"[{"name":"Invalid","locators":[{"name":"Missing discriminator"}]}]"#),
    ])
    func `invalid known variants and non ATProto future payloads fail`(_ field: String, _ payload: String) throws {
        var object = try #require(Event(id: uri, name: "Event", createdAt: "2026-09-15T00:00:00Z", timeZone: .gmt).encodeLexicon().object)
        object[field] = try JSONDecoder().decode(Lexicon.JSONValue.self, from: Data(payload.utf8))
        #expect {
            try Event.decodeLexicon(.object(object), metadata: .init(uri: uri))
        } throws: { error in
            guard case DecodingError.dataCorrupted(let context) = error else { return false }
            return context.codingPath.first?.stringValue == field
        }
    }

    @Test
    func `every supported location uses its public discriminator`() throws {
        var event = try Event(id: uri, name: "Event", createdAt: "2026-09-15T00:00:00Z", timeZone: .gmt)
        event.locations = [
            .init(name: "Live stream", links: [.init(url: try #require(URL(string: "https://example.com/live")))]),
            .init(name: "Canada", locators: [.known(.address(.init(country: "CA")))]),
            .init(name: "Festival grounds", locators: [.known(.foursquare(.init(fsqPlaceID: "place-123")))]),
            .init(name: "Map pin", locators: [.known(.geo(.init(latitude: "50.5000", longitude: "-116.0000")))]),
            .init(name: "Map cell", locators: [.known(.hthree(.init(value: "8928308280fffff")))]),
        ]
        event.start = .known(.time(.init(value: "2026-09-15T12:34:56.123456789+02:00")))
        let json = try event.encodeLexicon()
        expectNoDifference(try Event.decodeLexicon(json, metadata: .init(uri: uri)), event)
        guard case .array(let locations) = json.object?["locations"] else {
            Issue.record("Expected all published locations")
            return
        }
        let locatorTypes = locations.map { location -> Lexicon.JSONValue? in
            guard case let .object(locationObject) = location,
                  case let .array(locators)? = locationObject["locators"],
                  case let .object(locator)? = locators.first
            else { return nil }
            return locator["$type"]
        }
        expectNoDifference(locatorTypes, [
            nil, "community.lexicon.location.address", "community.lexicon.location.fsq",
            "community.lexicon.location.geo", "community.lexicon.location.hthree",
        ])
        guard case let .object(linkLocation) = locations[0],
              case let .array(links)? = linkLocation["links"],
              case let .object(link)? = links.first,
              case let .object(foursquareLocation) = locations[2],
              case let .array(foursquareLocators)? = foursquareLocation["locators"],
              case let .object(foursquare)? = foursquareLocators.first,
              case let .object(geoLocation) = locations[3],
              case let .array(geoLocators)? = geoLocation["locators"],
              case let .object(geo)? = geoLocators.first
        else {
            Issue.record("Expected encoded location contents")
            return
        }
        expectNoDifference(link["url"], "https://example.com/live")
        expectNoDifference(foursquare["fsq_place_id"], "place-123")
        expectNoDifference(geo["latitude"], "50.5000")
    }

    @Test(arguments: [("timeZone", "Not/AZone"), ("createdAt", "yesterday"), ("$type", "events.example.other")])
    func `invalid scalar metadata is rejected at the record boundary`(_ field: String, _ value: String) throws {
        var object = try #require(Event(id: uri, name: "Event", createdAt: "2026-09-15T00:00:00Z", timeZone: .gmt).encodeLexicon().object)
        object[field] = .string(value)
        #expect {
            try Event.decodeLexicon(.object(object), metadata: .init(uri: uri))
        } throws: { error in
            guard case DecodingError.dataCorrupted(let context) = error else { return false }
            return context.codingPath.map(\.stringValue) == (field == "$type" ? [] : [field])
        }
    }

    @Test
    func `invalid values cannot be published after editing a decoded event`() throws {
        var event = try Event(id: uri, name: "Event", createdAt: "2026-09-15T00:00:00Z", timeZone: .gmt)
        event.locations = [.init(name: "Invalid", locators: [.known(.address(.init(country: "C")))])]
        #expect {
            try event.encodeLexicon()
        } throws: { error in
            guard case EncodingError.invalidValue(_, let context) = error else { return false }
            return context.codingPath.map(\.stringValue) == ["locations", "0", "locators", "0", "country"]
        }
    }

    @Test
    func `the exporter discovers the whole event and preserves authoritative location structure`() throws {
        let documents = try LexiconExporter.documents(for: [Event.self])
        expectNoDifference(Set(documents.map(\.id.rawValue)), [
            "events.openmusic.event", "events.openmusic.defs",
            "community.lexicon.location.address", "community.lexicon.location.geo",
            "community.lexicon.location.fsq", "community.lexicon.location.hthree",
        ])
        for document in documents where document.id.rawValue.hasPrefix("community.lexicon.") {
            let url = try #require(Bundle.module.url(forResource: document.id.rawValue, withExtension: "json", subdirectory: "Fixtures/CommunityLexicons"))
            let expected = schemaStructure(try JSONSerialization.jsonObject(with: Data(contentsOf: url)))
            let actual = schemaStructure(try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)))
            #expect((actual as? NSDictionary)?.isEqual(to: try #require(expected as? [AnyHashable: Any])) == true,
                    "Schema structure differs from pinned public document: \(document.id)")
        }
        let event = try #require(documents.first { $0.id.rawValue == "events.openmusic.event" })
        let record = try #require(Lexicon.JSONValue(encoding: event).object?["defs"]?.object?["main"]?.object?["record"]?.object)
        expectNoDifference(record["required"], .array(["name", "createdAt", "timeZone"]))
        expectNoDifference(record["nullable"], .array(["description", "start", "end", "status", "mode", "locations", "links", "media", "programs", "schedules", "rsvpExpected", "categories", "siteMap"]))
        expectNoDifference(record["properties"]?.object?["name"], .object([
            "description": "The public name of the event.",
            "type": "string", "minLength": 1, "maxLength": 5_000, "maxGraphemes": 500,
        ]))
        expectNoDifference(record["properties"]?.object?["timeZone"], .object([
            "description": "The IANA time-zone identifier used for calendar days and event-local schedule display.",
            "type": "string", "minLength": 1, "maxLength": 64,
        ]))
        expectNoDifference(record["properties"]?.object?["description"], .object([
            "description": "A public description of the event.",
            "type": "string", "maxLength": 30_000, "maxGraphemes": 3_000,
        ]))
        expectNoDifference(record["properties"]?.object?["media"], .object([
            "description": "Media attached to the event. Array order is the organizer's preferred display order.",
            "type": "array", "items": .object([
                "type": "union", "refs": .array([
                    "events.openmusic.defs#image",
                    "events.openmusic.defs#mediaRecord",
                    "events.openmusic.defs#externalMedia",
                ]),
            ]),
        ]))
        expectNoDifference(record["properties"]?.object?["programs"], .object([
            "description": "The event's attendee-facing programs in organizer-defined tab order.",
            "type": "array", "minLength": 1,
            "items": .object(["type": "string", "format": "at-uri"]),
        ]))
        expectNoDifference(record["properties"]?.object?["schedules"], .object([
            "description": "The event's organizer-defined festival days in attendee-facing order.",
            "type": "array", "minLength": 1,
            "items": .object(["type": "string", "format": "at-uri"]),
        ]))
        expectNoDifference(Set(try #require(record["properties"]?.object).keys), [
            "name", "createdAt", "timeZone", "description", "start", "end", "status", "mode",
            "locations", "links", "media", "programs", "schedules", "rsvpExpected", "categories", "siteMap",
        ])

        let definitions = try #require(documents.first { $0.id.rawValue == "events.openmusic.defs" })
        let definitionObjects = try #require(Lexicon.JSONValue(encoding: definitions).object?["defs"]?.object)
        let location = try #require(definitionObjects["location"]?.object)
        expectNoDifference(location["properties"]?.object?["name"], .object([
            "description": "The organizer's human-readable name for this event location.",
            "type": "string", "minLength": 1, "maxLength": 5_000, "maxGraphemes": 500,
        ]))
        expectNoDifference(location["properties"]?.object?["description"], .object([
            "description": "Event-specific information about this location, such as arrival guidance or an announcement status.",
            "type": "string", "maxLength": 30_000, "maxGraphemes": 3_000,
        ]))
        for removed in [
            "categoryConfig", "eventPolicies", "contributorPolicies", "scheduleContributors",
            "actorProfiles", "claimedArtistsOnly", "profileProvider",
        ] {
            #expect(definitionObjects[removed] == nil)
        }
    }

    @Test
    func `every OME definition and field describes its public meaning`() throws {
        let documents = try LexiconExporter.documents(for: [Event.self])
            .filter { $0.id.rawValue.hasPrefix("events.openmusic.") }

        for document in documents {
            let definitions = try #require(Lexicon.JSONValue(encoding: document).object?["defs"]?.object)
            for (definitionName, definition) in definitions {
                let definition = try #require(definition.object)
                #expect(definition["description"]?.string != nil, "Missing description for \(document.id)#\(definitionName)")

                let properties: [String: Lexicon.JSONValue]
                if definition["type"] == "record" {
                    properties = try #require(definition["record"]?.object?["properties"]?.object)
                } else {
                    properties = definition["properties"]?.object ?? [:]
                }
                for (fieldName, field) in properties {
                    #expect(
                        field.object?["description"]?.string != nil,
                        "Missing description for \(document.id)#\(definitionName).\(fieldName)"
                    )
                }
            }
        }
    }
}

// Reverse macro order from Event, to prove both composition orders.
@Lexicon("events.example.child", type: .record(key: .tid))
@Table("testChildren")
private struct EventChild: RecordCodable, Equatable {
    @LexiconIgnored @Column(primaryKey: true) let id: ATProto.URI
    @LexiconIgnored var cid: ATProto.CID? = nil
    var event: ATProto.URI
    @LexiconIgnored var localNote: String?
}

private func schemaStructure(_ value: Any) -> Any {
    if let object = value as? [String: Any] {
        return object.reduce(into: [String: Any]()) { result, element in
            guard element.key != "description", element.key != "nullable" else { return }
            result[element.key] = schemaStructure(element.value)
        }
    }
    if let array = value as? [Any] {
        return array.map(schemaStructure)
    }
    return value
}
