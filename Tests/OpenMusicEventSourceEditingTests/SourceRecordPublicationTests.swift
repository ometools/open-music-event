import ATProto
import CustomDump
import Dependencies
import HTTPClient
import FileTree
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import Testing
@testable import OpenMusicEventSourceEditing

@Suite struct SourceRecordPublicationTests {
    @Test(arguments: ["events.openmusic.contributor", "events.openmusic.programItem", "social.ome.post"])
    func `live readback requests the published collection and CID`(collection: String) async throws {
        let id = try #require(ATProto.URI("at://did:plc:organizer/\(collection)/3mx6isyz5jy22"))
        let cid: ATProto.CID = "bafyreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku"
        let payload: Lexicon.JSONValue = .object(["$type": .string(collection)])
        let observed = try await withDependencies {
            $0[XRPC.Client.self] = .liveValue
            $0[ATProto.Repository.PDSHostResolver.self] = .init { _ in "publisher.example.test" }
            $0.httpClient = HTTPClient { request, body in
                let url = try #require(request.url)
                #expect(url.host == "publisher.example.test")
                #expect(url.path == "/xrpc/com.atproto.repo.getRecord")
                #expect(body == nil)
                let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
                let values = Dictionary(uniqueKeysWithValues: (query.queryItems ?? []).map { ($0.name, $0.value) })
                #expect(values["collection"] == collection)
                #expect(values["cid"] == cid.rawValue)
                let response: Lexicon.JSONValue = .object(["uri": .string(id.description), "cid": .string(cid.rawValue), "value": payload])
                return try JSONEncoder().encode(response)
            }
        } operation: {
            try await SourceRecordPublisher.liveValue.read(id, cid)
        }
        expectNoDifference(observed.uri, id)
        expectNoDifference(observed.value, payload)
    }

    let bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=")!

