import CustomDump
import Foundation
import ATProtoTypes
import ATProtoSQLite
import OpenMusicEventLexicon
import Testing

@Suite
struct ColorTests {
    @Test(arguments: [0, 0xFF0000, 0x00FF00, 0x0000FF, 0x336699, 0xFFFFFF])
    func publishedColorsRoundTripAsIntegers(rawValue: Int) throws {
        // Black, primary channels, a stage color, and white retain every RGB bit.
        let color = try #require(OME.Color(rawValue: rawValue))
        let wire = try color.encodeLexicon()
        expectNoDifference(wire, .integer(Int64(rawValue)))
        expectNoDifference(try OME.Color.decodeLexicon(wire), color)
        expectNoDifference(try JSONDecoder().decode(OME.Color.self, from: JSONEncoder().encode(color)), color)
        try SchemaValidator().validate(wire, against: OME.Color.lexiconDefinition, id: OME.Color.lexiconID)
    }

    @Test(arguments: [-1, 0x1000000, 0xFF336699, Int.min, Int.max])
    func invalidColorsCannotBeConstructedOrDecoded(rawValue: Int) throws {
        // Extra high bits must never silently become a different visible color.
        expectNoDifference(OME.Color(rawValue: rawValue), nil)
        let wire = Lexicon.JSONValue.integer(Int64(rawValue))
        #expect(throws: (any Error).self) { try OME.Color.decodeLexicon(wire) }
        #expect(throws: ValidationError.self) {
            try SchemaValidator().validate(wire, against: OME.Color.lexiconDefinition, id: OME.Color.lexiconID)
        }
    }

    @Test(arguments: ["\"#336699\"", "\"0x336699\"", "\"3368601\"", "1.5", "true", "null", "{}", "[]"])
    func publicDecodingRejectsAuthoringTextAndOtherNonIntegers(json: String) {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(OME.Color.self, from: Data(json.utf8))
        }
    }

    @Test
    func optionalColorIsUnspecifiedWhileZeroIsBlack() throws {
        // Exercise the real authoring macro on a field without introducing a Stage record.
        for wire: Lexicon.JSONValue in [.object([:]), .object(["color": .null])] {
            let appearance = try ColorAppearance.decodeLexicon(wire)
            expectNoDifference(appearance.color, nil)
            expectNoDifference(try appearance.encodeLexicon(), .object([:]))
        }
        let black = try ColorAppearance.decodeLexicon(.object(["color": 0]))
        expectNoDifference(black.color?.rawValue, 0)
        expectNoDifference(try black.encodeLexicon(), .object(["color": 0]))
        #expect(throws: (any Error).self) {
            try ColorAppearance.decodeLexicon(.object(["color": 16777216]))
        }
    }

    @Test
    func exporterIncludesTheBoundedSharedDefinitionAndFieldReference() throws {
        let documents = try LexiconExporter.documents(for: [ColorAppearance.self])
        let shared = try #require(documents.first { $0.id.rawValue == "events.openmusic.defs" })
        let definitions = try #require(Lexicon.JSONValue(encoding: shared).object?["defs"]?.object)
        expectNoDifference(definitions["color"], .object([
            "type": "integer",
            "description": "An opaque 24-bit sRGB color encoded as red × 65536 + green × 256 + blue, with each channel from 0 through 255.",
            "minimum": 0,
            "maximum": 16777215,
        ]))
        let fixture = try #require(documents.first { $0.id.rawValue == "events.openmusic.test" })
        let appearance = try #require(Lexicon.JSONValue(encoding: fixture).object?["defs"]?.object?["colorAppearance"]?.object)
        expectNoDifference(appearance["properties"]?.object?["color"], .object([
            "type": "ref", "ref": "events.openmusic.defs#color",
        ]))
        expectNoDifference(appearance["nullable"], .array(["color"]))
        #expect(appearance["required"] == nil || appearance["required"] == .array([]))
    }
}

@Lexicon("events.openmusic.test#colorAppearance")
struct ColorAppearance {
    var color: OME.Color? = nil
}
