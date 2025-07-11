import XCTest
@testable import OpenMusicEventParser
import CustomDump

import Testing
import CustomDump
import SnapshotTestingCustomDump
import InlineSnapshotTesting
import CoreModels
import FileTree

func expect<C: Conversion>(
    _ data: C.Input,
    toRoundtripUsing conversion: C,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
) throws where C.Input: Equatable  {
    let result = try conversion.unapply(conversion.apply(data))
    expectNoDifference(result, data, fileID: fileID, filePath: filePath, line: line, column: column)
}


struct YamlCodingTests {
    @Test
    func simpleEventInfo() throws {
        let yaml = Data("""
        version: "0.1.0" # Schema Version

        # General Information
        name: "Testival"
        address: "123 Festival Road, Music City"
        timeZone: "America/Seattle"

        # Images
        imageURL: "http://example.com/event-image.jpg"
        siteMapImageURL: "http://example.com/site-map.jpg"
        """.utf8)
        let result = try YMLConversion(EventConfiguration.EventInfoYaml.self).apply(yaml)
        assertInlineSnapshot(of: result, as: .customDump) {
            """
            EventConfiguration.EventInfoYaml(
              name: "Testival",
              address: "123 Festival Road, Music City",
              timeZone: "America/Seattle",
              iconImageURL: nil,
              imageURL: URL(http://example.com/event-image.jpg),
              siteMapImageURL: URL(http://example.com/site-map.jpg),
              startDate: nil,
              endDate: nil,
              contactNumbers: nil,
              stages: nil
            )
            """
        }

    }

    @Test
    func decodingSimpleStageInfo() throws {
        let yaml = Data("""
        - name: "Mystic Grove"
          color: 0x1DB954
          imageURL: "http://example.com/mystic-grove.jpg"

        - name: "Bass Haven"
          color: 0xFF5733
          imageURL: "http://example.com/bass-haven.jpg"

        - name: "Tranquil Meadow"
          color: 0x4287f5
        """.utf8)
        let result = try Conversions.YamlConversion([CoreModels.Stage.Draft].self).apply(yaml)
        assertInlineSnapshot(of: result, as: .customDump) {
            """
            [
              [0]: Stage.Draft(
                id: nil,
                musicEventID: nil,
                name: "Mystic Grove",
                sortIndex: nil,
                iconImageURL: nil,
                imageURL: URL(http://example.com/mystic-grove.jpg),
                color: Tagged(rawValue: 1947988),
                posterImageURL: nil,
                lineup: nil
              ),
              [1]: Stage.Draft(
                id: nil,
                musicEventID: nil,
                name: "Bass Haven",
                sortIndex: nil,
                iconImageURL: nil,
                imageURL: URL(http://example.com/bass-haven.jpg),
                color: Tagged(rawValue: 16734003),
                posterImageURL: nil,
                lineup: nil
              ),
              [2]: Stage.Draft(
                id: nil,
                musicEventID: nil,
                name: "Tranquil Meadow",
                sortIndex: nil,
                iconImageURL: nil,
                imageURL: nil,
                color: Tagged(rawValue: 4360181),
                posterImageURL: nil,
                lineup: nil
              )
            ]
            """
        }
    }

    @Test
    func decodeSimpleContactInfo() throws {
        let yaml = Data("""
        - phoneNumber: "+1234567890"
          title: "General Info"

        - phoneNumber: "+0987654321"
          title: "Emergency"
          description: "For emergencies only"
        """.utf8)
        let result = try Conversions.YamlConversion([CoreModels.MusicEvent.ContactNumber].self).apply(yaml)
        assertInlineSnapshot(of: result, as: .customDump) {
            """
            [
              [0]: MusicEvent.ContactNumber(
                phoneNumber: "+1234567890",
                title: "General Info",
                description: nil
              ),
              [1]: MusicEvent.ContactNumber(
                phoneNumber: "+0987654321",
                title: "Emergency",
                description: "For emergencies only"
              )
            ]
            """
        }
    }


