import Foundation
import OpenMusicEventImages
import OpenMusicEventLexicon
import Testing

@testable import OpenMusicEventApp

struct EventRowImageTests {
    @Test
    func `an event poster is shown before its icon fallback`() throws {
        let event = try Event(
            id: try #require(Event.ID("at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah")),
            name: "Wicked Woods",
            createdAt: "2026-09-01T12:00:00Z",
            timeZone: try #require(TimeZone(identifier: "America/Denver")),
            media: [
                .known(.image(OME.Image(
                    source: .known(.url(try #require(URL(string: "https://example.com/icon.png")))),
                    role: .known(.icon(.init()))
                ))),
                .known(.image(OME.Image(
                    source: .known(.url(try #require(URL(string: "https://example.com/poster.png")))),
                    role: .known(.poster)
                )))
            ]
        )
        #expect(event.heroImageSources.map(\.image.role) == [.poster, .icon(.init())])
    }
}
