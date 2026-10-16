import CustomDump
import ATProtoTypes
import ATProtoSQLite
import OpenMusicEventLexicon
import Testing

@Suite
struct SemanticIconTests {
    @Test
    func `known icons describe depicted pictograms`() {
        expectNoDifference(
            OME.SemanticIcon.knownValues.map(\.rawValue),
            [
                "calendar",
                "heart",
                "thumbsUp",
                "personDoingYoga",
                "speechBubbles",
                "gridOfSquares",
            ]
        )
    }

    @Test
    func `known and future icons round trip as strings`() throws {
        // A client encodes a known icon without publishing a platform symbol name.
        expectNoDifference(try OME.SemanticIcon.calendar.encodeLexicon(), "calendar")
        expectNoDifference(
            try OME.SemanticIcon.decodeLexicon("calendar"),
            .calendar
        )

        // A newer icon remains intact even when this client does not recognize it.
        let futureIcon = OME.SemanticIcon(rawValue: "personDancing")
        expectNoDifference(try futureIcon.encodeLexicon(), "personDancing")
        expectNoDifference(
            try OME.SemanticIcon.decodeLexicon("personDancing"),
            futureIcon
        )
    }

    @Test
    func `the exported vocabulary is open and contains no platform identifiers`() throws {
        let documents = try LexiconExporter.documents(for: [OME.SemanticIcon.self])
        expectNoDifference(documents.count, 1)
        let document = try #require(documents.first)
        expectNoDifference(document.id.rawValue, "events.openmusic.defs")
        let definitions = try #require(
            Lexicon.JSONValue(encoding: document).object?["defs"]?.object
        )
        expectNoDifference(definitions["semanticIcon"], .object([
            "type": "string",
            "description": "A platform-neutral name for a familiar pictogram. Values describe the depicted object or gesture, not the purpose assigned to it by a product.",
            "knownValues": .array(OME.SemanticIcon.knownValues.map { .string($0.rawValue) }),
        ]))
        #expect(definitions["semanticIcon"]?.object?["enum"] == nil)
    }
}