    @Test
    func decodeSimpleSchedule() throws {
        let yaml = Data("""
        Bass Haven:
          - time: 10:00 PM
            artist: "Prism Sound"

          - time: 11:30 PM
            title: "Subsonic B2B Sylvan"
            artists:
               - "Subsonic"
               - "Sylvan Beats"

          - time: "12:30 AM"
            endTime: "2:00 AM"
            artist: "Space Chunk"

        Mystic Grove:
          - time: "4:30 PM"
            artist: "Sunspear"

          - time: "6:30 PM"
            artist: "Phantom Groove"

          - time: "10:30 PM"
            artist: "Oaktrail"

          - time: "12:00 AM"
            endTime: "4:00 AM"
            artist: "Rhythmbox"

        Tranquil Meadow:
          - time: "3:00 PM"
            artist: "Float On"

          - time: "4:30 PM"
            artist: "Floods"

          - time: "04:00 PM"
            endTime: "6:00 PM"
            artist: "Overgrowth"

          - time: "1:00 AM"
            endTime: "2:00 AM"
            artist: "The Sleepies"
            title: "The Wind Down"
        """.utf8)

        let result = try YMLConversion<Schedule.YamlRepresentation>().apply(yaml)

        assertInlineSnapshot(of: result, as: .customDump) {
            """
            (extension in OpenMusicEventParser):Schedule.YamlRepresentation(
              customTitle: nil,
              date: nil,
              performances: [
                "Bass Haven": [
                  [0]: (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                    title: nil,
                    artist: "Prism Sound",
                    artists: nil,
                    time: ScheduleTime(
                      hour: 22,
                      minute: 0
                    ),
                    endTime: nil
                  ),
                  [1]: (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                    title: "Subsonic B2B Sylvan",
                    artist: nil,
                    artists: [
                      [0]: "Subsonic",
                      [1]: "Sylvan Beats"
                    ],
                    time: ScheduleTime(
                      hour: 23,
                      minute: 30
                    ),
                    endTime: nil
                  ),
                  [2]: (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                    title: nil,
                    artist: "Space Chunk",
                    artists: nil,
                    time: ScheduleTime(
                      hour: 0,
                      minute: 30
                    ),
                    endTime: ScheduleTime(
                      hour: 2,
                      minute: 0
                    )
                  )
                ],
                "Mystic Grove": [
                  [0]: (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                    title: nil,
                    artist: "Sunspear",
                    artists: nil,
                    time: ScheduleTime(
                      hour: 16,
                      minute: 30
                    ),
                    endTime: nil
                  ),
                  [1]: (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                    title: nil,
                    artist: "Phantom Groove",
                    artists: nil,
                    time: ScheduleTime(
                      hour: 18,
                      minute: 30
                    ),
                    endTime: nil
                  ),
                  [2]: (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                    title: nil,
                    artist: "Oaktrail",
                    artists: nil,
                    time: ScheduleTime(
                      hour: 22,
                      minute: 30
                    ),
                    endTime: nil
                  ),
                  [3]: (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                    title: nil,
                    artist: "Rhythmbox",
                    artists: nil,
                    time: ScheduleTime(
                      hour: 0,
                      minute: 0
                    ),
                    endTime: ScheduleTime(
                      hour: 4,
                      minute: 0
                    )
                  )
                ],
                "Tranquil Meadow": [
                  [0]: (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                    title: nil,
                    artist: "Float On",
                    artists: nil,
                    time: ScheduleTime(
                      hour: 15,
                      minute: 0
                    ),
                    endTime: nil
                  ),
                  [1]: (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                    title: nil,
                    artist: "Floods",
                    artists: nil,
                    time: ScheduleTime(
                      hour: 16,
                      minute: 30
                    ),
                    endTime: nil
                  ),
                  [2]: (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                    title: nil,
                    artist: "Overgrowth",
                    artists: nil,
                    time: ScheduleTime(
                      hour: 16,
                      minute: 0
                    ),
                    endTime: ScheduleTime(
                      hour: 18,
                      minute: 0
                    )
                  ),
                  [3]: (extension in OpenMusicEventParser):Performance.YamlRepresentation(
                    title: "The Wind Down",
                    artist: "The Sleepies",
                    artists: nil,
                    time: ScheduleTime(
                      hour: 1,
                      minute: 0
                    ),
                    endTime: ScheduleTime(
                      hour: 2,
                      minute: 0
                    )
                  )
                ]
              ]
            )
            """
        }

        
    }


