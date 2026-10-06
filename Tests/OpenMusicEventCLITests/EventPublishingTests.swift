import ATProto
import ArgumentParser
import CustomDump
import Foundation
import OpenMusicEventSource
import Testing

@testable import OpenMusicEventCLI

@Suite struct EventPublishingTests {
    let owner = DID("did:plc:wickedwoods")!
    let mapping = "2026=at://did:plc:wickedwoods/events.openmusic.event/3jzfcijpj2z2a"

    @Test func `source publication keeps the selected event identity and creation time on retry`() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: source) }
        for year in ["2025", "2026"] {
            let directory = source.appendingPathComponent("events/\(year)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "name: Wicked Woods \(year)\ntimeZone: America/Denver\nstartDate: '\(year)-09-04'\n"
                .write(to: directory.appendingPathComponent("event.yml"), atomically: true, encoding: .utf8)
        }
        // Publishing 2026 does not also publish the other year in the source repository.
        let input = try EventPublicationInput(argument: mapping)
        let created = try #require(ISO8601DateFormatter().date(from: "2026-10-06T02:00:00Z"))
        let records = try EventPublicationLoader.load(sourceURL: source, inputs: [input], account: owner, createdAt: created)
        expectNoDifference(records.count, 1)
        let event = try #require(records.first)
        expectNoDifference(event.id, input.uri)
        expectNoDifference(event.name, "Wicked Woods 2026")
        expectNoDifference(event.createdAt.rawValue, "2026-10-06T02:00:00Z")
        expectNoDifference(records, try EventPublicationLoader.load(sourceURL: source, inputs: [input], account: owner, createdAt: created))
        // A duplicate mapping fails before any publisher can receive these records.
        #expect(throws: OpenMusicEventSourcePublicationCompiler.CompilationError.duplicateSourceDirectory("2026")) {
            try EventPublicationLoader.load(sourceURL: source, inputs: [input, input], account: owner, createdAt: created)
        }
        #expect(throws: OpenMusicEventSourcePublicationCompiler.CompilationError.unknownSourceDirectory("missing")) {
            try EventPublicationLoader.load(sourceURL: source,
                inputs: [EventPublicationInput(argument: mapping.replacingOccurrences(of: "2026=", with: "missing="))],
                account: owner, createdAt: created)
        }
    }

    @Test func `mapping rejects non-event identities and mixed publishers`() throws {
        let input = try EventPublicationInput(argument: mapping)
        expectNoDifference(try EventPublicationInput.owner(of: [input]), owner)
        for invalid in [mapping.replacingOccurrences(of: "events.openmusic.event", with: "app.bsky.feed.post"),
                        mapping.replacingOccurrences(of: "3jzfcijpj2z2a", with: "not-a-tid")] {
            #expect(throws: (any Error).self) { try EventPublicationInput(argument: invalid) }
        }
        let other = try EventPublicationInput(argument: mapping.replacingOccurrences(of: "did:plc:wickedwoods", with: "did:plc:other"))
        #expect(throws: (any Error).self) { try EventPublicationInput.owner(of: [input, other]) }
    }

    @Test func `explicit session requires the publisher account and paired host options`() throws {
        let session = EventPublicationSession(did: owner, accessJwt: "fixture-token")
        try session.validate(owner: owner)
        #expect(throws: (any Error).self) { try session.validate(owner: DID("did:plc:other")!) }
        let arguments = ["/source", "--event", mapping, "--created-at", "2026-10-06T02:00:00Z", "--dry-run"]
        typealias Command = OpenMusicEventCommand.ProtocolRecords.PublishEvents
        _ = try Command.parse(arguments)
        for extra in [["--pds", "pds.example"], ["--session-file", "/session.json"],
                      ["--pds", "https://pds.example", "--session-file", "/session.json"]] {
            #expect(throws: (any Error).self) { try Command.parse(arguments + extra) }
        }
    }
}
