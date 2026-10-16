import ATProtoTypes
import CustomDump
import Foundation
import OpenMusicEventLexicon
import Testing

@Suite
struct EventCommunicationTests {
    typealias Event = OpenMusicEventLexicon.Event
    typealias Category = Social.Category

    @Test
    func `a category cannot contradict required subscriptions or cross event ownership`() throws {
        let eventURI = try #require(ATProto.URI("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"))
        let categoryURI = try #require(ATProto.URI("at://did:plc:organizer/social.ome.category/3mrdbziccpcai"))
        var event = try Event(id: eventURI, name: "Event", createdAt: "2026-09-01T12:00:00Z", timeZone: .gmt)
        var category = try Category(
            id: categoryURI, event: eventURI, name: "Safety", createdAt: "2026-09-01T12:00:00Z",
            defaultNotificationState: .known(.unsubscribed), notificationsRequired: true
        )
        #expect(throws: ValidationError.self) { try category.validateReferences() }
        category.defaultNotificationState = .known(.subscribed)
        #expect(throws: ValidationError.self) { try category.validateGraph(event: event) }
        event.categories = [categoryURI]
        try category.validateGraph(event: event)

        event.categories = [categoryURI, categoryURI]
        #expect(throws: ValidationError.self) { try event.validateReferences() }
        event.categories = [try #require(ATProto.URI("at://did:plc:outsider/social.ome.category/3mrdbziccpcai"))]
        #expect(throws: ValidationError.self) { try event.validateReferences() }
        category.event = try #require(ATProto.URI("at://did:plc:outsider/events.openmusic.event/3mrdbziccpcah"))
        #expect(throws: ValidationError.self) { try category.validateReferences() }
    }

    @Test
    func `emergency intent requires organizer authority and a resolved category from the same event`() throws {
        let eventURI = try #require(ATProto.URI("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"))
        let categoryURI = try #require(ATProto.URI("at://did:plc:organizer/social.ome.category/3mrdbziccpcai"))
        let event = try Event(
            id: eventURI, name: "Event", createdAt: "2026-09-01T12:00:00Z", timeZone: .gmt,
            categories: [categoryURI]
        )
        var category = try Category(
            id: categoryURI, event: eventURI, name: "Safety", createdAt: "2026-09-01T12:00:00Z"
        )
        let post = try Social.Post(
            id: #require(ATProto.URI("at://did:plc:organizer/social.ome.post/3mrdbziccpcaj")),
            text: "Use the marked exit", event: eventURI, category: categoryURI,
            createdAt: "2026-09-04T12:00:00Z", delivery: .known(.emergency)
        )
        try post.validateGraph(event: event, category: category)
        let payload = try post.encodeLexicon()
        #expect(payload.object?["delivery"] == "emergency")
        expectNoDifference(try Social.Post.decodeLexicon(payload, metadata: .init(uri: post.id)), post)
        #expect(throws: ValidationError.self) { try post.validateGraph(event: event) }

        category.event = try #require(ATProto.URI("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcak"))
        #expect(throws: ValidationError.self) { try post.validateGraph(event: event, category: category) }

        var outsider = try Social.Post(
            id: #require(ATProto.URI("at://did:plc:attendee/social.ome.post/3mrdbziccpcaj")),
            text: "Attendee post", event: eventURI, category: categoryURI,
            createdAt: "2026-09-04T12:00:00Z", delivery: .known(.emergency)
        )
        #expect(throws: ValidationError.self) { try outsider.validateReferences() }
        outsider.delivery = .known(.silent)
        try outsider.validateReferences()
        outsider.delivery = .unknown("digest")
        try outsider.validateReferences()
        #expect(try outsider.encodeLexicon().object?["delivery"] == "digest")
        outsider.delivery = nil
        #expect(try outsider.encodeLexicon().object?["delivery"] == nil)
    }

    @Test
    func `renaming and reordering map styles preserves the selected identity`() throws {
        let publicImage = OME.Image(source: .known(.url(try #require(URL(string: "https://example.com/public-map.png")))), role: .known(.siteMap))
        let safetyImage = OME.Image(source: .known(.url(try #require(URL(string: "https://example.com/safety-map.png")))), role: .known(.siteMap))
        var map = Event.SiteMap(
            title: "Wicked Woods Map",
            styles: [
                .init(id: "public", title: "Public", image: publicImage),
                .init(id: "safety", title: "Safety", image: safetyImage),
            ],
            defaultStyleID: "safety"
        )
        try map.validate()
        map.styles.reverse()
        map.styles[0].title = "Safety and assistance"
        #expect(map.defaultStyle?.id == "safety")
        #expect(map.defaultStyle?.image == safetyImage)
        expectNoDifference(try Event.SiteMap.decodeLexicon(map.encodeLexicon()), map)

        // Removing the selected style requires choosing a valid default or clearing it.
        map.styles.removeFirst()
        #expect(throws: ValidationError.self) { try map.validate() }
        map.defaultStyleID = nil
        try map.validate()
        #expect(map.defaultStyle?.id == "public")
        #expect(try map.encodeLexicon().object?["defaultStyleID"] == nil)

        map.styles.append(map.styles[0])
        #expect(throws: ValidationError.self) { try map.validate() }
        map.styles = []
        #expect(throws: (any Error).self) { try map.validate() }
    }

    @Test
    func `public maps reject local image paths and preserve future image source payloads`() throws {
        var event = try Event(
            id: #require(ATProto.URI("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")),
            name: "Event", createdAt: "2026-09-01T12:00:00Z", timeZone: .gmt,
            siteMap: .init(title: "Map", styles: [
                .init(id: "public", title: "Public", image: .init(source: .known(.url(URL(fileURLWithPath: "/tmp/map.png"))))),
            ])
        )
        #expect(throws: ValidationError.self) { try event.validateReferences() }
        let unknown: Lexicon.JSONValue = ["$type": "maps.example.defs#tileSource", "uri": "https://example.com/tiles"]
        event.siteMap?.styles[0].image.source = .unknown(unknown)
        try event.validateReferences()
        expectNoDifference(try Event.decodeLexicon(event.encodeLexicon(), metadata: .init(uri: event.id)), event)
        event.siteMap = nil
        #expect(try event.encodeLexicon().object?["siteMap"] == nil)
    }
}
