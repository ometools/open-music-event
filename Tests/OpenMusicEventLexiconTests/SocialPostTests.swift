import CustomDump
import Foundation
import ATProtoTypes
import ATProtoSQLite
@testable import OpenMusicEventLexicon
import Testing

@Suite
struct SocialPostTests {
    let postURI = ATProto.URI("at://did:plc:author/social.ome.post/3mrdbziccpcah")!
    let eventURI = ATProto.URI("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcai")!
    let categoryURI = ATProto.URI("at://did:plc:organizer/social.ome.category/3mrdbziccpcaj")!
    let syndicatedURI = ATProto.URI("at://did:plc:author/app.bsky.feed.post/3mrdbziccpcal")!
    let syndicatedCID: ATProto.CID = "bafyreibvlzqnyqbyq2xlxzyelbnzczd3i2cppmx7xghg42yyjz7dss6xju"
    let createdAt: ATProto.DateTime = "2026-09-23T18:00:00Z"

    @Test
    func `an account can publish a post without an event or category`() throws {
        let post = try Social.Post(
            id: postURI,
            text: "See you in the woods.",
            createdAt: createdAt
        )

        try post.validateReferences()
        expectNoDifference(try post.encodeLexicon(), .object([
            "$type": "social.ome.post",
            "text": "See you in the woods.",
            "createdAt": .string(createdAt.rawValue),
        ]))
    }

    @Test
    func `a post can target an event category and preserve Bluesky facets embeds and syndication`() throws {
        let facet = Social.Post.Facet([
            "index": .object([
                "byteStart": 0,
                "byteEnd": 5,
            ]),
            "features": .array([.object([
                "$type": "app.bsky.richtext.facet#link",
                "uri": "https://openmusic.events",
            ])]),
        ])
        let embed = Social.Post.Embed([
            "$type": "app.bsky.embed.external",
            "external": .object([
                "uri": "https://openmusic.events",
                "title": "Open Music Events",
                "description": "Find the event.",
                "thumb": .object([
                    "$type": "blob",
                    "ref": .object(["$link": "bafkreibvlzqnyqbyq2xlxzyelbnzczd3i2cppmx7xghg42yyjz7dss6xju"]),
                    "mimeType": "image/jpeg",
                    "size": 42,
                ]),
            ]),
        ])
        let post = try Social.Post(
            id: postURI,
            cid: "observed-post-revision",
            title: "Gates are open",
            text: "Gates are open. Welcome!",
            facets: [facet],
            embed: embed,
            event: eventURI,
            category: categoryURI,
            syndications: [.init(uri: syndicatedURI, cid: syndicatedCID)],
            createdAt: createdAt,
            updatedAt: "2026-09-23T18:05:00Z"
        )

        try post.validateReferences()
        expectNoDifference(
            try Social.Post.decodeLexicon(
                post.encodeLexicon(),
                metadata: .init(uri: postURI, cid: "observed-post-revision")
            ),
            post
        )
    }

    @Test
    func `a category is event scoped but the post remains account owned`() throws {
        var post = try Social.Post(
            id: postURI,
            text: "Category update",
            category: categoryURI,
            createdAt: createdAt
        )
        #expect(throws: ValidationError.self) { try post.validateReferences() }

        post.event = eventURI
        try post.validateReferences()

        post.category = try #require(ATProto.URI(
            "at://did:plc:another/social.ome.category/3mrdbziccpcaj"
        ))
        #expect(throws: ValidationError.self) { try post.validateReferences() }
    }

    @Test
    func `a post requires text or an embed and unique complete syndication references`() throws {
        var post = try Social.Post(id: postURI, text: "", createdAt: createdAt)
        #expect(throws: ValidationError.self) { try post.validateReferences() }

        post.embed = .init(["$type": "app.bsky.embed.images", "images": .array([])])
        try post.validateReferences()

        post.syndications = [
            .init(uri: syndicatedURI, cid: syndicatedCID),
            .init(uri: syndicatedURI, cid: syndicatedCID),
        ]
        #expect(throws: ValidationError.self) { try post.validateReferences() }
    }

    @Test
    func `the public schema reuses Bluesky facets and embeds without exporting them`() throws {
        let documents = try LexiconExporter.documents(for: [Social.Post.self])
        expectNoDifference(Set(documents.map(\.id.rawValue)), [
            "com.atproto.repo.strongRef",
            "social.ome.post",
        ])

        let document = try #require(documents.first { $0.id.rawValue == "social.ome.post" })
        guard case .record(let record) = document.defs["main"],
              case .object(let schema) = record.record
        else {
            Issue.record("Expected social.ome.post record schema")
            return
        }

        guard case .string(let delivery) = schema.properties["delivery"] else {
            Issue.record("Expected an open delivery string")
            return
        }
        expectNoDifference(delivery.knownValues, ["silent", "standard", "emergency"])
        #expect(delivery.values == nil)
        expectNoDifference(schema.required, ["text", "createdAt"])
        expectNoDifference(Set(schema.properties.keys), [
            "title",
            "text",
            "facets",
            "embed",
            "event",
            "category",
            "syndications",
            "createdAt",
            "updatedAt",
            "delivery",
        ])
        guard case .array(let facets) = schema.properties["facets"],
              case .ref(let facet) = facets.items,
              case .union(let embed) = schema.properties["embed"],
              case .string(let text) = schema.properties["text"]
        else {
            Issue.record("Expected rich post fields")
            return
        }
        expectNoDifference(facet.ref.resolved(relativeTo: Social.Post.lexiconID), "app.bsky.richtext.facet")
        expectNoDifference(embed.refs.map { $0.resolved(relativeTo: Social.Post.lexiconID).rawValue }, [
            "app.bsky.embed.images",
            "app.bsky.embed.video",
            "app.bsky.embed.gallery",
            "app.bsky.embed.external",
            "app.bsky.embed.record",
            "app.bsky.embed.recordWithMedia",
        ])
        expectNoDifference(text.maxLength, 100_000)
        expectNoDifference(text.maxGraphemes, 10_000)
    }
}
