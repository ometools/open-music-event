import ATProto
import CustomDump
import Foundation
import OpenMusicEventDatabase
import OpenMusicEventLexicon
import OpenMusicEventSource
import SQLiteData
import Testing

@testable import OpenMusicEventSourceEditing

@Suite
struct EventRecordPublicationTests {
    let account = DID("did:plc:organizer")!
    let imageBytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=")!

    func event(_ key: String = "3mrdbziccpcah", withImage: Bool = true) throws -> Event {
        var event = try Event(
            id: #require(Event.ID("at://\(account)/events.openmusic.event/\(key)")),
            name: "Testival", createdAt: "2026-07-01T12:00:00Z",
            timeZone: #require(TimeZone(identifier: "America/Denver"))
        )
        event.description = "Edited in the app before publication"
        if withImage {
            event.media = [.known(.image(OME.Image(
                source: .known(.blob(localImageBlob(imageBytes, mimeType: .png))),
                alt: .init(rawValue: "A white Testival image"), role: .known(.hero)
            )))]
        }
        return event
    }

    func review(_ events: [Event]) throws -> EventRecordPublication {
        try .prepare(events: events, account: account) { _ in imageBytes }
    }

    @Test func `review preserves edited fields image metadata and stable identities`() throws {
        let rich = try event()
        let minimal = try event("3mrdbziccpcaq", withImage: false)
        let first = try review([minimal, rich])
        expectNoDifference(first, try review([rich, minimal]))
        expectNoDifference(first.records[0].event, rich)
        expectNoDifference(first.records[0].images[0].bytes, imageBytes)
        expectNoDifference(first.records[0].payload, try rich.encodeLexicon())
        #expect(first.authorization.permissions.contains(.blob("image/png")))
        expectNoDifference(first.authorization.account, .did(account))
    }

