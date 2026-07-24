import CustomDump
import Foundation
import OpenMusicEventSource
import Testing

@testable import OpenMusicEventCLI

struct FestivalProImportTests {
    @Test
    func consolidatesDuplicateArtistProfilesByLowestContactID() throws {
        let export = try FestivalProExport(
            data: Data(
                """
                {
                  "contact9": {
                    "Contact ID": "9",
                    "Company Name": "Night Sky",
                    "Artist Bio": "Later bio",
                    "Artist Press Photo ID": "https://example.com/later.jpg",
                    "Soundcloud:": "https://soundcloud.com/night-sky"
                  },
                  "contact2": {
                    "Contact ID": "2",
                    "Company Name": "Night Sky",
                    "Artist Bio": "First bio",
                    "Artist Logo ID": "https://example.com/logo.png",
                    "Instagram": "https://instagram.com/night-sky"
                  },
                  "contact4": {
                    "Contact ID": "4",
                    "Company Name": "",
                    "Artist Bio": "Not a profile"
                  }
                }
                """.utf8
            )
        )

        let importer = FestivalProContributorImporter()
        let contributors = try importer.contributors(from: export)

        let contributor = try #require(contributors.first)
        expectNoDifference(contributor.fileName, "Night Sky")
        expectNoDifference(contributor.data.name, "Night Sky")
        expectNoDifference(contributor.data.bio, "First bio")
        expectNoDifference(
            contributor.data.images,
            [
                SourceImageAsset(
                    source: .url(URL(string: "https://example.com/later.jpg")!),
                    role: .photo,
                    renderKind: .fullImage,
                    materializationPolicy: .lazy
                ),
                SourceImageAsset(
                    source: .url(URL(string: "https://example.com/logo.png")!),
                    role: .logo,
                    renderKind: .transparent,
                    materializationPolicy: .lazy
                ),
            ]
        )
        expectNoDifference(
            contributor.data.links?.map { ($0.url.absoluteString, $0.platform?.rawValue) },
            [
                ("https://instagram.com/night-sky", "instagram"),
                ("https://soundcloud.com/night-sky", "soundcloud"),
            ]
        )
        expectNoDifference(
            importer.summary(for: export, contributors: contributors),
            FestivalProImportSummary(
                contactCount: 3,
                contributorCount: 1,
                contributorNamesWithoutProfiles: 1
            )
        )
    }
}
