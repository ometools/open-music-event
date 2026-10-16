import ATProto
import Dependencies
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import SQLiteData
import Testing

@Suite
struct CanonicalImageBlobStagingTests {
    @Test
    func importedImageBytesKeepTheirCIDAndCanBeReadForPublication() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ome-canonical-image-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileStore = LocalImageFileStoreClient(
            existingFileURL: { key, _ in
                let url = directory.appending(path: key).appendingPathExtension("png")
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            },
            write: { key, data, _ in
                let url = directory.appending(path: key).appendingPathExtension("png")
                try data.write(to: url, options: .atomic)
                return url
            }
        )

        try withDependencies {
            $0.localImageFileStore = fileStore
        } operation: {
            let bytes = Data("Wicked Woods".utf8)
            let blob = try stageLocalImageBlob(bytes, mimeType: .png)
            #expect(blob.ref.rawValue == "bafkreifcu6blc4yl7etxhjohn3tm2jopmz2vvxlqfgckqujm4g74adf46y")
            #expect(blob.mimeType == .png)
            #expect(blob.size == bytes.count)
            let stagedURL = try #require(try stagedLocalImageBlobURL(for: blob))
            #expect(try Data(contentsOf: stagedURL) == bytes)

            let database = try DatabaseQueue()
            var migrator = DatabaseMigrator()
            OME.DatabaseMigrations.register(into: &migrator)
            try migrator.migrate(database)
            let eventID = try #require(Event.ID(
                "at://did:plc:organizer/events.openmusic.event/3mrdbziccpcah"
            ))
            let event = try Event(
                id: eventID,
                name: "Wicked Woods",
                createdAt: "2026-09-01T12:00:00Z",
                timeZone: #require(TimeZone(identifier: "America/Denver"))
            )
            try database.write { try Event.insert { event }.execute($0) }
            let image = OME.Image(source: .known(.blob(blob)), role: .known(.photo))
            let contributorID = try database.write { db in
                try ContributorRecordEditing.create(
                    eventID: eventID,
                    fields: .init(name: "The Woods Collective", media: [.known(.image(image))]),
                    createdAt: try Date("2026-09-02T18:00:00Z", strategy: .iso8601),
                    in: db
                )
            }
            let contributor = try database.read {
                try #require(try Contributor.find(contributorID).fetchOne($0))
            }
            #expect(contributor.media == [.known(.image(image))])
        }
    }
}