    @Test func `review rejects duplicate identities and a different publisher`() throws {
        let record = try event()
        #expect(throws: EventRecordPublication.PublicationError.duplicateEvent(record.id)) {
            try review([record, record])
        }
        #expect(throws: EventRecordPublication.PublicationError.wrongAccount) {
            try EventRecordPublication.prepare(events: [record], account: DID("did:plc:other")!) { _ in imageBytes }
        }
    }

    @Test func `review rejects missing corrupt and mismatched image bytes`() throws {
        let record = try event()
        #expect(throws: EventRecordPublication.PublicationError.self) {
            try EventRecordPublication.prepare(events: [record], account: account) { blob in
                throw EventRecordPublication.PublicationError.missingImage(blob.ref)
            }
        }
        #expect(throws: EventRecordPublication.PublicationError.self) {
            try EventRecordPublication.prepare(events: [record], account: account) { _ in Data("not an image".utf8) }
        }
        var bytes = imageBytes
        bytes[30] ^= 1
        #expect(throws: EventRecordPublication.PublicationError.self) {
            try EventRecordPublication.prepare(events: [record], account: account) { _ in bytes }
        }
    }

    @Test func `uploads image before writing and verifies the record before reporting success`() async throws {
        let review = try review([event()])
        let network = PublicationNetwork()
        let result = try await network.publisher.publish(review)
        let calls = await network.calls
        expectNoDifference(calls, ["upload", "put", "read"])
        expectNoDifference(result.failures, [:])
        let receipt = try #require(result.receipts.first)
        expectNoDifference(receipt.id, review.records[0].id)
        expectNoDifference(receipt.images, review.records[0].images.map(\.blob))
        expectNoDifference(receipt.payloadSHA256, review.records[0].payloadSHA256)
    }

    @Test func `image upload failure does not publish an imageless event`() async throws {
        let review = try review([event()])
        let network = PublicationNetwork(failure: .upload)
        let result = try await network.publisher.publish(review)
        let calls = await network.calls
        expectNoDifference(calls, ["upload"])
        #expect(result.receipts.isEmpty)
        #expect(result.failures[review.records[0].id] != nil)
    }

    @Test func `write failure after upload can retry without changing event or image identity`() async throws {
        let review = try review([event()])
        let network = PublicationNetwork(failure: .put)
        let failed = try await network.publisher.publish(review)
        #expect(failed.receipts.isEmpty)
        await network.clearFailure()
        let retried = try await network.publisher.publish(review)
        expectNoDifference(retried.receipts.map(\.id), review.records.map(\.id))
        let calls = await network.calls
        expectNoDifference(calls, ["upload", "put", "upload", "put", "read"])
        #expect(await network.records.count == 1)
    }

    @Test func `readback mismatch is not reported as verified publication`() async throws {
        let review = try review([event()])
        let network = PublicationNetwork(failure: .read)
        let result = try await network.publisher.publish(review)
        #expect(result.receipts.isEmpty)
        #expect(result.failures[review.records[0].id] != nil)
    }

    @Test func `replacing an image publishes new bytes under the same event identity`() async throws {
        let original = try event()
        let first = try review([original])
        let network = PublicationNetwork()
        let initial = try await network.publisher.publish(first)

        // Replace the local form's image and text without changing its URI or creation date.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let replacementBytes = try Data(contentsOf: root.appending(path:
            "Sources/OpenMusicEventApp/Resources/UIAutomation/TestivalSource/events/testival-2026/maps/safety-map.png"
        ))
        let replacementBlob = localImageBlob(replacementBytes, mimeType: .png)
        var edited = original
        edited.description = "Replacement published from the Event form"
        edited.media = [.known(.image(OME.Image(
            source: .known(.blob(replacementBlob)), alt: "Testival safety map", role: .known(.hero)
        )))]
        let replacement = try EventRecordPublication.prepare(events: [edited], account: account) { _ in
            replacementBytes
        }
        let updated = try await network.publisher.publish(replacement)
        #expect(updated.failures.isEmpty)
        expectNoDifference(updated.receipts.map(\.id), initial.receipts.map(\.id))
        expectNoDifference(replacement.records[0].event.createdAt, first.records[0].event.createdAt)
        #expect(updated.receipts[0].cid != initial.receipts[0].cid)
        #expect(updated.receipts[0].images[0].ref != initial.receipts[0].images[0].ref)
        expectNoDifference(updated.receipts[0].images, [replacementBlob])
        expectNoDifference(first.records[0].images[0].bytes, imageBytes)
        #expect(await network.records.count == 1)
        let published = await network.records[original.id]
        expectNoDifference(published, try edited.encodeLexicon())
    }

    @Test func `one failed image does not hide the independently published minimal event`() async throws {
        let review = try review([event(), event("3mrdbziccpcaq", withImage: false)])
        let network = PublicationNetwork(failure: .upload)
        let result = try await network.publisher.publish(review)
        expectNoDifference(result.receipts.map(\.id), [review.records[1].id])
        expectNoDifference(Set(result.failures.keys), [review.records[0].id])
    }

    @Test func `receipt migration preserves existing event data and retains verified blob metadata`() async throws {
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database, upTo: "Key OpenMusicEvent relationships by record URI")
        let original = try event()
        try await database.write { try Event.insert { original }.execute($0) }
        try migrator.migrate(database)
        let network = PublicationNetwork()
        let result = try await network.publisher.publish(review([original]))
        let receipt = try #require(result.receipts.first)
        try await database.write { try EventRecordPublicationReceipt.upsert { receipt }.execute($0) }
        let saved = try await database.read { try EventRecordPublicationReceipt.find(original.id).fetchOne($0) }
        expectNoDifference(saved, receipt)
        let savedEvent = try await database.read { try Event.find(original.id).fetchOne($0) }
        expectNoDifference(savedEvent, original)
    }

    @Test func `source import creates rich and minimal canonical events and reimport preserves app edits`() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appending(path: "Sources/OpenMusicEventApp/Resources/UIAutomation/TestivalSource")
        let validated = try await OpenMusicEventSourceValidator(.init(
            source: source.path, organizerID: account
        )).validate()
        let database = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        OME.DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(database)
        let ids = try await CanonicalSourceEventImport.insert(
            validated, at: Date(timeIntervalSince1970: 1_780_000_000), in: database
        )
        let imported = try await database.read { try Event.all.fetchAll($0) }
        #expect(ids.count == 2)
        let minimal = try #require(imported.first { $0.name == "Minimal Event" })
        #expect(minimal.description == nil && minimal.media == nil && minimal.start == nil)
        var rich = try #require(imported.first { $0.name == "Testival 2026" })
        #expect(rich.timeZone.identifier == "America/Denver")
        #expect(rich.locations?.first?.name == "1 Fixture Road, Denver, CO 80202")
        #expect(rich.links?.count == 3)
        rich.description = "Changed in the Event form"
        let edited = rich
        try await database.write { try Event.upsert { edited }.execute($0) }
        let again = try await CanonicalSourceEventImport.insert(validated, at: Date(), in: database)
        expectNoDifference(again, ids)
        let saved = try await database.read { try Event.find(edited.id).fetchOne($0) }
        expectNoDifference(saved, edited)
    }
}

actor PublicationNetwork {
    enum Failure: Error { case upload, put, read }
    var failure: Failure?
    var calls: [String] = []
    var records: [Event.ID: Lexicon.JSONValue] = [:]
    var cids: [Event.ID: ATProto.CID] = [:]

    init(failure: Failure? = nil) { self.failure = failure }
    func clearFailure() { failure = nil }

    nonisolated var publisher: EventRecordPublisher {
        .init(
            upload: { image, _ in try await self.upload(image) },
            put: { record, _ in try await self.put(record) },
            read: { id, _ in try await self.read(id) }
        )
    }

    func upload(_ image: EventRecordPublication.Image) throws -> ATProto.Blob {
        calls.append("upload")
        if failure == .upload { throw Failure.upload }
        return image.blob
    }
    func put(_ record: EventRecordPublication.Record) throws -> ATProto.Repository.WriteRecordOutput {
        calls.append("put")
        if failure == .put { throw Failure.put }
        records[record.id] = record.payload
        // A content-derived test receipt, not a substitute for a real PDS DAG-CBOR CID.
        let cid = localImageBlob(try JSONEncoder().encode(record.payload), mimeType: .png).ref
        cids[record.id] = cid
        return .init(uri: record.id, cid: cid)
    }
    func read(_ id: Event.ID) throws -> ATProto.Repository.ListedRecord<Lexicon.JSONValue> {
        calls.append("read")
        return .init(uri: id, cid: cids[id]!, value: failure == .read ? .null : records[id]!)
    }
}