    @Test
    func decodeReallySimpleSchedule() throws {
        let yaml = Data("""
        Bass:
          - time: '10:00 PM'
            artist: "Prism Sound"
        """.utf8)

        struct Performance: Codable {
            let time: ScheduleTime
            let artist: String
        }

        let result = try Conversions.YamlConversion<[String: [Performance]]>().apply(yaml)

    }

    @Test
    func decodingSimpleArtistFrontMatter() throws {
        let yaml = Data("""
            imageURL: http://example.com/subsonic.jpg
            links:
            - url: http://soundcloud.com/subsonic
            - url: http://instagram.com/subsonic
        """.utf8)

        let expectedResult = ArtistConversion.ArtistInfoFrontMatter(
            imageURL: .init(string: "http://example.com/subsonic.jpg"),
            links: [
                .init(url: URL(string: "http://soundcloud.com/subsonic")!),
                .init(url: URL(string: "http://instagram.com/subsonic")!)
            ]
        )

        let result = try Conversions.YamlConversion<ArtistConversion.ArtistInfoFrontMatter>().apply(yaml)
        assertInlineSnapshot(of: result, as: .customDump) {
            """
            ArtistConversion.ArtistInfoFrontMatter(
              imageURL: URL(http://example.com/subsonic.jpg),
              logoURL: nil,
              kind: nil,
              links: [
                [0]: Artist.Link(
                  url: URL(http://soundcloud.com/subsonic),
                  linkType: nil
                ),
                [1]: Artist.Link(
                  url: URL(http://instagram.com/subsonic),
                  linkType: nil
                )
              ]
            )
            """
        }

        expectNoDifference(result, expectedResult)

        try expect(expectedResult, toRoundtripUsing: Conversions.YamlConversion<ArtistConversion.ArtistInfoFrontMatter>().inverted())

    }
}

struct ArtistDecodingTests {
    @Test(.tags(.frontmatter))
    func decodingStandardArtistFile() throws {
        let markdown = """
        ---
        imageURL: http://example.com/subsonic.jpg
        links:
        - url: http://soundcloud.com/subsonic
        - url: http://instagram.com/subsonic
        ---
        Subsonic delivers powerful bass-driven music that shakes the ground and moves the crowd, known for their high-energy performances and deep, resonant beats.
        """

        var text = Substring(markdown)
        let parser = MarkdownWithFrontMatter<ArtistConversion.ArtistInfoFrontMatter>.Parser()
        let dto = try parser.parse(&text)

        assertInlineSnapshot(of: dto, as: .customDump) {
            """
            MarkdownWithFrontMatter(
              frontMatter: ArtistConversion.ArtistInfoFrontMatter(
                imageURL: URL(http://example.com/subsonic.jpg),
                logoURL: nil,
                kind: nil,
                links: [
                  [0]: Artist.Link(
                    url: URL(http://soundcloud.com/subsonic),
                    linkType: nil
                  ),
                  [1]: Artist.Link(
                    url: URL(http://instagram.com/subsonic),
                    linkType: nil
                  )
                ]
              ),
              body: "Subsonic delivers powerful bass-driven music that shakes the ground and moves the crowd, known for their high-energy performances and deep, resonant beats."
            )
            """
        }

        try parser.print(dto, into: &text)
        #expect(Substring(markdown) == text)
    }

    @Test(.tags(.frontmatter))
    func decodingArtistFileWithNoFrontmatterRoundtripping() throws {
        let markdown = """
        Subsonic delivers powerful bass-driven music that shakes the ground and moves the crowd, known for their high-energy performances and deep, resonant beats.
        """

        var text = Substring(markdown)
        let parser = MarkdownWithFrontMatter<ArtistConversion.ArtistInfoFrontMatter>.Parser()
        let dto = try parser.parse(&text)

        assertInlineSnapshot(of: dto, as: .customDump) {
            """
            MarkdownWithFrontMatter(
              frontMatter: nil,
              body: "Subsonic delivers powerful bass-driven music that shakes the ground and moves the crowd, known for their high-energy performances and deep, resonant beats."
            )
            """
        }

        try parser.print(dto, into: &text)
        #expect(markdown == text)
    }
}

