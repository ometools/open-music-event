import Foundation
import OpenMusicEventLexicon
import Testing

@testable import OpenMusicEventApp

struct EventRowImageTests {
    @Test
    func `an event poster is shown before its icon fallback`() {
        let icon = imageAsset(role: .icon, url: "https://example.com/icon.png")
        let poster = imageAsset(role: .poster, url: "https://example.com/poster.png")

        #expect(EventRowView.imageAssets(icon: icon, poster: poster) == [poster, icon])
        #expect(EventRowView.imageAssets(icon: nil, poster: poster) == [poster])
        #expect(EventRowView.imageAssets(icon: icon, poster: nil) == [icon])
    }

    private func imageAsset(
        role: OME.ImageAsset.Role,
        url: String
    ) -> OME.ImageAsset {
        OME.ImageAsset(
            source: .url(URL(string: url)!),
            role: role,
            renderKind: .fullImage,
            materializationPolicy: .lazy
        )
    }
}
