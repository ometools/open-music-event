import CustomDump
import Dependencies
import Foundation
import SourceEditing
import Testing

struct SourcePatchApplierTests {
    @Test
    func liveApplierAppliesAddedModifiedAndDeletedFiles() throws {
        let fixture = try SourcePatchApplierFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile("events/test/event.yml", contents: "name: Old\n")
        try fixture.writeFile("events/test/deleted.md", contents: "Delete me\n")
        try fixture.writeFile("events/test/unchanged.md", contents: "Same\n")

        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/test/added.md",
                    kind: .added,
                    newContents: data("Added\n")
                ),
                SourcePatchFileChange(
                    path: "events/test/deleted.md",
                    kind: .deleted,
                    oldContents: data("Delete me\n")
                ),
                SourcePatchFileChange(
                    path: "events/test/event.yml",
                    kind: .modified,
                    oldContents: data("name: Old\n"),
                    newContents: data("name: New\n")
                ),
            ]
        )
        try SourcePatchApplier.live.apply(patch, fixture.repositoryURL)
        try SourcePatchApplier.live.apply(patch, fixture.repositoryURL)

        expectNoDifference(
            try fixture.readFile("events/test/added.md"),
            "Added\n"
        )
        expectNoDifference(
            try fixture.readFile("events/test/event.yml"),
            "name: New\n"
        )
        expectNoDifference(
            try fixture.readFile("events/test/unchanged.md"),
            "Same\n"
        )
        #expect(!fixture.fileExists("events/test/deleted.md"))
    }

    @Test
    func liveApplierFailsWithoutPartiallyApplyingStalePatch() throws {
        let fixture = try SourcePatchApplierFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile("events/test/added.md", contents: "existing\n")
        try fixture.writeFile("events/test/event.yml", contents: "name: Drifted\n")

        let error = #expect(throws: SourcePatchApplierError.self) {
            try SourcePatchApplier.live.apply(
                SourcePatch(
                    fileChanges: [
                        SourcePatchFileChange(
                            path: "events/test/new.md",
                            kind: .added,
                            newContents: data("New file\n")
                        ),
                        SourcePatchFileChange(
                            path: "events/test/event.yml",
                            kind: .modified,
                            oldContents: data("name: Old\n"),
                            newContents: data("name: New\n")
                        ),
                    ]
                ),
                fixture.repositoryURL
            )
        }
        expectNoDifference(error, .staleFile(path: "events/test/event.yml"))
        #expect(!fixture.fileExists("events/test/new.md"))
        expectNoDifference(
            try fixture.readFile("events/test/event.yml"),
            "name: Drifted\n"
        )
    }

    @Test
    func liveApplierRejectsAddedFileThatAlreadyExists() throws {
        let fixture = try SourcePatchApplierFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile("events/test/event.yml", contents: "name: Old\n")

        let error = #expect(throws: SourcePatchApplierError.self) {
            try SourcePatchApplier.live.apply(
                SourcePatch(
                    fileChanges: [
                        SourcePatchFileChange(
                            path: "events/test/event.yml",
                            kind: .added,
                            newContents: data("name: New\n")
                        )
                    ]
                ),
                fixture.repositoryURL
            )
        }
        expectNoDifference(error, .fileAlreadyExists(path: "events/test/event.yml"))
        expectNoDifference(
            try fixture.readFile("events/test/event.yml"),
            "name: Old\n"
        )
    }

    @Test
    func liveApplierRejectsMissingPatchContents() throws {
        let fixture = try SourcePatchApplierFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile("events/test/event.yml", contents: "name: Old\n")

        let missingOldContents = #expect(throws: SourcePatchApplierError.self) {
            try SourcePatchApplier.live.apply(
                SourcePatch(
                    fileChanges: [
                        SourcePatchFileChange(
                            path: "events/test/event.yml",
                            kind: .modified,
                            newContents: data("name: New\n")
                        )
                    ]
                ),
                fixture.repositoryURL
            )
        }
        expectNoDifference(
            missingOldContents,
            .missingOldContents(path: "events/test/event.yml")
        )

        let missingNewContents = #expect(throws: SourcePatchApplierError.self) {
            try SourcePatchApplier.live.apply(
                SourcePatch(
                    fileChanges: [
                        SourcePatchFileChange(
                            path: "events/test/new.yml",
                            kind: .added
                        )
                    ]
                ),
                fixture.repositoryURL
            )
        }
        expectNoDifference(
            missingNewContents,
            .missingNewContents(path: "events/test/new.yml")
        )
    }

    @Test
    func liveApplierRejectsEscapingPatchPaths() throws {
        let fixture = try SourcePatchApplierFixture()
        defer { fixture.cleanUp() }

        let error = #expect(throws: SourcePatchApplierError.self) {
            try SourcePatchApplier.live.apply(
                SourcePatch(
                    fileChanges: [
                        SourcePatchFileChange(
                            path: "events/../outside.yml",
                            kind: .added,
                            newContents: data("outside\n")
                        )
                    ]
                ),
                fixture.repositoryURL
            )
        }
        expectNoDifference(
            error,
            .invalidPatchPath("events/../outside.yml")
        )
    }

    @Test
    func dependencyDefaultsToLiveApplier() throws {
        let fixture = try SourcePatchApplierFixture()
        defer { fixture.cleanUp() }

        try withDependencies {
            $0.sourcePatchApplier = .live
        } operation: {
            @Dependency(\.sourcePatchApplier) var applier
            try applier.apply(
                SourcePatch(
                    fileChanges: [
                        SourcePatchFileChange(
                            path: "events/test/event.yml",
                            kind: .added,
                            newContents: data("name: New\n")
                        )
                    ]
                ),
                fixture.repositoryURL
            )
        }

        expectNoDifference(
            try fixture.readFile("events/test/event.yml"),
            "name: New\n"
        )
    }
}

private final class SourcePatchApplierFixture {
    let repositoryURL: URL
    let rootURL: URL

    init() throws {
        self.rootURL = FileManager.default.temporaryDirectory
            .appending(path: "SourcePatchApplierTests-\(UUID().uuidString)")
            .standardizedFileURL
        self.repositoryURL = rootURL.appending(path: "repository").standardizedFileURL

        try FileManager.default.createDirectory(
            at: repositoryURL,
            withIntermediateDirectories: true
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func fileExists(_ path: String) -> Bool {
        FileManager.default.fileExists(
            atPath: repositoryURL.appending(path: path).path
        )
    }

    func readFile(_ path: String) throws -> String {
        try String(
            contentsOf: repositoryURL.appending(path: path),
            encoding: .utf8
        )
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

private func data(_ string: String) -> Data {
    Data(string.utf8)
}
