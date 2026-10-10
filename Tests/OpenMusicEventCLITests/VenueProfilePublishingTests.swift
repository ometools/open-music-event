import ATProto
import CustomDump
import Foundation
import Testing

@testable import OpenMusicEventCLI

@Suite struct VenueProfilePublishingTests {
    @Test func `venue profile uses the standard self record`() throws {
        let account = DID("did:plc:venue")!
        let publication = try VenueProfilePublication.prepare(
            account: account,
            displayName: "Gallatin Labor Temple",
            description: "Live music in Bozeman.",
            avatarURL: nil
        )
        expectNoDifference(publication.account, account)
        let record = try #require(publication.records.first)
        expectNoDifference(
            record.id,
            ATProto.URI("at://did:plc:venue/app.bsky.actor.profile/self")!
        )
        expectNoDifference(
            record.payload.object?["displayName"],
            .string("Gallatin Labor Temple")
        )
        expectNoDifference(
            record.payload.object?["description"],
            .string("Live music in Bozeman.")
        )
        #expect(record.images.isEmpty)
    }

    @Test func `venue profile stages its local avatar before the profile record`() throws {
        let avatar = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: avatar) }
        let bytes = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII="
        )!
        try bytes.write(to: avatar)
        let publication = try VenueProfilePublication.prepare(
            account: DID("did:plc:venue")!,
            displayName: "Gallatin Labor Temple",
            description: nil,
            avatarURL: avatar
        )
        let record = try #require(publication.records.first)
        expectNoDifference(record.images.map(\.bytes), [bytes])
        #expect(record.payload.object?["avatar"] != nil)
    }
}
