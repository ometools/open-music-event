import CustomDump
import Dependencies
import Foundation
import SourceEditing
import Testing

struct SourceWorkingTreeMaterializerTests {
    @Test
    func materializeCopiesRepositoryAndTargetsRelativePath() throws {
        let fixture = try SourceWorkingTreeMaterializerFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile("README.md", contents: "original readme")
        try fixture.writeFile("events/test-event/event.yml", contents: "name: Test")

        let tree = try fixture.materializer.materialize(
            fixture.repositoryURL,
            "events/test-event"
        )

        defer { try? FileManager.default.removeItem(at: tree.workingRepositoryURL) }
        expectNoDifference(tree.originalRepositoryURL, fixture.repositoryURL.standardizedFileURL)
        expectNoDifference(tree.relativePath, "events/test-event")
        expectNoDifference(
            tree.originalURL,
            fixture.repositoryURL.appending(path: "events/test-event").standardizedFileURL
        )
        expectNoDifference(
            tree.workingURL,
            tree.workingRepositoryURL.appending(path: "events/test-event").standardizedFileURL
        )
        #expect(FileManager.default.fileExists(atPath: tree.workingURL.appending(path: "event.yml").path))

        try "changed".write(
            to: tree.workingURL.appending(path: "event.yml"),
            atomically: true,
            encoding: .utf8
        )
        let originalContents = try String(
            contentsOf: fixture.repositoryURL.appending(path: "events/test-event/event.yml"),
            encoding: .utf8
        )
        expectNoDifference(originalContents, "name: Test")
    }

    @Test
    func materializeWithoutRelativePathTargetsRepositoryRoot() throws {
        let fixture = try SourceWorkingTreeMaterializerFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile("event.yml", contents: "name: Root")

        let tree = try fixture.materializer.materialize(fixture.repositoryURL, nil)

        defer { try? FileManager.default.removeItem(at: tree.workingRepositoryURL) }
        expectNoDifference(tree.relativePath, nil)
        expectNoDifference(tree.originalURL, tree.originalRepositoryURL)
        expectNoDifference(tree.workingURL, tree.workingRepositoryURL)
        #expect(FileManager.default.fileExists(atPath: tree.workingURL.appending(path: "event.yml").path))
    }

    @Test
    func materializeNormalizesDuplicateSeparators() throws {
        let fixture = try SourceWorkingTreeMaterializerFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile("events/test-event/event.yml", contents: "name: Test")

        let tree = try fixture.materializer.materialize(
            fixture.repositoryURL,
            "events//test-event"
        )

        defer { try? FileManager.default.removeItem(at: tree.workingRepositoryURL) }
        expectNoDifference(tree.relativePath, "events/test-event")
        #expect(FileManager.default.fileExists(atPath: tree.workingURL.appending(path: "event.yml").path))
    }

    @Test
    func repeatedDomainUUIDStillCreatesIndependentWorkingTrees() throws {
        let fixture = try SourceWorkingTreeMaterializerFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile("event.yml", contents: "name: Root")
        let repeatedUUID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )

        let (first, second) = try withDependencies {
            $0.uuid = .constant(repeatedUUID)
        } operation: {
            (
                try fixture.materializer.materialize(fixture.repositoryURL, nil),
                try fixture.materializer.materialize(fixture.repositoryURL, nil)
            )
        }
        defer {
            try? FileManager.default.removeItem(at: first.workingRepositoryURL)
            try? FileManager.default.removeItem(at: second.workingRepositoryURL)
        }

        #expect(first.workingRepositoryURL != second.workingRepositoryURL)
        #expect(FileManager.default.fileExists(atPath: first.workingURL.appending(path: "event.yml").path))
        #expect(FileManager.default.fileExists(atPath: second.workingURL.appending(path: "event.yml").path))
    }

    @Test
    func materializeRejectsAbsoluteRelativePath() throws {
        let fixture = try SourceWorkingTreeMaterializerFixture()
        defer { fixture.cleanUp() }

        let error = #expect(throws: SourceWorkingTreeMaterializerError.self) {
            try fixture.materializer.materialize(fixture.repositoryURL, "/events/test-event")
        }
        expectNoDifference(error, .invalidRelativePath("/events/test-event"))
    }

    @Test
    func materializeRejectsEscapingRelativePath() throws {
        let fixture = try SourceWorkingTreeMaterializerFixture()
        defer { fixture.cleanUp() }

        let error = #expect(throws: SourceWorkingTreeMaterializerError.self) {
            try fixture.materializer.materialize(fixture.repositoryURL, "events/../other")
        }
        expectNoDifference(error, .invalidRelativePath("events/../other"))
    }

    @Test
    func materializeRejectsMissingRepository() throws {
        let fixture = try SourceWorkingTreeMaterializerFixture()
        defer { fixture.cleanUp() }
        let missingRepositoryURL = fixture.rootURL.appending(path: "missing")

        let error = #expect(throws: SourceWorkingTreeMaterializerError.self) {
            try fixture.materializer.materialize(missingRepositoryURL, nil)
        }
        expectNoDifference(error, .sourceRepositoryMissing(missingRepositoryURL.standardizedFileURL))
    }
}

private final class SourceWorkingTreeMaterializerFixture {
    let materializer: SourceWorkingTreeMaterializer
    let repositoryURL: URL
    let rootURL: URL

    init() throws {
        self.rootURL = FileManager.default.temporaryDirectory
            .appending(path: "SourceWorkingTreeMaterializerTests-\(UUID().uuidString)")
            .standardizedFileURL
        self.repositoryURL = rootURL.appending(path: "repository").standardizedFileURL
        self.materializer = SourceWorkingTreeMaterializer.live(temporaryDirectoryURL: rootURL)

        try FileManager.default.createDirectory(
            at: repositoryURL,
            withIntermediateDirectories: true
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func writeFile(_ path: String, contents: String) throws {
        let url = repositoryURL.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