    func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let files = [
            "events/2026/event.yml": "name: Wicked Woods 2026\ntimeZone: America/Denver\nstartDate: '2026-09-04'\n",
            "events/2026/contributors/artist.md": "---\nname: Artist\ndid: did:plc:artist\n---\nArtist biography.\n",
            "events/2026/stages/main.yml": "name: Main Stage\ncolor: 1122867\nsortIndex: 1\nlineup: [artist]\n",
            "events/2026/stages/workshops.yml": "name: Workshop Grove\ncolor: 2236962\ncategory: Workshops\nsortIndex: 2\n",
            "events/2026/schedules/friday.yml": """
            date: '2026-09-04'
            customTitle: Friday
            scheduleItems:
              main:
                - kind: performance
                  id: opening
                  title: Opening set
                  startTime: '23:00'
                  contributors:
                    - id: artist
                - kind: performance
                  id: late
                  title: Late set
                  startTime: '01:00'
                  endTime: '02:00'
              workshops:
                - kind: performance
                  id: workshop
                  title: Movement
                  startTime: '14:00'
                  endTime: '15:00'
            """,
            "events/2026/channels/General.yml": "name: General\ndescription: Updates\ndefaultNotificationState: subscribed\nnotificationsRequired: false\n",
            "events/2026/communications/General/welcome.md": "---\ntitle: Welcome\nisPinned: true\ndelivery: silent\nheaderImageURL: https://example.test/header.png\n---\nWelcome to the woods!\n",
            "events/2026/posters/lineup.yml": "title: Lineup\nimage:\n  role: poster\n  renderKind: fullImage\n  materializationPolicy: lazy\n  source: {url: 'https://example.test/lineup.png'}\n",
            "events/2026/maps/main.yml": "title: Festival Map\ndefaultStyleID: public\nstyles:\n  - id: public\n    title: Public\n    image:\n      source: {file: 'maps/public.png'}\n",
        ]
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try bytes.write(to: root.appendingPathComponent("events/2026/maps/public.png"))
        return root
    }
    func prepare(_ root: URL, identities: inout SourcePublicationIdentities, preserveLinkText: Bool = false) async throws -> SourceRecordPublication {
        let read = try OpenMusicEventSourceRepositoryFileTree().read(from: root)
        #expect(!read.output.isInvalid, "\(read.diagnostics.diagnostics.map(\.message))")
        let source = try read.output.requiredValue
        let event = try Event(id: #require(ATProto.URI("at://did:plc:organizer/events.openmusic.event/3mx6isyz5jy22")),
            name: "Wicked Woods 2026", createdAt: "2026-10-06T03:35:50Z", timeZone: #require(TimeZone(identifier: "America/Denver")))
        return try await SourceRecordPublication.prepare(source: source, sourceRoot: root, events: ["2026": event], identities: &identities, preserveLinkText: preserveLinkText) { _ in bytes }
    }
    func decode<R: RecordCodable>(_ type: R.Type, _ record: SourceRecordPublication.Record) throws -> R {
        try R.decodeLexicon(record.payload, metadata: .init(uri: record.id))
    }

    @Test func `publishes the complete source graph with overnight times credits pinned posts posters and map blobs`() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var identities = SourcePublicationIdentities()
        let publication = try await prepare(root, identities: &identities)
        expectNoDifference(publication.records.count, 12)
        let records = Dictionary(grouping: publication.records, by: { $0.id.collection!.rawValue })
        let event = try decode(Event.self, #require(records["events.openmusic.event"]?.first))
        let contributor = try decode(Contributor.self, #require(records["events.openmusic.contributor"]?.first))
        expectNoDifference(contributor.subject, DID("did:plc:artist"))
        expectNoDifference(contributor.description, "Artist biography.\n")
        expectNoDifference(event.id, publication.records.last?.id)
        expectNoDifference(event.programs?.count, 2)
        expectNoDifference(event.schedules?.count, 1)
        expectNoDifference(event.siteMap?.defaultStyleID, "public")
        #expect(event.media?.contains { if case .known(.image(let image)) = $0 { return image.title == "Lineup" }; return false } == true)
        let items = try #require(records["events.openmusic.programItem"]).map { try decode(ProgramItem.self, $0) }
        let opening = try #require(items.first { $0.title == "Opening set" })
        let late = try #require(items.first { $0.title == "Late set" })
        expectNoDifference(opening.startsAt?.rawValue, "2026-09-05T05:00:00Z")
        expectNoDifference(opening.endsAt, late.startsAt)
        expectNoDifference(late.startsAt?.rawValue, "2026-09-05T07:00:00Z")
        expectNoDifference(opening.credits?.first?.contributor, contributor.id)
        let post = try decode(Social.Post.self, #require(records["social.ome.post"]?.first))
        let category = try decode(Social.Category.self, #require(records["social.ome.category"]?.first))
        expectNoDifference(category.pinnedPosts, [post.id])
        expectNoDifference(post.delivery, .known(.silent))
        #expect(post.embed != nil)
        #expect(publication.records.contains { !$0.images.isEmpty })

        // Reloading the saved identity map preserves every URI, creation timestamp and payload.
        identities = try JSONDecoder().decode(SourcePublicationIdentities.self, from: JSONEncoder().encode(identities))
        let retry = try await prepare(root, identities: &identities)
        expectNoDifference(retry.records, publication.records)
    }

    @Test func `source domains normalize while ambiguous link text needs an explicit preservation choice`() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try "---\nname: Artist\nlinks:\n  - url: www.example.com\n    platform: website\n  - url: @unknown-account\n    platform: website\n---\nBiography.\n".replacingOccurrences(of: "url: @unknown-account", with: "url: \"@unknown-account\"")
            .write(to: root.appendingPathComponent("events/2026/contributors/artist.md"), atomically: true, encoding: .utf8)
        var identities = SourcePublicationIdentities()
        await #expect(throws: ValidationError.self) { try await prepare(root, identities: &identities) }
        let publication = try await prepare(root, identities: &identities, preserveLinkText: true)
        let record = try #require(publication.records.first { $0.id.collection?.rawValue == "events.openmusic.contributor" })
        let contributor = try decode(Contributor.self, record)
        expectNoDifference(contributor.links?.map(\.url.absoluteString), ["https://www.example.com"])
        #expect(contributor.description?.contains("website: @unknown-account") == true)
        #expect(!publication.diagnostics.isEmpty)
    }

    @Test func `missing stage lineup member is rejected before publication`() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try "name: Main Stage\ncolor: 1122867\nlineup: [missing]\n".write(to: root.appendingPathComponent("events/2026/stages/main.yml"), atomically: true, encoding: .utf8)
        var identities = SourcePublicationIdentities()
        await #expect(throws: (any Error).self) { try await prepare(root, identities: &identities) }
    }

    @Test func `failed child readback stops before publishing the parent and retry uses the same records`() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var identities = SourcePublicationIdentities()
        let publication = try await prepare(root, identities: &identities)
        let network = SourcePublicationNetwork()
        let failed = await network.publisher.publish(publication)
        expectNoDifference(failed.receipts.count, 0)
        expectNoDifference(failed.failures.count, 1)
        let written = await network.written
        expectNoDifference(written, [publication.records[0].id])
        await network.allowReadback()
        let completed = await network.publisher.publish(publication)
        expectNoDifference(completed.failures, [:])
        expectNoDifference(completed.receipts.map(\.id), publication.records.map(\.id))
        let uploads = await network.uploads
        expectNoDifference(uploads, 1)
    }
}

actor SourcePublicationNetwork {
    var rejectReadback = true
    var records: [ATProto.URI: Lexicon.JSONValue] = [:]
    var written: [ATProto.URI] = []
    var uploads = 0
    func allowReadback() { rejectReadback = false }
    nonisolated var publisher: SourceRecordPublisher {
        .init(put: { record, _ in await self.put(record) }, upload: { image, _ in await self.upload(image) }, read: { id, cid in await self.read(id, cid) })
    }
    func put(_ record: SourceRecordPublication.Record) -> ATProto.Repository.WriteRecordOutput {
        records[record.id] = record.payload; written.append(record.id)
        return .init(uri: record.id, cid: .init(rawValue: "bafy-fixture"))
    }
    func upload(_ image: EventRecordPublication.Image) -> ATProto.Blob { uploads += 1; return image.blob }
    func read(_ id: ATProto.URI, _ cid: ATProto.CID) -> ATProto.Repository.ListedRecord<Lexicon.JSONValue> {
        .init(uri: id, cid: cid, value: rejectReadback ? .object([:]) : records[id]!)
    }
}
