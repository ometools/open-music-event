import CustomDump
import Foundation
import ATProtoTypes
import ATProtoSQLite
import OpenMusicEventLexicon
import Testing

@Suite
struct MediaTests {
    @Test
    func `media supports embedded images AT Protocol records and external links`() throws {
        let image = OME.Image(
            source: .known(.url(try #require(URL(string: "https://example.com/wicked-woods.jpg"))))
        )
        let recordURI = try #require(ATProto.URI(
            "at://did:plc:streamplace/place.stream.video/3mrdbziccpcaj"
        ))
        let youtube = try OME.Media.External(
            uri: #require(URL(string: "https://www.youtube.com/watch?v=wicked-woods")),
            title: "Wicked Woods Live",
            description: "The complete set",
            thumbnail: image,
            mediaKind: .known(.video)
        )
        let media: [Open<OME.Media>] = [
            .known(.image(image)),
            .known(.record(.init(uri: recordURI))),
            .known(.external(youtube)),
        ]

        let encoded = try media.map { try $0.encodeLexicon() }
        expectNoDifference(encoded.map { $0.object?["$type"] }, [
            "events.openmusic.defs#image",
            "events.openmusic.defs#mediaRecord",
            "events.openmusic.defs#externalMedia",
        ])
        expectNoDifference(encoded[1].object?["uri"], .string(recordURI.description))
        expectNoDifference(encoded[2].object?["uri"], "https://www.youtube.com/watch?v=wicked-woods")
        expectNoDifference(encoded[2].object?["mediaKind"], "video")
        expectNoDifference(
            try encoded.map { try $0.decoded(as: Open<OME.Media>.self) },
            media
        )
        for case .known(let value) in media { try value.validateForPublication() }
    }

    @Test
    func `publication requires stable record addresses and public external URLs`() throws {
        let handleRecord = try OME.Media.record(.init(uri: #require(ATProto.URI(
            "at://stream.place/place.stream.video/3mrdbziccpcaj"
        ))))
        #expect(throws: ValidationError.self) { try handleRecord.validateForPublication() }

        let incompleteRecord = try OME.Media.record(.init(uri: #require(ATProto.URI("at://did:plc:streamplace"))))
        #expect(throws: ValidationError.self) { try incompleteRecord.validateForPublication() }

        let insecure = try OME.Media.external(.init(
            uri: #require(URL(string: "http://soundcloud.com/wicked-woods/live")),
            mediaKind: .known(.audio)
        ))
        #expect(throws: ValidationError.self) { try insecure.validateForPublication() }
    }

    @Test(arguments: [
        #"{"$type":"events.openmusic.defs#mediaRecord","uri":42}"#,
        #"{"$type":"events.openmusic.defs#externalMedia","uri":42}"#,
        #"{"$type":"events.openmusic.defs#externalMedia","uri":"https://example.com","mediaKind":42}"#,
    ])
    func `malformed known media cannot become unknown variants`(_ payload: String) throws {
        let value = try JSONDecoder().decode(Lexicon.JSONValue.self, from: Data(payload.utf8))
        #expect(throws: (any Error).self) { try value.decoded(as: Open<OME.Media>.self) }
    }

    @Test
    func `media schema stays open without publishing a provider registry`() throws {
        let documents = try LexiconExporter.documents(for: [
            OME.Media.External.self,
            OME.Media.RecordReference.self,
            OME.Image.self,
        ])
        let defs = try #require(documents.first { $0.id.rawValue == "events.openmusic.defs" })
        let definitions = try #require(Lexicon.JSONValue(encoding: defs).object?["defs"]?.object)
        expectNoDifference(Set(definitions.keys), [
            "externalMedia", "focalPoint", "heroImage", "iconImage", "image",
            "imageBlob", "imageURL", "logoImage", "mediaRecord",
            "photoImage", "posterImage", "siteMapImage",
        ])
        let external = try #require(definitions["externalMedia"]?.object)
        expectNoDifference(Set(try #require(external["properties"]?.object).keys), [
            "uri", "title", "description", "thumbnail", "mediaKind",
        ])
        #expect(definitions["externalPlatform"] == nil)
    }
}
