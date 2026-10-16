import ATProto
import ATProtoAppView
import CustomDump
import Foundation
import OpenMusicEventLexicon
import Testing
@testable import OpenMusicEventAppViewServer

@Suite struct CommunityCalendarDomainAdapterTests {
    private func source(_ json: String) throws -> AppView.RecordVersion<Data> {
        try .init(collection: "community.lexicon.calendar.event",
              uri: try #require(ATProto.URI("at://did:plc:calendar/community.lexicon.calendar.event/3mrdbziccpcab")),
              cid: "bafy-original", value: Data(json.utf8), sequence: 1)
    }

    @Test func `import preserves source identity and exact midnight without inventing a zone`() throws {
        let source = try source(#"{"$type":"community.lexicon.calendar.event","name":"Midnight music","createdAt":"2026-08-01T12:00:00Z","startsAt":"2026-09-04T00:00:00Z","endsAt":"2026-09-04T12:00:00Z","locations":[{"$type":"community.lexicon.location.geo","latitude":"50.1","longitude":"-115.5"}]}"#)
        let result = try CommunityCalendarDomainAdapter.project(source)
        expectNoDifference(result.diagnostics, [])
        expectNoDifference(result.event.id, source.uri)
        expectNoDifference(result.event.cid, source.cid)
        #expect(result.event.timeZone == nil)
        #expect(result.event.locations?.first?.name == nil)
        expectNoDifference(result.event.start, .known(.time(.init(value: "2026-09-04T00:00:00Z"))))
        expectNoDifference(result.event.end, .known(.time(.init(value: "2026-09-04T12:00:00Z"))))
        let content = try result.event.domainContent()
        #expect(content.object?["timeZone"] == nil)
        #expect(content.object?["id"] == nil)
        #expect(content.object?["cid"] == nil)
        #expect(content.object?["projectionVersion"] == nil)
        #expect(throws: (any Error).self) { try result.event.validateReferences() }
        #expect(throws: (any Error).self) { try result.event.encodeLexicon() }
    }

    @Test func `invalid optional content is diagnosed while valid content survives`() throws {
        let result = try CommunityCalendarDomainAdapter.project(source(#"{"$type":"community.lexicon.calendar.event","name":"Music","createdAt":"2026-08-01T12:00:00Z","startsAt":"not a date","endsAt":"2026-09-04T12:00:00Z","customField":true}"#))
        #expect(result.event.start == nil)
        #expect(result.event.end != nil)
        expectNoDifference(result.diagnostics.map(\.path), ["startsAt", "customField"])
    }

    @Test func `invalid required content cannot become a valid looking replacement`() throws {
        let source = try source(#"{"$type":"community.lexicon.calendar.event","name":"Music","createdAt":{"date":"2026-08-01"}}"#)
        #expect(throws: (any Error).self) { try CommunityCalendarDomainAdapter.project(source) }
    }

    @Test func `URI locations have links without fabricated names`() throws {
        let result = try CommunityCalendarDomainAdapter.project(source(#"{"$type":"community.lexicon.calendar.event","name":"Music","createdAt":"2026-08-01T12:00:00Z","locations":[{"$type":"community.lexicon.calendar.event#uri","uri":"https://example.com/venue"}]}"#))
        let location = try #require(result.event.locations?.first)
        #expect(location.name == nil)
        #expect(location.locators == nil)
        expectNoDifference(location.links?.first?.url.absoluteString, "https://example.com/venue")
    }

    @Test func `source media roles map explicitly without discarding usable artwork`() throws {
        let record = try source(#"""
        {"$type":"community.lexicon.calendar.event","name":"Concert","createdAt":"2026-08-01T12:00:00Z",
         "media":[
           {"role":"poster","content":{"$type":"blob","ref":{"$link":"bafkreigdcl6knsg6xgvcsrmdehb37xwlstbvcv3kbbmrc37ormgg2ll3g4"},"mimeType":"image/webp","size":100}},
           {"role":"thumbnail","content":{"$type":"blob","ref":{"$link":"bafkreigdcl6knsg6xgvcsrmdehb37xwlstbvcv3kbbmrc37ormgg2ll3g4"},"mimeType":"image/webp","size":100}},
           {"content":{"$type":"blob","ref":{"$link":"bafkreigdcl6knsg6xgvcsrmdehb37xwlstbvcv3kbbmrc37ormgg2ll3g4"},"mimeType":"image/webp","size":100}}
         ]}
        """#)
        let result = try CommunityCalendarDomainAdapter.project(record)
        let media = try #require(result.event.media)
        #expect(media.count == 3)
        let roles = try media.map { value -> Open<OME.Image.Role>? in
            guard case let .known(.image(image)) = value else {
                throw ValidationError("Expected the source image to survive adaptation")
            }
            return image.role
        }
        expectNoDifference(roles, [.known(.poster), nil, nil])
        expectNoDifference(result.diagnostics, [.init(
            path: "media[1].role", message: "Unsupported image role retained in raw record"
        )])
    }
}
