import Foundation
import OpenMusicEventLexicon
import Testing

@Suite("Image assets")
struct ImageAssetTests {
    @Test
    func `legacy dimensions decode but are not stored again`() throws {
        let legacyData = Data(
            """
            {
              "source": {
                "url": "https://example.com/contributor.jpg"
              },
              "role": "photo",
              "renderKind": "fullImage",
              "materializationPolicy": "lazy",
              "dimensions": {
                "width": 1200,
                "height": 800
              },
              "focalPoint": {
                "x": 0.25,
                "y": 0.75
              }
            }
            """.utf8
        )

        // Existing databases and source files may still contain computed geometry.
        let asset = try JSONDecoder().decode(OME.ImageAsset.self, from: legacyData)
        #expect(asset.focalPoint == OME.ImageAsset.FocalPoint(x: 0.25, y: 0.75))

        // Saving the asset keeps only durable author intent.
        let encodedObject = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(asset))
                as? [String: Any]
        )
        #expect(encodedObject["dimensions"] == nil)
        #expect(encodedObject["focalPoint"] != nil)
    }
}
