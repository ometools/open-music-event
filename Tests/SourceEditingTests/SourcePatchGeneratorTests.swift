import CustomDump
import Dependencies
import Foundation
import SourceEditing
import Testing

struct SourcePatchGeneratorTests {
    @Test
    func configuredGeneratorCanBeReadByRequestType() async throws {
        let patch = SourcePatch(
            fileChanges: [
                SourcePatchFileChange(
                    path: "events/test/event.yml",
                    kind: .modified,
                    oldContents: data("name: Old\n"),
                    newContents: data("name: New\n")
                )
            ]
        )

        let generated = try await withDependencies {
            $0[SourcePatchGeneratorKey<TestPatchRequest>.self] = SourcePatchGenerator { request in
                #expect(request == TestPatchRequest(name: "New"))
                return patch
            }
        } operation: {
            @Dependency(SourcePatchGeneratorKey<TestPatchRequest>.self) var generator
            return try await generator.generate(TestPatchRequest(name: "New"))
        }

        expectNoDifference(generated, patch)
    }

    @Test
    func liveGeneratorMaterializesRewritesDiffsAndCleansUpWorkingTree() async throws {
        let fixture = try SourcePatchGeneratorFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile("events/test/event.yml", contents: "name: Old\n")
        try fixture.writeFile("events/test/deleted.md", contents: "Delete me\n")
        try fixture.writeFile("events/test/unchanged.md", contents: "Same\n")
        let repositoryURL = fixture.repositoryURL
        let rootURL = fixture.rootURL

        let patch = try await withDependencies {
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: rootURL
            )
        } operation: {
            let generator = SourcePatchGenerator<TestPatchRequest>.live(
                resolve: { request in
                    SourcePatchSource(
                        repositoryURL: repositoryURL,
                        relativePath: "events/test",
                        value: request.name
                    )
                },
                rewrite: { name, workingURL in
                    try "name: \(name)\n".write(
                        to: workingURL.appending(path: "event.yml"),
                        atomically: true,
                        encoding: .utf8
                    )
                    try "Added\n".write(
                        to: workingURL.appending(path: "added.md"),
                        atomically: true,
                        encoding: .utf8
                    )
                    try FileManager.default.removeItem(
                        at: workingURL.appending(path: "deleted.md")
                    )
                }
            )

            return try await generator.generate(TestPatchRequest(name: "New"))
        }

        expectNoDifference(
            patch,
            SourcePatch(
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
        )

        let originalContents = try String(
            contentsOf: fixture.repositoryURL.appending(path: "events/test/event.yml"),
            encoding: .utf8
        )
        expectNoDifference(originalContents, "name: Old\n")

        let rootContents = try FileManager.default.contentsOfDirectory(
            atPath: fixture.rootURL.path
        )
        expectNoDifference(rootContents, ["repository"])
    }

    @Test
    func liveGeneratorCanReadExistingSourceBeforeUpdating() async throws {
        let fixture = try SourcePatchGeneratorFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile("events/test/event.yml", contents: "name: Old\n")
        let repositoryURL = fixture.repositoryURL
        let rootURL = fixture.rootURL

        let patch = try await withDependencies {
            $0.uuid = .incrementing
            $0.sourceWorkingTreeMaterializer = .live(
                temporaryDirectoryURL: rootURL
            )
        } operation: {
            let generator = SourcePatchGenerator<TestPatchRequest>.live(
                resolveLocation: { _ in
                    SourcePatchLocation(
                        repositoryURL: repositoryURL,
                        relativePath: "events/test"
                    )
                },
                read: { sourceURL in
                    try String(
                        contentsOf: sourceURL.appending(path: "event.yml"),
                        encoding: .utf8
                    )
                },
                update: { existing, request in
                    existing.replacingOccurrences(
                        of: "Old",
                        with: request.name
                    )
                },
                rewrite: { updated, workingURL in
                    try updated.write(
                        to: workingURL.appending(path: "event.yml"),
                        atomically: true,
                        encoding: .utf8
                    )
                }
            )

            return try await generator.generate(TestPatchRequest(name: "New"))
        }

        expectNoDifference(
            patch,
            SourcePatch(
                fileChanges: [
                    SourcePatchFileChange(
                        path: "events/test/event.yml",
                        kind: .modified,
                        oldContents: data("name: Old\n"),
                        newContents: data("name: New\n")
                    )
                ]
            )
        )
    }
}

private struct TestPatchRequest: Equatable, Sendable {
    var name: String
}

private final class SourcePatchGeneratorFixture {
    let repositoryURL: URL
    let rootURL: URL

    init() throws {
        self.rootURL = FileManager.default.temporaryDirectory
            .appending(path: "SourcePatchGeneratorTests-\(UUID().uuidString)")
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
